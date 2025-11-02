# Argus 技術仕様 v4

本書は 2025 年 11 月時点の `Argus` Flutter アプリの実装内容を正確に反映した仕様書である。旧仕様 (v3) からの差分は **3 秒間隔での測位・リアルタイムログ表示・新しい状態管理実装** に関する記述を中心に更新されている。

---

## 0. 全体概要

- **目的**: GeoJSON で定義した警戒エリアへの入退場をモバイル端末で常時監視する。
- **プラットフォーム**: Flutter 3.x (Dart 3.9) / Android 9 以上。iOS は Info.plist 等を同梱するが検証対象外。
- **ターゲット利用者**: 緊急対応チーム、危険エリア監視担当。
- **守るべき指標**
  - 3 秒間隔で位置情報を取得し続ける。OUTER (退出) 判定時も測位は継続する。
  - 状態変化・GPS 取得をすべてログへ記録し、アプリ画面にも時系列で表示する。
  - GeoJSON 未ロード時・精度不足時・ヒステリシス判定中の状態を明示する。

---

## 1. 主機能 (Functional Requirements)

1. **GeoJSON のロード**
   - 初期起動時は `assets/geojson/sample_area.geojson` を読み込む。
   - 端末ファイルから任意の `.geojson` / `.json` をファイルピッカーで読み込める。
   - ロード失敗時はエラーを UI とログに表示する。
2. **位置情報監視**
   - Geolocator を使用して 3 秒間隔で測位 (Android は `AndroidSettings`、iOS/macOS は `AppleSettings`)。
   - 距離フィルタは 0m。外周に出ても監視を止めない。
   - 各測位結果 (`LocationFix`) をログ出力し、UI に即時表示する。
3. **状態判定**
   - `StateMachine` が GeoJSON 座標と設定値を用いて以下いずれかを算出: `WAIT_GEOJSON / GPS_BAD / INNER / NEAR / OUTER_PENDING / OUTER`。
   - OUTER 判定には `leave_confirm_samples` と `leave_confirm_seconds` を用いたヒステリシス (サンプル数 + 経過時間) を適用。
   - 結果を UI のバッジとログに反映。OUTER → 非 OUTER の遷移時は Notifier で復帰通知。
4. **ログ管理**
   - `EventLogger` がすべての GPS 取得と状態遷移をプレーンテキスト + CSV に追記。
   - ログはホーム画面で最新順にスクロール表示 (最大 200 件保持)。
   - CSV 形式: `timestamp,lat,lon,status,dist_to_boundary_m,horiz_accuracy_m,battery_pct`。
   - JSONL エクスポートに対応 (`SettingsPage` 経由)。
5. **UI**
   - `HomePage`: 状態バッジ、GeoJSON 読込 / Start / Stop ボタン、アクティブ状態説明、ログ一覧。
   - `SettingsPage`: 設定値の参照とログの JSONL 表示 (モーダル)。

---

## 2. 補助機能 (Non-Functional/Support)

- **設定ファイル (`AppConfig`)**
  - 既定値は `assets/config/default_config.json`。
  - ユーザー設定は `getApplicationDocumentsDirectory()/config.json` に保存 (JSON)。
- **GeoJSON パース**
  - `GeoModel` が FeatureCollection から Polygon/MultiPolygon を抽出し、閉じたリングに正規化。
  - `AreaIndex` はポリゴンのバウンディングボックスで簡易インデックスを持つ。
  - `PointInPolygon` がレイキャスト法 + ハバースイン距離で内外判定/境界距離を算出。
- **テスト**
  - `test/state_machine_test.dart`: INNER/NEAR/OUTER の代表ケースをカバー。
  - 追加テスト時は `flutter test` を使用。
- **ビルド**
  - Android 専用 (`flutter build apk`)。`android/build.gradle.kts` で Java/Kotlin を 11 に統一。
  - 未使用の `workmanager` を排除済み。ファイル選択は `file_selector` を利用。

---

