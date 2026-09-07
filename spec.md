# Argus アプリ仕様（コード起点 / 2026-08-20）

この文書はリポジトリ内の実装（特に `lib/` 配下）から読み取った事実ベースの仕様です。ランディングページ用コピーや追加開発時の参照に使えます。

---

## 1. プロダクト概要
- 目的: GeoJSON で定義された安全圏からの離脱を端末内で検知し、音・バイブ・ローカル通知で即時警告するジオフェンスアプリ。
- 想定利用: 認知症徘徊対策、警備エリア監視、養護施設内の見守りなど「エリア外に出たら即アラート」が要るケース。
- 対応プラットフォーム: Flutter 3 / Dart 3.2+。Android 9+ / iOS 15+（Foreground / 背景位置情報前提）。
- 同期/クラウドなし。GeoJSON は手動読み込み（ファイル or QR）。位置情報は Geolocator の単一ストリームで取得する。

## 2. ユースケース価値
- 端末完結の監視（ネット不要）で通信遮断時も動作。
- QR コード経由で GeoJSON を安全に配布（ARGUS専用差分圧縮または汎用gzip圧縮）。
- 「離脱確定までの猶予」(サンプル数 + 経過秒数) を設定でき、GPS ノイズによる誤検知を抑制。
- 離脱時は無音の高重要度通知＋アラーム音＋連続バイブで確実に気付かせる。
- Developer mode でエリア内でも距離・方位を確認でき、デバッグ／捜索補助に使える。

## 3. モジュール構成（主要ファイル）
- `lib/main.dart`: エントリポイント、`AppController.bootstrap()` を起動。
- `lib/app_controller.dart`: アプリ全体のオーケストレーター。設定ロード、GeoJSON 読み込み、位置監視開始/停止、状態通知、ログ保持、エラー提示を司る。
- `lib/state_machine/state_machine.dart` + `state.dart` + `hysteresis_counter.dart`: ジオフェンス状態遷移ロジック。
- `lib/geo/geo_model.dart` / `area_index.dart` / `point_in_polygon.dart`: GeoJSON パーサ・境界インデックス・点とポリゴン判定/距離/方位計算。
- `lib/platform/location_service.dart`: Geolocator を用いた位置ストリーム抽象＆実装。
- `lib/platform/notifier.dart`: ローカル通知、同梱アラーム音 (`assets/sounds/alarm.mp3` / Android `res/raw/alarm.mp3`)、連続バイブ制御。
- `lib/io/config.dart` / `file_manager.dart`: 設定 JSON の永続化、GeoJSON ファイルピック。
- `lib/io/logger.dart` / `log_entry.dart`: 状態変化・GPS 受信の JSON レコード化（メモリ内）。
- `lib/qr/geojson_qr_codec.dart`: GeoJSON の QR エンコード/デコード（gzip 圧縮、外部CLI依存なし）。
- `lib/ui/home_page.dart` / `settings_page.dart` / `qr_scanner_page.dart`: 画面（Material3）。

## 4. ランタイムフロー
1) 起動: `AppController.bootstrap()` で設定を `config.json`（無ければ `assets/config/default_config.json`）から読み込み、通知音量設定。GeoJSON 未ロードなので状態は `waitGeoJson` で開始。  
2) 権限要求: 通知権限は警告を見逃さないための setup 対象。監視開始のブロック条件は位置サービス有効 + Always 位置権限で、PermissionCoordinator が foreground から background の順に確認・要求する。拒否/永久拒否時は app/location settings への導線を出す。
3) GeoJSON 取込:
   - ファイル: `FileManager.pickGeoJsonFile()` で `.geojson/.json/.bin` を選択しパース→`GeoModel`→`AreaIndex` 構築。ファイル名を `.geojson` 拡張子に正規化して保持。
   - QR: `agz1:` / `gjz1:` テキストを復元→gzip 伸長→構造バリデーション→一時ファイル保存（次回起動で消去）。`agz1` は元ファイル名も復元する。
   ロード成功後の状態は `waitStart`、`navigationEnabled` は false にリセット、アラーム停止。
