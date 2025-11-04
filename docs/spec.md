# Argus 仕様書 v5（2025-11-03 時点）

本ドキュメントは Flutter 製アプリ Argus の現行コード（ブランチ `background`）をもとに構成・挙動・テスト観点を整理したものです。最新コードに追従するため、旧バージョンからの差分を含め全面的に更新しています。

---

## 0. 概要

- **目的**: GeoJSON で定義した警戒エリアからの逸脱を端末上で監視し、離脱時に即時アラートを発報する。
- **利用想定**: 保護対象者の無断外出検知、現場作業者の安全区域逸脱監視など。
- **対応プラットフォーム**: Flutter 3.x / Dart 3.2+。Android 9 以降、iOS 15 以降を想定。  
- **位置取得**: Geolocator を利用し、最短 3 秒間隔・距離フィルタ 0m で継続的に測位。Android では Foreground Service、iOS では常時位置情報を前提。

---

## 1. 機能要件

1. **GeoJSON 読み込み**
   - 初回起動時に `assets/geojson/sample_area.geojson` をバンドルロード。
   - ユーザはファイルピッカーで `.geojson` / `.json` を再ロード可能。
   - 読み込み失敗はエラーバナーとログ（レベル ERROR）で通知。

2. **位置情報ストリーム**
   - Geolocator の `getPositionStream` を利用。
   - Android: `AndroidSettings`（`intervalDuration`, `forceLocationManager` など）＋ ForegroundService 通知を構成。
   - iOS/macOS: `AppleSettings` でバックグラウンド更新を継続。
   - 受信した `LocationFix` は `AppController` で記録・評価。

3. **状態遷移ロジック**
   - `StateMachine` が GeoJSON と設定値（閾値）を参照し、`WAIT_GEOJSON / GPS_BAD / INNER / NEAR / OUTER_PENDING / OUTER` を算出。
   - OUTER 判定にはヒステリシス（サンプル数＋経過時間）を適用して誤検知を抑制。
   - 状態変化に応じてアラーム通知および UI 更新を行う。

4. **バックグラウンド動作**
   - Android: 位置サービスは Foreground Service として継続。`WAKE_LOCK` / `FOREGROUND_SERVICE_LOCATION` 権限を要求。
   - iOS: Info.plist で `location` 背景モードを有効化し、Always 許可を促す文言を日本語で表示。

5. **通知とアラーム**
   - Flutter Local Notifications をラップした `Notifier` がアラート通知を管理。
   - OUTER でアラーム音（`flutter_ringtone_player`）をループ再生。INNER/NEAR 復帰で停止。
   - 通知タイトル・本文・チャンネル名はすべて日本語。

6. **UI**
   - `HomePage`: 状態バッジ、状態詳細、GeoJSON ロードボタン、Start ボタン、アプリ内ログカード。
   - `SettingsPage`: 現在の設定値確認とログ JSON エクスポート表示。

---

## 2. 非機能要件

- **パフォーマンス**: 位置取得・状態評価・ログ記録はいずれも非同期処理で UI スレッドを阻害しない。
- **電力消費**: Android は WakeLock を活用しつつも位置リクエスト間隔は設定値で調整可能。iOS はバックグラウンド許可前提。
- **データ永続化**: 設定はアプリドキュメントディレクトリの `config.json` に保存。ログはメモリのみで保持し、最大 200 件のリングバッファ管理。
- **権限**: 初期化時に通知・位置情報（常時）許可を順序立てて要求。拒否時はアプリ設定画面への誘導。
- **ローカライズ**: 通知文言、位置許可文言、UI 文言は日本語がデフォルト。

---

## 3. アーキテクチャ概要

| 区分 | 主要クラス | 役割 |
| --- | --- | --- |
| 中核ロジック | `AppController`, `StateMachine`, `AreaIndex`, `GeoModel` | 位置評価と状態管理、設定・ジオメトリの保持。 |
| 位置サービス | `LocationService`, `GeolocatorLocationService` | 位置ストリームの開始・停止、権限確認。 |
| 通知 | `Notifier`, `AlarmPlayer`（`RingtoneAlarmPlayer`） | 通知チャンネル作成、アラーム音制御、バッジ状態。 |
| ログ | `EventLogger`, `AppLogEntry`, `AppLogLevel` | GPS・状態イベントのメモリ記録と UI 連携、JSON エクスポート。 |
| I/O | `FileManager`, `AppConfig` | 設定・GeoJSON ファイルの読み書き。 |
| UI | `HomePage`, `SettingsPage`, `ArgusApp` | 画面構成とユーザ操作ルーティング。 |

全モジュールは依存注入で連結され、`AppController.bootstrap()` が標準構成を生成する。

---

## 4. 位置ステートマシン詳細

### 状態一覧

| 状態 | 説明 |
| --- | --- |
| `waitGeoJson` | GeoJSON 未ロード。ユーザにロード操作を促す。 |
| `init` | 監視準備完了。位置ストリームは未開始または安定待ち。 |
| `inner` | エリア内かつバッファより十分内側。 |
| `near` | エリア内だがバッファ距離未満。 |
| `outerPending` | エリア外候補。ヒステリシス確定待ち。 |
| `outer` | エリア外確定。通知・アラーム発火。 |
| `gpsBad` | 位置精度不足。OUTER 維持しつつも補正が入る。 |

