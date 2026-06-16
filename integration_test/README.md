# Android UI Smoke Checks

This directory contains Android device/emulator smoke tests for ARGUS. Detailed behavior is covered by unit and widget tests; this suite only confirms that important screens can render and navigate on a real Android runtime.

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
- `build/integration_test/screenshots/background-disclosure.png`
- `build/integration_test/screenshots/settings-form.png`
- `build/integration_test/screenshots/qr-permission-error.png`

## Notes

- CI does not currently provision an Android emulator for this suite.
- If multiple devices are connected, always pass `-d <android-device-id>`.
- GPS and camera hardware behavior should be treated as manual/device verification; app-side permission and error flows are covered by tests.