## 3. クラス構成

| レイヤ | 主要クラス | 役割 |
| ------ | ---------- | ---- |
| UI | `HomePage`, `SettingsPage` | 状態バッジ、コントロール群、ログ表示 / エクスポート |
| アプリ制御 | `AppController` | GeoJSON ロード、測位開始/停止、ログ蓄積、状態更新、エラー処理 |
| 状態管理 | `StateMachine`, `StateSnapshot`, `LocationStateStatus`, `HysteresisCounter` | 測位結果から状態遷移判断 |
| Geo 処理 | `GeoModel`, `GeoPolygon`, `AreaIndex`, `PointInPolygon` | GeoJSON パースと点/境界判定 |
| プラットフォーム | `GeolocatorLocationService`, `FakeLocationService`, `Notifier` | 3 秒毎の測位ストリーム、通知 (現在は `debugPrint`) |
| IO | `FileManager`, `EventLogger`, `AppConfig` | ファイル選択・設定保存・CSV/JSONL ログ出力 |

---

## 4. 状態遷移 (実装)

```
WAIT_GEOJSON --(GeoJSON ロード成功)--> INIT
INIT / INNER / NEAR / OUTER_PENDING / OUTER / GPS_BAD

GPS_BAD: 精度 > gps_accuracy_bad_m。精度回復で他状態へ遷移。
INNER: ポリゴン内部 & dist >= inner_buffer_m。
NEAR: ポリゴン内部 & dist < inner_buffer_m。
OUTER_PENDING: ポリゴン外。ヒステリシス条件を満たすと OUTER。
OUTER: 規定サンプル数 & 経過時間を満たす退出確定状態。位置監視・ログは継続。
```

`StateMachine.evaluate(fix)` が常に `LocationFix` を受け取り `StateSnapshot` を返す。`AppController` は OUTER → 非 OUTER の遷移で復帰通知を行い、状態に応じたログを追加する。

---

## 5. ログ仕様

- **保存先**: `getApplicationDocumentsDirectory()/argus.log`。
- **CSV ヘッダー**: `timestamp,lat,lon,status,dist_to_boundary_m,horiz_accuracy_m,battery_pct`。
- **記録内容**
  - GPS 取得 (`status = GPS_FIX`)
  - 状態遷移 (`status = INNER/NEAR/...`)
  - アプリイベント (開始/停止/GeoJSON 読込/エラー) はメモリ内ログのみ。
- **アプリ画面表示**
  - `AppController.logs` に最新 200 行を保持 (新しい順)。
  - `HomePage` でモノスペースフォントによるリスト表示。

---

## 6. エラー処理と UI

- GeoJSON 読み込み失敗や解析失敗時は `_lastErrorMessage` に格納し、`HomePage` に赤背景のアラート表示。
- エラーはログにも記録される ( `[ERROR] ...` )。
- スタートボタンは GeoJSON がロードされていない場合は実行しても状態は変化しないが、ログにコマンド実行が残る。

---

## 7. 開発・運用メモ

- **ビルド/実行**: `flutter pub get` → `flutter build apk` または `flutter run`。
- **テスト**: `flutter test`。
- **GeoJSON テンプレート**: `assets/geojson/sample_area.geojson`。
- **測位間隔変更**: `AppConfig.sample_interval_s.fast` を更新 (デフォルト 3 秒)。
- **ログ最大保持数**: `AppController._logs` (200 行) を適宜調整。CSV 側は無制限。
- **IN/OUT 境界更新**: `inner_buffer_m`, `leave_confirm_samples`, `leave_confirm_seconds` を `config.json` で調整。

---

## 8. 今後の検討事項 (参考)

- Android Foreground Service との連携実装 (現状はアプリ前提)。
- Notifier を実デバイスの通知/音/振動に対応させる。
- 連続測位によるバッテリー影響の測定と `sample_interval_s` の動的調整。
- GeoJSON の複数エリア対応 (現状は最初のリングのみを監視)。