### 判定パラメータ

- `innerBufferM`: エリア境界との距離バッファ。
- `leaveConfirmSamples`: OUTER 確定に必要な連続サンプル数。
- `leaveConfirmSeconds`: OUTER 確定に必要な経過秒数。
- `gpsAccuracyBadMeters`: 精度閾値。超過で `gpsBad`。

状態遷移は既存テスト（`test/state_machine_test.dart`）により INNER/NEAR/OUTER の代表ケースが保証される。

---

## 5. ログ仕様

- `AppController` が `AppLogEntry` を用いてアプリ内ログを管理。保持数は最大 200 件で新しい順に整列。
- ログレベルは `debug / info / warning / error`。GPS 受信は debug、状態変化は info、外出警告は warning、例外系は error。
- 全ログは `HomePage` でカード表示され、タグ（例: APP / GPS / STATE / ALERT）、タイムスタンプ、本文、レベルに応じた色・アイコンを表示。
- `EventLogger` はメモリにイベントを蓄積し、`exportJsonl()` 呼び出し時に整形 JSON を返す。ファイル書き込みは行わない。
- `SettingsPage` の「Export logs」ボタンは JSON をダイアログ表示するのみ。ユーザが手動コピーする運用。

---

## 6. 通知・アラーム仕様

- **チャンネル**: `Argus警告`（ID: `argus_alerts`）。説明は「ジオフェンスの安全エリアから離れたときに通知します。」。
- **通知本文**: `Argus警告` / `安全エリアから離れています。`
- **Foreground Service 通知**: Android 背景計測用に「Argusが位置情報を監視中です」「画面を消しても位置情報の追跡は継続されます。」を表示。
- **アラーム音**: `flutter_ringtone_player` によるループ再生。`Notifier.stopAlarm()` で停止。
- **iOS Permission 文言**:
  - WhenInUse: 「アプリを使用中に安全エリアを監視するため、位置情報へのアクセスが必要です。」
  - Always: 「バックグラウンド実行中も安全エリアを監視するため、常時の位置情報アクセスが必要です。」
  - AlwaysAndWhenInUse: 「安全エリアからの離脱を検知するため、常に位置情報を取得します。」

---

## 7. 画面仕様

### HomePage

- AppBar: タイトル Argus、Settings への遷移アイコン。
- Body:
  1. 状態バッジ（状態別カラー）。
  2. 状態詳細テキスト（status、notes、タイムスタンプ、距離・精度）。
  3. GeoJSON ロード状況、エラーバナー（必要時）。
  4. 操作ボタン: 「Load GeoJSON」「Start」。Stop ボタンは廃止済み。
  5. ログリスト: カード形式、レベル色分け。
- FAB: `GeoJSON` ボタン（ロードと同じ動作）。

### SettingsPage

- 設定値（バッファ・確認条件・精度閾値など）をテキスト表示。
- 「Export logs」ボタンで JSON ダイアログ表示。

---

## 8. テストと検証

- `flutter test` で以下をカバー:
  - `state_machine_test.dart`: 状態判定とヒステリシス挙動。
  - `hysteresis_counter_test.dart`: カウンタのサンプル数／時間条件。
  - `geo_model_test.dart`: GeoJSON パーサの挙動。
  - `point_in_polygon_test.dart`: 点とポリゴンの関係判定。
  - `platform/notifier_test.dart`: OUTER→INNER→OUTER でアラーム切り替え。
  - `app_controller_test.dart`: GeoJSON 再読込で init 状態・アラーム停止を確認。
  - `widget_test.dart`: 基本ウィジェット構成のレンダリング確認。

- `flutter analyze` を CI ベースラインとし、警告ゼロを維持。

---

## 9. 今後の検討事項

- ログフィルタ／検索 UI の追加（警告だけ表示する等）。
- 設定画面からサンプリング間隔やバッファ値を編集できるフォーム化。
- 通知チャンネル別の細分化（警告・情報を分離）。
- バッテリー・位置権限のチュートリアル画面や再許可導線の強化。
- 本番向け Foreground Service の設定（通知タップでアプリ復帰など）。

---

## 参考リンク

- Geolocator: <https://pub.dev/packages/geolocator>
- flutter_local_notifications: <https://pub.dev/packages/flutter_local_notifications>
- permission_handler: <https://pub.dev/packages/permission_handler>

## 10. 退避ナビゲーション

- INNER/NEAR states keep navigation distance/bearing hidden; cues surface only after OUTER is confirmed.

- OUTER/OUTER_PENDING 状態では最寄り境界点（緯度経度）と距離・推奨方角を表示し、復帰までの目標地点を提示する。
- StateSnapshot に方位角（deg）と最寄り境界点座標を保持し、ログ/通知メッセージで案内に利用する。
- HomePage では距離・方角（方位記号付き）・ターゲット座標を表示して方向感覚を補助する。
