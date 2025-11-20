# Argus アプリ仕様（コード起点 / 2025-11-17）

この文書はリポジトリ内の実装（特に `lib/` 配下）から読み取った事実ベースの仕様です。ランディングページ用コピーや追加開発時の参照に使えます。

---

## 1. プロダクト概要
- 目的: GeoJSON で定義された安全圏からの離脱を端末内で検知し、音・バイブ・ローカル通知で即時警告するジオフェンスアプリ。
- 想定利用: 認知症徘徊対策、警備エリア監視、養護施設内の見守りなど「エリア外に出たら即アラート」が要るケース。
- 対応プラットフォーム: Flutter 3 / Dart 3.2+。Android 9+ / iOS 15+（Foreground / 背景位置情報前提）。
- 同期/クラウドなし。GeoJSON は手動読み込み（ファイル or QR）。位置情報は Geolocator のポーリングのみ。

## 2. ユースケース価値
- 端末完結の監視（ネット不要）で通信遮断時も動作。
- QR コード経由で GeoJSON を安全に配布（Brotli 圧縮＋Base64URL＋SHA-256 ハッシュ検証）。
- 「離脱確定までの猶予」(サンプル数 + 経過秒数) を設定でき、GPS ノイズによる誤検知を抑制。
- 離脱時はフルスクリーン通知＋アラーム音＋連続バイブで確実に気付かせる。
- Developer mode でエリア内でも距離・方位を確認でき、デバッグ／捜索補助に使える。

## 3. モジュール構成（主要ファイル）
- `lib/main.dart`: エントリポイント、`AppController.bootstrap()` を起動。
- `lib/app_controller.dart`: アプリ全体のオーケストレーター。設定ロード、GeoJSON 読み込み、位置監視開始/停止、状態通知、ログ保持、エラー提示を司る。
- `lib/state_machine/state_machine.dart` + `state.dart` + `hysteresis_counter.dart`: ジオフェンス状態遷移ロジック。
- `lib/geo/geo_model.dart` / `area_index.dart` / `point_in_polygon.dart`: GeoJSON パーサ・境界インデックス・点とポリゴン判定/距離/方位計算。
- `lib/platform/location_service.dart`: Geolocator を用いた位置ストリーム抽象＆実装。
- `lib/platform/notifier.dart`: ローカル通知、アラーム音 (`assets/sounds/alarm.mp3`)、連続バイブ制御。
- `lib/io/config.dart` / `file_manager.dart`: 設定 JSON の永続化、GeoJSON ファイルピック。
- `lib/io/logger.dart` / `log_entry.dart`: 状態変化・GPS 受信の JSON レコード化（メモリ内）。
- `lib/qr/geojson_qr_codec.dart`: GeoJSON の QR エンコード/デコード（Brotli CLI 依存）。
- `lib/ui/home_page.dart` / `settings_page.dart` / `qr_scanner_page.dart`: 画面（Material3）。

## 4. ランタイムフロー
1) 起動: `AppController.bootstrap()` で設定を `config.json`（無ければ `assets/config/default_config.json`）から読み込み、通知音量設定。GeoJSON 未ロードなので状態は `waitGeoJson` で開始。  
2) 権限要求: 通知権限・位置情報 (Always) を permission_handler で要求。拒否/永久拒否時は設定画面を開くだけで UI 上の代替ハンドリングなし。  
3) GeoJSON 取込:
   - ファイル: `FileManager.pickGeoJsonFile()` で `.geojson/.json/.bin` を選択しパース→`GeoModel`→`AreaIndex` 構築。ファイル名を `.geojson` 拡張子に正規化して保持。
   - QR: `gjb1:` / `gjb1p:` テキストを復元→Brotli 伸長→構造バリデーション→一時ファイル保存（次回起動で消去）。  
   ロード成功後の状態は `waitStart`、`navigationEnabled` は false にリセット、アラーム停止。
4) 監視開始: `startMonitoring()` で Geolocator ストリーム購読開始。`sampleIntervalS['fast']`（デフォルト 3 秒）間隔・距離フィルタ 0m・`LocationAccuracy.best`。
5) 評価ループ: 各 `LocationFix` を `StateMachine.evaluate()` に通し、UI/ログ/通知に反映。OUTER 確定時に通知＋アラーム。再入時に停止通知。
6) 停止/終了: `stopMonitoring()` で購読解除・Geolocator 停止。アプリ detach 時に QR 由来の一時 GeoJSON を削除。

## 5. 中核ドメイン仕様
### 5.1 GeoJSON 取り込み
- 対応タイプ: FeatureCollection の Polygon / MultiPolygon（各ポリゴンは最初のリングのみ使用、3点未満は無視）。properties の `name`/`version` は読み取りのみ未使用。
- ファイルピック時はクエリ/フラグメントを除去したファイル名を `.geojson` に正規化して記憶。
- ロード失敗時は `FormatException`/その他を Snackbar で表示し、状態は維持。
- 新規ロード時は監視を一時停止し、AreaIndex も再構築。