4) 監視開始: `startMonitoring()` で Geolocator ストリーム購読開始。開始条件（GeoJSON・設定・権限・Androidのアラーム音量）はすべて `startMonitoring()` 内で判定し、`MonitoringStartOutcome` を返す。呼び出し元に判定を任せないため、別の入口から安全条件を迂回できず、確認から開始までの間に音量を下げられても検出できる。`starting → acquiring → active` の監視ライフサイクルを持つ。`sampleIntervalS['fast']`（デフォルト 3 秒）間隔・距離フィルタ 0m・`LocationAccuracy.best`。
5) 評価ループ: 各 `LocationFix` を `StateMachine.evaluate()` に通し、UI/ログ/通知に反映。OUTER 確定時に通知＋アラーム。再入時に停止通知。
6) GPS監視: 最終fixから `max(15秒, 取得間隔×3)` が経過、または位置ストリームがエラー/終了した場合は警告通知と短い振動を出し、1/2/4/8/16/30秒のバックオフで再接続する。途絶が続くあいだ既定60秒間隔で警告を出し直し、経過時間を本文に含める（iOSは通知音とtimeSensitiveでバックグラウンドでも届かせる）。fix復帰時に警告と反復を解除する。経過時間は監視セッションが持つ単調増加クロックで測り、位置サービスの再接続をまたいでも巻き戻らない。再開前に監視権限を再確認し、権限失効時または再開が連続5回失敗した場合は自動再接続を打ち切って原因を表示する（アプリのレジュームで再試行）。
7) 停止/終了: `stopMonitoring()` で購読解除・Geolocator 停止。アプリ detach 時に QR 由来の一時 GeoJSON を削除。強制終了後の自動復元は行わない。

## 5. 中核ドメイン仕様
### 5.1 GeoJSON 取り込み
- 対応タイプ: FeatureCollection の穴なし Polygon / MultiPolygon。穴は黙って無視せずエラーにする。座標範囲、有限値、始終点閉包、3つ以上の異なる頂点、0でない面積を検証する。properties の `name`/`version` は読み取りのみ未使用。
- 上限: UTF-8で1MB、Polygon 10個、1 Polygon 5,000頂点、合計10,000頂点。QRのgzip展開後も1MBで打ち切る。
- ファイルピック時はクエリ/フラグメントを除去したファイル名を `.geojson` に正規化して記憶。
- ロード失敗時は `FormatException`/その他を Snackbar で表示し、状態は維持。
- 設定・GeoJSON・QRの変更は監視中には受け付けない。停止後の新規ロード時に AreaIndex を再構築する。開発者モードは表示の切り替えのみで監視挙動に影響しないため、監視中も変更できる。

### 5.2 QR コーデック（ライブラリ）
- 標準エンコード: 単一Feature・単一Polygonの外周座標をscale 6の差分列へ変換し、元ファイル名とともに `a3` 本文へ格納する。gzip(level=9) → Base64URL（= 無パディング）→ `agz1:<payload>` とし、画像名は `QR_<元名>.png`。
- 互換形式: `gjz1:<payload>[#hash]` の生成APIと読み込みを維持する。`gjz1` のSHA-256検証も従来どおり行う。
- デコード: `agz1` はGeoJSONと埋め込みファイル名を復元し、`gjz1` はGeoJSONのみ復元する。
- 一時ファイル: QR取込時の実体は `temp_geojson_<timestamp>.geojson` として安全に管理し、表示名には `agz1` 内の元ファイル名を使う。次回起動(detached)または再読込時に削除する。

### 5.3 権限
- 通知: 警告を見逃さないための setup 対象。拒否時は app settings への導線を表示するが、監視開始ブロック条件そのものではない。
- 位置: 位置サービス有効 + `locationAlways` を監視開始条件とする。`whileInUse` から foreground → background の順に要求する。iOSの事前説明は単一の「続ける」のみとし、拒否時は自動遷移せず明示的な app settings 導線を表示する。Androidは従来どおり拒否後に app/location settings を開く。

### 5.4 位置サンプリング（`lib/platform/location_service.dart`）
- Android: Foreground Service 通知チャンネル名「ARGUSバックグラウンド監視」、タイトル「ARGUSが位置情報を監視中です」、本文「画面を消しても位置情報の追跡は継続されます。」。`enableWakeLock: true`、`setOngoing: true`。
- iOS/macOS: `showBackgroundLocationIndicator: true`、`pauseLocationUpdatesAutomatically: false`、`allowBackgroundLocationUpdates: true`。
- Stream 値: `latitude/longitude/timestamp/accuracyMeters/monitoringElapsed` を `LocationFix` として配信。監視開始前の古い測位は除外する。

