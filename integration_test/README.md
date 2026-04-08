# Android UI Smoke Checks

This directory contains emulator-friendly UI smoke tests for ARGUS.

## What is covered

- Home screen permission setup card
- Settings screen rendering
- QR screen camera-permission error UI
- Navigation from Home to Settings

## Run on Android emulator

```powershell
./scripts/run_android_ui_checks.ps1
```

To save screenshots for the checked screens:

```powershell
./scripts/run_android_ui_checks.ps1 -CaptureScreenshots
```

Saved files:

- `build/integration_test/screenshots/home-permission-card.png`
- `build/integration_test/screenshots/settings-form.png`
- `build/integration_test/screenshots/qr-permission-error.png`

Or run the test directly against a connected emulator:

```powershell
flutter test integration_test/ui_smoke_test.dart -d emulator-5554
```