### 5.2 QR コーデック（ライブラリ）
- エンコード: GeoJSON を jsonEncode → Brotli (quality=11, 外部 `brotli` CLI 必須) → Base64URL（= 無パディング）→ `gjb1:<payload>[#hash]`。長すぎる場合は `gjb1p:<idx>/<total>:<chunk>` へ自動分割。オプションで PNG 生成（`qr` + `image` パッケージ）。
- ハッシュ: デフォルトで SHA-256 を付与し、デコード時に検証 (`verifyHash=true`)。不一致なら `HashMismatchException`。
- デコード: `gjb1`/`gjb1p` 以外は拒否。Brotli 伸長後に GeoJSON 構造チェックを行い、無効なら `GeoJsonValidationException`。
- 一時ファイル: QR 取込時のみ `temp_geojson_<timestamp>.geojson` を作成。次回起動(detached)または再読込時に削除。

### 5.3 権限
- 通知: denied/permanentlyDenied の場合は `openAppSettings()` を呼ぶのみ。
- 位置: `locationAlways` を要求。`whileInUse` のみ許可された場合は再要求し、それでもダメなら設定画面を開くだけでフェールファスト。

### 5.4 位置サンプリング（`lib/platform/location_service.dart`）
- Android: Foreground サービス通知タイトル「Argus 位置を監視中」、本文「画面を閉じても位置記録は続きます」。`enableWakeLock: true`、`setOngoing: true`。
- iOS/macOS: `showBackgroundLocationIndicator: true`、`pauseLocationUpdatesAutomatically: false`。
- Stream 値: `latitude/longitude/timestamp/accuracyMeters/batteryPercent?` を `LocationFix` として配信。

### 5.5 状態機械（`state_machine.dart`）
- 状態: `waitGeoJson` → `waitStart` → `inner / near / outerPending / outer / gpsBad`。
- 距離閾値: `innerBufferM`（デフォルト 30m）より内側で `near`、それ以上は `inner`。
- GPS 精度: `accuracyMeters == null` または `> gpsAccuracyBadMeters`（デフォルト 40m）のとき `gpsBad`。ただし直前が OUTER の場合は「外にいる前提」で最寄り境界距離だけ更新し OUTER 維持。精度が悪くても内側に戻ったと判定できれば `inner/near` に復帰しヒステリシスリセット。
- OUTER 確定条件: `_hysteresis.addSample(timestamp)` が `leaveConfirmSamples` 回（デフォルト 3）かつ `leaveConfirmSeconds` 秒（デフォルト 10 秒）経過。未達時は `outerPending`。
- ポリゴン探索: AreaIndex の軸平行バウンディングボックスで候補絞り込み、ray-cast で包含判定。最短距離/方位を常に計算し `StateSnapshot` に積む。
- ナビゲーション表示: OUTER になったタイミングで `navigationEnabled=true`。Developer mode ではエリア内でもナビ表示可。それ以外は OUTER 以降のみ距離/方位ヒントを UI に出す。

### 5.6 境界計算（`point_in_polygon.dart`）
- 包含判定: Ray casting（端点補正 ε=1e-12）。
- 最近傍点: 各辺の射影点を計算し、Haversine 距離最小の点を選択。
- 方位: Haversine を基に 0–360deg へ正規化。UI では 8 方位 (N/NE/…/NW) 併記。

### 5.7 通知・アラーム（`notifier.dart`）
- チャンネル: `argus_alerts`（Android importance max / alarm 音属性）。タイトル「Argus警告」、本文「安全エリアを離脱しています。」。
- OUTER: ローカル通知＋ループ再生のアラーム音＋連続バイブ（5 秒振動＋2 秒休止を繰り返し）。`Notifier.stopAlarm()` で両方停止。
- 復帰: OUTER 通知をキャンセルし、アラーム停止のみ。ログに “Returned to safe zone.” を出力。
- 音量: ユーザー設定 0.0–1.0 を `RingtoneAlarmPlayer` に反映（初期 1.0）。

### 5.8 UI
- Home (`home_page.dart`): 大型ステータス円で状態表示（INNER/NEAR/OUTER 等、色付き）。`waitStart` ではタップで監視開始。GeoJSON ファイル名と GPS 精度を常時表示。OUTER（または Developer mode）で距離/方位ナビ表示。最新 5 件のアプリ内ログをカードで閲覧。エラーは Snackbar。
- Settings (`settings_page.dart`): 設定フォーム（Inner buffer, GPS 精度閾値, Leave confirm サンプル/秒, Alarm 音量）。Developer mode トグル。ログ JSON エクスポート（メモリ上の `EventLogger` 内容をその場表示）。
- QR Scanner (`qr_scanner_page.dart`): `mobile_scanner` で `gjb1` スキーム QR を読み取り、`AppController.reloadGeoJsonFromQr` へ連携。処理中オーバーレイとエラーバナーを表示。
- テーマ: Material3、Seed color Blue。文言は日本語中心で一部英語残り。