### 5.5 状態機械（`state_machine.dart`）
- 状態: `waitGeoJson` → `waitStart` → `inner / near / outerPending / outer / gpsBad`。
- 距離閾値: `innerBufferM`（デフォルト 30m）より内側で `near`、それ以上は `inner`。
- 測位の可用性: `accuracyMeters == null`・非有限・`> gpsAccuracyBadMeters`（デフォルト 40m）、または緯度経度が非有限・範囲外のとき `gpsBad`。使えない測位ではヒステリシスをリセットしない（エリア内に戻った証拠ではないため）。ただし直前が OUTER の場合は「外にいる前提」で最寄り境界距離だけ更新し OUTER を維持する。低精度fixでは警告を解除せず、精度が閾値内へ戻ったfixだけが `inner/near` に復帰できる。
- OUTER 確定条件: 最初の有効なエリア外判定から、単調増加する実経過時間で `leaveConfirmSeconds` 秒（デフォルト 10 秒）かつ `leaveConfirmSamples` 回（デフォルト 3）に到達すること。GPS timestampは確定時間に使わない。未達時は `outerPending`。
- ポリゴン探索: AreaIndex の軸平行バウンディングボックスで候補絞り込み、ray-cast で包含判定。最短距離/方位を常に計算し `StateSnapshot` に積む。
- ナビゲーション表示: OUTER になったタイミングで `navigationEnabled=true`。Developer mode ではエリア内でもナビ表示可。それ以外は OUTER 以降のみ距離/方位ヒントを UI に出す。

### 5.6 境界計算（`point_in_polygon.dart`）
- 包含判定: Ray casting（端点補正 ε=1e-12）。
- 最近傍点: 各辺の射影点を計算し、Haversine 距離最小の点を選択。
- 方位: Haversine を基に 0–360deg へ正規化。UI では 8 方位 (N/NE/…/NW) 併記。

### 5.7 通知・アラーム（`notifier.dart`）
- チャンネル: `argus_alerts_visual_v2` / `ARGUS警告`（Android importance max / 通知自体の音・バイブは無効）。タイトル「ARGUS警告」、本文「競技エリアから離れています。」。OUTER 通知 ID は `1001`。
- OUTER: ローカル通知＋同梱警報音のネイティブループ再生＋ネイティブ連続バイブを独立に開始する。1経路の失敗で他経路を止めず、失敗経路をwarningログへ残す。Android は `MediaPlayer` と `VibrationEffect`、iOS は `AVAudioPlayer` と `AudioServicesPlaySystemSound` を使用する。
- 復帰: OUTER 通知をキャンセルし、アラーム停止のみ。ログに “Returned to safe zone.” を出力。
- 音量: ユーザー設定 0.1–1.0（10–100%）を `AlarmPlayer` に反映（初期 0.5）。Android では監視開始前に端末のアラーム音量を確認し、`percent >= 0.5` なら開始可、50% 未満なら開始せず「５０％以上」警告と音設定への導線を出す。音量取得失敗時は warning ログを残し、監視開始はブロックしない。
- iOS警告音テスト: Settingsから現在のスライダー音量で音声だけを再生する。通知・バイブは発生させず、ホーム画面でも継続し、停止操作・Settings終了・監視開始・アプリ終了で停止する。
- 音設定: MethodChannel `argus/alarm` の `openSoundSettings` を呼ぶ。Android 側は `ACTION_SOUND_SETTINGS` を開き、失敗時は `ACTION_SETTINGS` にフォールバックする。

### 5.8 UI
- Home (`home_page.dart`): 大型ステータス円で状態表示（INNER/NEAR/OUTERに加え、開始中/GPS取得中/GPS停止/再接続中/停止中/失敗）。OUTER・OUTER_PENDING の警告中は監視状態でラベルと色を塗り替えず、ジオフェンス状態を主表示にしたまま監視状態を円内の副バッジで併記する。監視中は強制終了で監視が止まる注意を表示する。
- Settings (`settings_page.dart`): 設定フォーム（Inner buffer, GPS 精度閾値, Leave confirm サンプル/秒, Alarm 音量）。監視中は全設定をロックする。iOSでは警告音の開始・停止テストを表示する。
- QR Scanner (`qr_scanner_page.dart`): `mobile_scanner` で `agz1` / `gjz1` スキーム QR を読み取り、`AppController.reloadGeoJsonFromQr` へ連携。処理中オーバーレイとエラーバナーを表示。
- テーマ: Material3、Seed color Blue。文言は日本語中心で一部英語残り。

## 6. データ/設定リファレンス
- AppConfig (`io/config.dart`):
  - `inner_buffer_m`(double, 30.0) / `leave_confirm_samples`(int, 3) / `leave_confirm_seconds`(int, 10) / `gps_accuracy_bad_m`(double, 40.0) / `sample_interval_s.fast`(int, 3) / `alarm_volume`(double, 0.5、最小0.1)。
  - 保存先: ドキュメントディレクトリの `config.json`。読み込み失敗時はデフォルトを再生成。
- StateSnapshot (`state.dart`): `status`, `timestamp`, `distanceToBoundaryM`, `horizontalAccuracyM`, `geoJsonLoaded`, `notes`, `nearestBoundaryPoint(LatLng)`, `bearingToBoundaryDeg`。
- ログ:
  - UI ログ (`AppLogEntry`): 種別 debug/info/warning/error、200 件までメモリ保持（永続化なし）。
  - EventLogger: `location` と `state` を最大20,000件のメモリリングバッファへ追加。`exportJsonl()` で JSON 文字列を返すのみ。

