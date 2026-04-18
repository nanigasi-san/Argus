# iOS release with Codemagic

## Current project assumptions

- Bundle identifier: `com.argus`
- Codemagic App Store Connect integration name: `argus-app-store`
- iOS deployment target: `15.0`
- Background location is enabled via `UIBackgroundModes = location`
- iOS notifications default to `time-sensitive`
- Critical alerts are intentionally disabled until Apple approves the entitlement

## Codemagic setup

1. In Codemagic Team settings, add an App Store Connect API key integration named `argus-app-store`.
2. In Codemagic code signing, configure iOS signing for bundle ID `com.argus`.
3. Set `APP_STORE_APPLE_ID` for the workflow. This is the Apple ID shown in App Store Connect for the app record.
4. Create the app record in App Store Connect before enabling the release workflow.
5. Upload the first build manually if App Store Connect still requires initial metadata entry.

## Repository configuration

- `codemagic.yaml` contains two workflows:
  - `ios-testflight`: signed IPA build + TestFlight upload
  - `ios-app-store-release`: signed IPA build + TestFlight upload + App Store submission
- `ios/Podfile` enables only the permissions this app actually uses on iOS:
  - camera
  - location
  - notifications
- `ios/Runner/Info.plist` contains the required location and camera usage descriptions and uses Flutter build version variables.

## Notification behavior on iOS

- The app initializes Darwin notifications without prompting immediately.
- Runtime permission requests are still handled by `permission_handler` in Dart.
- Outer-zone alerts use `time-sensitive` interruption level by default.
- To move to critical alerts later, Apple must approve the entitlement first. After approval, enable the entitlement on the Apple side and switch `Notifier(enableCriticalAlerts: true)` in the app bootstrap path.

## Verification checklist

- `flutter analyze`
- `flutter test`
- Codemagic `ios-testflight` workflow succeeds
- App asks for camera, notifications, and always-on location as expected
- Background monitoring still works after screen lock
- TestFlight build installs and can read QR codes
