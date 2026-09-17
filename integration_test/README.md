# Mobile E2E Checks

This directory contains Android and iOS device/emulator tests for ARGUS. UI smoke checks rendering and navigation; Core E2E checks monitoring flows across the production app components.

各シナリオの操作・位置入力・状態遷移・警告動作は
[E2Eテストの流れ](../docs/e2e_test_flows.md) に整理しています。

## What Is Covered

- Home permission setup card
- Background location disclosure flow
- Settings screen
- QR screen camera-permission error UI
- Navigation from Home to Settings

## Run On Android

Check connected devices:

```sh
flutter devices
adb devices
```

Run the smoke test against a connected device or emulator:

```sh
flutter test integration_test/ui_smoke_test.dart -d <android-device-id>
```

Example:

```sh
flutter test integration_test/ui_smoke_test.dart -d emulator-5554
```

## PowerShell Helper

```powershell
./scripts/run_android_ui_checks.ps1
```

To save screenshots for checked screens:

```powershell
./scripts/run_android_ui_checks.ps1 -CaptureScreenshots
```

Saved files:

- `build/integration_test/screenshots/home-permission-card.png`
- `build/integration_test/screenshots/background-location-disclosure.png`
- `build/integration_test/screenshots/settings-form.png`
- `build/integration_test/screenshots/qr-permission-error.png`

## Notes

- `.github/workflows/android_e2e.yml` provisions an Android API 36 emulator and runs all E2E files on every PR and main push, and supports manual runs.
- If multiple devices are connected, always pass `-d <android-device-id>`.
- GPS and camera hardware behavior should be treated as manual/device verification; app-side permission and error flows are covered by tests.

## Run on iOS Simulator

macOS と Xcode が必要です。

```bash
flutter drive \
  --driver=test_driver/ui_smoke_driver.dart \
  --target=integration_test/ui_smoke_test.dart \
  -d <ios-simulator-id>
```

iOSでは、単一「続ける」ボタンの位置情報説明画面と、設定画面の「警告音をテスト」も検証します。上記コマンドで取得したスクリーンショットはAndroidと同じ出力先に保存されます。

全E2E（UI smoke・Core monitoringの8シナリオ・コンパス）を実行する場合:

```bash
bash scripts/run_ios_e2e.sh <ios-simulator-id>
```

iOSの全件実行は一度ビルドしたアプリを停止状態で起動し、今回のPIDの
VM Service URLを保存ログから取得してdriverへ接続します。URL取得は120秒、
ビルドからテスト完了までの全体は900秒に制限します。
起動情報・接続URL・保存ログは `build/e2e/ios/` に記録します。

`.github/workflows/ios_e2e.yml` はPR・main push・手動実行時に標準の
`macos-latest` runnerで利用可能なiPhone Simulatorを起動し、このスクリプトを
実行します。`integration_test/` と、存在する場合は `e2e/` の全
`*_test.dart` を再帰的に検出します。失敗しても残りのsuiteを続行し、
1件でも失敗すれば `iOS E2E` チェックを失敗にします。

仮想方位はDartサービスへ注入するため、Simulatorの磁気センサーは不要です。
OS固有の任意モード `SIMULATOR_GPS=true` はCIでは有効にしません。
実センサー・OS権限ダイアログ・実通知／警告音は引き続き別途実機確認します。

Artifact `ios-e2e-diagnostics` は成功・失敗とも14日間保存します。
スクリーンショットは `build/integration_test/screenshots/`、suiteログ・結果・
Flutter/Xcodeバージョン・Simulator情報・Runnerログ・最終画面は
`build/e2e/ios/` に保存し、実行結果はStep Summaryにも表示します。

## Compass navigation E2E

仮想位置・方位をサービスの入口から流し、監視開始、範囲内→範囲外、
境界までの距離、左右の案内、前方±30°、方位取得不可、範囲内復帰、
長押しによる監視終了を確認します。