## 6. データ/設定リファレンス
- AppConfig (`io/config.dart`):
  - `inner_buffer_m`(double, 30.0) / `leave_confirm_samples`(int, 3) / `leave_confirm_seconds`(int, 10) / `gps_accuracy_bad_m`(double, 40.0) / `sample_interval_s.fast`(int, 3) / `sample_distance_m`(保持のみ・未使用) / `screen_wake_on_leave`(保持のみ・未使用) / `alarm_volume`(double, 1.0)。
  - 保存先: ドキュメントディレクトリの `config.json`。読み込み失敗時はデフォルトを再生成。
- StateSnapshot (`state.dart`): `status`, `timestamp`, `distanceToBoundaryM`, `horizontalAccuracyM`, `geoJsonLoaded`, `notes`, `nearestBoundaryPoint(LatLng)`, `bearingToBoundaryDeg`。
- ログ:
  - UI ログ (`AppLogEntry`): 種別 debug/info/warning/error、200 件までメモリ保持（永続化なし）。
  - EventLogger: `location`（lat/lon/accuracy/battery）、`state`（status/distance/accuracy/bearing/nearest/notes）をメモリ配列に追加。`exportJsonl()` で JSON 文字列を返すのみ。

## 7. 依存・アセット
- 主要パッケージ: geolocator, flutter_local_notifications, permission_handler, mobile_scanner, file_selector, provider, vibration, flutter_ringtone_player, brotli, qr, image, crypto。
- CLI 依存: QR エンコード時のみ `brotli` コマンドが必要（パス探索: `_BrotliCli.resolve()` が `BROTLI_CLI` 環境変数や where/which を検索）。
- アセット: `assets/config/default_config.json`（初期設定）、`assets/geojson/map.geojson`（サンプル／テスト用、アプリ起動時には自動ロードされない）、`assets/sounds/alarm.mp3`（警告音）、`icon.png`。

## 8. 品質・テスト
- README 時点カバレッジ: 42.5%（state_machine/geo 周りは高カバー、UI・I/O は低カバー）。
- 自動テスト対象（抜粋）: 状態遷移とヒステリシス、GeoJSON パース/点とポリゴン計算、QR コーデック、Notifier のアラーム状態、AppController の GeoJSON 読み込み/アラーム停止など。
- 未テスト/低カバー: file_picker, UI 表示分岐、位置サービス実機連携、設定フォームバリデーション。

## 9. 強み（実装で裏付けられるポイント）
- ノイズ耐性: サンプル数＋経過秒数によるヒステリシスで誤検知を抑制しつつ、精度不良時も OUTER 維持・距離算出を試みる（`state_machine.dart`）。
- 詳細な距離/方位ガイダンス: 最近傍境界点と方位を常時計算し、OUTER で移動ヒントを出せる（`_buildNavHint`, `_cardinalFromBearing`）。
- オフライン配布: Brotli 圧縮＋SHA-256 ハッシュ付き QR（分割にも対応）でエリアデータを物理的に配布可能（`qr/geojson_qr_codec.dart`）。
- フルアラート: クリティカル通知＋ループアラーム音＋連続バイブで確実に気付ける。音量はユーザー設定反映。
- デベロッパーモード: エリア内でも距離/方位やログを確認でき、現地調査・検証に向く。

## 10. 弱み / リスク（現状コード由来）
- ポーリング前提: OS ネイティブ geofence を使わず Geolocator の高頻度ストリーム依存。電池負荷と端末設定（省電力）に左右される。
- 外部依存: QR エンコードは外部 `brotli` CLI が無いと失敗（デフォルトで同梱されない）。デコードは可能。
- GeoJSON サポートの簡素さ: 最初のリングしか読まないため穴 (holes) や複数リングを無視。MultiPolygon も各ポリゴンの一番外側のみ。高精度ジオフェンスには不十分な場合がある。
- 設定項目の遊休: `sample_distance_m` と `screen_wake_on_leave` は UI/ロジックで未使用。設定と実挙動が乖離する恐れ。
- ログ永続化なし: UI ログはメモリ 200 件のみ、EventLogger もメモリのみ。`FileManager.openLogFile()` は未使用で実ファイルに残らない。
- バックグラウンド挙動の限定: アプリ終了後の自動再開なし。起動後も GeoJSON を手動ロードしないと監視が始まらない（サンプル GeoJSON も自動読み込みしない）。
- UX/多言語: 文言が日英混在、アクセシビリティ配慮やローカライズは未実装。
- セキュリティ: ハッシュ検証は任意、署名なし。無効な GeoJSON は弾くが、改ざん防止はハッシュ頼み。

## 11. 運用メモ
- Android では Foreground Service 通知が常に出る想定。端末設定で「常に位置情報」許可が必須。
- iOS では Always 許可＋背景位置表示が有効化されている必要あり。拒否された場合の代替フローは無し。
- GeoJSON を差し替えたら自動で監視停止→再起動しないので、利用者に「再度 START を押す」導線を用意すると親切。
- アプリ終了時（detached）に QR 由来の一時 GeoJSON を自動削除するため、永続利用にはファイルピックを使う。

---

上記は 2025-11-17 時点のコードを直接確認した内容です。挙動変更時は `lib/app_controller.dart`・`lib/state_machine/state_machine.dart`・`lib/qr/geojson_qr_codec.dart` 周辺のロジック更新に合わせて改訂してください。
