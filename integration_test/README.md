# Mobile UI Smoke Checks

This directory contains Android and iOS device/emulator smoke tests for ARGUS. Detailed behavior is covered by unit and widget tests; this suite confirms that important screens can render and navigate on a mobile runtime.

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

- CI does not currently provision an Android emulator for this suite.
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