```bash
flutter drive --driver=test_driver/compass_navigation_driver.dart \
  --target=integration_test/compass_navigation_test.dart -d <device-id>
```

iOSシミュレーターのネイティブGPS受信も検証する場合は次を実行します。
ドライバーが位置情報の許可を設定して仮想位置を
範囲外から範囲内へ移動し、終了時に仮想位置を解除します。

```bash
ARGUS_SIMULATOR_ID=<simulator-id> flutter drive \
  --driver=test_driver/compass_navigation_driver.dart \
  --target=integration_test/compass_navigation_test.dart \
  --dart-define=SIMULATOR_GPS=true -d <simulator-id>
```

シミュレーターには磁気センサーがないため、ネイティブGPSの検証では
「方角を確認中」が表示されることを確認します。実際の磁気センサーによる
方位追従は実機で確認してください。スクリーンショットは
`build/integration_test/screenshots/compass-*.png` に保存します。

通常のE2EはGPS・磁気センサーに依存せず実機でも再現できます。位置情報と
方位は仮想サービス、GeoJSONはテスト用の正方形、通知・音・振動・権限は
テスト用実装を使います。状態判定とホーム画面はアプリ本体の実装を通します。
OSの権限ダイアログや実際の通知・警告音の動作はこのE2Eの対象外です。

## Core Monitoring E2E

`core_monitoring_e2e_test.dart` は、各シナリオを1つの `AppController` と
`ArgusApp` / `HomePage` で最後まで通します。

| シナリオ | 確認する連携 |
| --- | --- |
| GeoJSON → START → 範囲外 → 復帰 | QR変換・復元 → GeoModel → AreaIndex → UIから監視開始 → INNER → OUTER_PENDING → OUTER → 警告開始 → INNER → 警告停止 |
| GPS精度悪化 → 復帰 | INNER → GPS_BAD → INNER、誤警告なし、画面とsnapshotの一致 |
| OUTER中の精度悪化 | OUTER維持・警告継続、低精度でも実際に範囲内へ戻った場合は解除 |
| STOP → 再START（判定待ち） | UIの長押し終了、購読解除、停止中の位置を無視、ヒステリシスをリセット |
| STOP → 再START（警告中） | 警告停止、再開後に旧警告が残らない、購読が1つだけで位置を処理 |
| 権限不足 → 開示画面 → 更新 → START | 開示だけでは開始不可、権限granted後のUI更新から監視可能 |
| 設定変更 | Settingsで30 m → 50 mへ保存、監視を自動再開、同一座標がINNER → NEAR、設定ファイルにも保存 |
| OUTER中のスヌーズ | UI操作で音・振動だけ停止、OUTER維持、復帰時にスヌーズと通知を解除 |

本物の `AppController` / `StateMachine` / `Notifier` のロジックを使います。
GeoJSONは座標の意味が明確な専用fixtureをproductionの `encodeGeoJson()` と
`reloadGeoJsonFromQr()` に通し、QR復元後の一時ファイル保存も実行します。
設定は本番 `FileManager` でシナリオごとの一時ディレクトリに読み書きします。
`debugSeed()` でモデルや状態を直接設定することはありません。

OS位置情報は任意のfixを投入できる `ScriptedLocationService`、OS権限は
変更可能なgateway、通知・音・振動は実行状態を記録する実装に置き換えます。
コンパスと開始前のOS音量確認も固定値にし、センサー・音量・native dialogに
依存しません。Loggerはメモリに記録し、購読の二重化も検証します。

ヒステリシスはデフォルトの3サンプル・10秒を維持し、
`LocationFix.monitoringElapsed` を0 / 1 / 5 / 11秒へ進めます。
GPS判定のための固定sleepやスヌーズ満了までの1分待機はありません。
STOPでは本物のUI操作に必要な5秒の長押しを再現します。
各テスト終了時は画面を外して監視・購読・スヌーズタイマー・一時ファイルを
解放し、シナリオ間で設定や警告状態が残らないようにします。