## 7. 依存・アセット
- 主要パッケージ: geolocator, flutter_local_notifications, permission_handler, mobile_scanner, file_selector, provider, qr, image, crypto, package_info_plus, upgrader。
- CLI 依存: なし。QR エンコード/デコードは Dart 標準の gzip とアプリ依存パッケージのみで完結。
- アセット: `assets/config/default_config.json`（初期設定）、`assets/geojson/map.geojson`（サンプル／テスト用、アプリ起動時には自動ロードされない）、`assets/sounds/alarm.mp3`（警告音）、`icon.png`。

## 8. 品質・テスト
- `flutter analyze` / `flutter test` / `flutter test --coverage` を基本確認とし、カバレッジは 100% を目標にする。
- 自動テスト対象（抜粋）: 状態遷移とヒステリシス、GeoJSON パース/点とポリゴン計算、QR コーデック、AppController、Notifier、PermissionCoordinator、LocationService settings、Home / Settings / QR UI。
- Android 契約テスト: 音量 50% 境界、MethodChannel、通知チャンネル、Foreground Service 文言、権限順序、音設定導線を保護する。
- GPS、カメラ、file picker、通知プラグインなど実機/OS 境界は薄い wrapper として `coverage:ignore` を許容し、周辺 contract を Fake で検証する。

## 9. 強み（実装で裏付けられるポイント）
- ノイズ耐性: サンプル数＋経過秒数によるヒステリシスで誤検知を抑制しつつ、精度不良時も OUTER 維持・距離算出を試みる（`state_machine.dart`）。
- 詳細な距離/方位ガイダンス: 最近傍境界点と方位を常時計算し、OUTER で移動ヒントを出せる（`_buildNavHint`, `_cardinalFromBearing`）。
- オフライン配布: gzip 圧縮＋SHA-256 ハッシュ付き QRでエリアデータを物理的に配布可能（`qr/geojson_qr_codec.dart`）。
- フルアラート: 無音の高重要度通知＋同梱 MP3 のループアラーム音＋連続バイブで気付けるようにする。音量はユーザー設定反映。
- デベロッパーモード: エリア内でも距離/方位やログを確認でき、現地調査・検証に向く。

## 10. 弱み / リスク（現状コード由来）
- ストリーム前提: OS ネイティブ geofence を使わず Geolocator の高頻度ストリームに依存する。電池負荷と端末設定（省電力）に左右される。
- 外部依存: QR エンコード/デコードに外部CLIは不要。
- GeoJSON サポートの限定: 穴付きPolygonは安全のため読み込みを拒否する。1MB・Polygon数・頂点数の上限を超える大規模データも読み込めない。`geometry` 欠落・非対応geometry type・空の `features`/`MultiPolygon`・連続重複頂点も黙って読み飛ばさずエラーにし、エラーには該当Feature・Polygon・頂点の位置と実際の値を含める。
- 設定項目の遊休: `sample_distance_m` と `screen_wake_on_leave` は UI/ロジックで未使用。設定と実挙動が乖離する恐れ。
- ログ永続化なし: UI ログはメモリ 200 件のみ、EventLogger もメモリのみ。`FileManager.openLogFile()` は未使用で実ファイルに残らない。
- バックグラウンド挙動の限定: アプリ終了後の自動再開なし。起動後も GeoJSON を手動ロードしないと監視が始まらない（サンプル GeoJSON も自動読み込みしない）。
- UX/多言語: 文言が日英混在、アクセシビリティ配慮やローカライズは未実装。
- セキュリティ: ハッシュ検証は任意、署名なし。無効な GeoJSON は弾くが、改ざん防止はハッシュ頼み。

## 11. 運用メモ
- Android では Foreground Service 通知が常に出る想定。監視開始には位置サービス有効と「常に位置情報」許可が必須。
- iOS では Always 許可＋背景位置表示が有効化されている必要あり。拒否された場合の代替フローは無し。
- 設定やGeoJSONを変更する場合は、先に監視を停止する。
- 画面ロックや他アプリ利用中は背景監視を継続するが、アプリの強制終了やOSによるプロセス終了後は監視を自動復元しない。
- アプリ終了時（detached）に QR 由来の一時 GeoJSON を自動削除するため、永続利用にはファイルピックを使う。

---

上記は 2026-08-20 時点のコードを直接確認した内容です。挙動変更時は `lib/app_controller.dart`・`lib/state_machine/state_machine.dart`・`lib/platform/`・`lib/qr/geojson_qr_codec.dart` 周辺のロジック更新に合わせて改訂してください。