### ローカル実行

```sh
flutter test integration_test/ui_smoke_test.dart -d emulator-5554
flutter test integration_test/core_monitoring_e2e_test.dart -d emulator-5554
```

スクリーンショットをホストへ保存する場合はextended driverを使います。
既存UI smokeのdriverはCore E2Eでも再利用できます。

```sh
flutter drive --driver=test_driver/ui_smoke_driver.dart \
  --target=integration_test/core_monitoring_e2e_test.dart -d emulator-5554
```

Linux / macOS / Git BashでCIと同じ実行・ログ収集を行う場合:

```sh
bash scripts/run_android_e2e.sh emulator-5554
```

両スクリプトは `integration_test/` と、存在する場合は `e2e/` 配下の
`*_test.dart` を再帰的に検出し、すべて実行します。
現在の対象はUI smoke、Core monitoring、コンパスの3ファイルです。
PowerShellでも同じ全件を実行します。

```powershell
./scripts/run_android_ui_checks.ps1 -CaptureScreenshots
```

### CIと診断情報

CIはUbuntu / Java 17 / Flutter stable / API 36 google_apis x86_64を使用し、
KVMを有効化したエミュレーターで全suiteを実行します。
スクリーンショットを保存するため、`flutter test` と同じ
`integration_test` のsuiteを `flutter drive` + extended driverで起動します。
一部のsuiteが失敗しても残りを実行し、1件でも失敗すればjobも失敗します。
再試行で失敗を隠す構成にはしていません。

Artifact `android-e2e-diagnostics` は成功・失敗とも14日間保存されます。

- `build/integration_test/screenshots/`: UI smoke、Coreの完了画面・OUTER画面・失敗時画面
- `build/e2e/`: suiteごとの実行ログ、結果、Flutter version、API level、logcat、最終画面

Step SummaryにもAPI level、Flutter version、実行suite、成否を表示します。
実行中のlogcatはエミュレーター終了前に収集します。
実行ファイル一覧は `build/e2e/suites.txt` に保存します。
PRの必須チェックにする場合のチェック名は `Android E2E` です。
PR提出前にローカルで全件を成功させるルールを `AGENTS.md` に記載しています。
`Flutter Tests`、`iOS Build`、`Android Release` は独立して動作します。

### Platform E2Eの残る範囲

この変更では決定的なPhase 1 / 2を実装しています。実
`GeolocatorLocationService` を通すPlatform E2Eはまだ実装していません。
OS権限・実GPS・background/resumeは、今後別の手動workflow/jobへ分離し、
安定性を確認するまでPRの必須チェックには含めません。
そのjobで使う基盤は同じAPI 36 emulator、extended driver、ログ収集方法です。

```sh
# インストール後に設定する。camera権限は位置情報シナリオに不要。
adb -s emulator-5554 shell pm grant com.argus.orienteering android.permission.ACCESS_COARSE_LOCATION
adb -s emulator-5554 shell pm grant com.argus.orienteering android.permission.ACCESS_FINE_LOCATION
adb -s emulator-5554 shell pm grant com.argus.orienteering android.permission.ACCESS_BACKGROUND_LOCATION
adb -s emulator-5554 shell pm grant com.argus.orienteering android.permission.POST_NOTIFICATIONS
adb -s emulator-5554 shell cmd location set-location-enabled true
# longitude → latitude。監視開始後に新しい位置を送る必要がある。
adb -s emulator-5554 emu geo fix 139.005 35.005
adb -s emulator-5554 emu geo fix 139.020 35.005
```

実providerでは経過時間を外から指定できないため、OUTER確定は実時間で
10秒・3サンプル以上が必要です。実機でのバックグラウンド位置受信、
権限設定、通知、警告音・振動、磁気センサー、カメラは別途確認します。
