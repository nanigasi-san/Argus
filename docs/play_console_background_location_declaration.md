# Google Play Background Location Declaration

Last updated: 2026-08-20

## Privacy Policy URL

Use this public URL in Play Console and in the app:

- https://argus-lp.vercel.app/privacy.html

## Core functionality description

ARGUS is a geofence monitoring app for orienteering and similar field activities. The app lets the user load a GeoJSON competition area and start monitoring. After monitoring starts, ARGUS uses background location so it can detect when the user leaves the configured competition area and immediately notify them while the screen is locked or another app is in use. Force-quitting ARGUS stops monitoring.

## Why background location is required

Background location is required because the app's core feature is continuous geofence monitoring after the user explicitly starts monitoring. If background location is not allowed, ARGUS cannot detect leaving the competition area while the phone screen is off, while the app is in the background, or while another app is being used.

## User benefit

The user benefit is immediate safety and rules-compliance feedback during an event. ARGUS warns the user as soon as they leave the configured area so they can return promptly.

## Data handling statement

ARGUS uses location data only to evaluate whether the device remains inside the loaded GeoJSON area. Location data is processed only on the device and is not sent to the developer's server.

## In-app disclosure summary

Before any location runtime permission request, the app shows an in-app disclosure screen stating that:

- ARGUS uses location data for geofence monitoring.
- Location is used while the screen is locked or another app is in use after monitoring starts.
- Force-quitting ARGUS stops monitoring; it does not restart automatically.
- Location is used only to detect leaving the configured competition area.
- Location data is processed only on-device and is not sent to the developer's server.

After the disclosure, the app requests foreground location first and then background/always location. Notification permission is part of setup so the user does not miss an alert, but monitoring is blocked only when location services are disabled or Always location permission is unavailable.

## Short declaration text for Play Console

ARGUS uses background location only after the user starts monitoring a loaded GeoJSON competition area. This is required for the app's core feature: detecting when the user leaves the configured area and notifying them immediately while the screen is locked or another app is in use. Force-quitting ARGUS stops monitoring. Location data is processed only on the device and is not sent to the developer's server.

## Foreground service declaration text

ARGUS uses the location foreground service type only while the user has started geofence monitoring. The foreground service keeps location monitoring active so ARGUS can notify the user immediately when they leave the loaded GeoJSON area. Monitoring is user initiated and can be stopped from the app.

## Store listing short description note

Mention background location in the Play Store description so the declared core functionality is visible outside the app:

```text
ARGUS monitors a loaded GeoJSON area and can warn you with notifications and sound when you leave the area, including while monitoring continues in the background.
```

## Video checklist

Record a short video that shows this exact flow:

1. Open ARGUS.
2. Show that a GeoJSON area is already loaded.
3. Tap `監視開始前に設定する` or the start action that leads to setup.
4. Show the in-app disclosure screen.
5. Tap `同意して位置情報の設定へ進む`.
6. Show the Android location permission screens.
7. Grant `アプリの使用中のみ`, then continue to the background/always location step.
8. Grant `常に許可`.
9. Return to ARGUS and show monitoring can start.

Do not include unrelated permission prompts if possible. If Android shows notification permission, explain that it is used so alert notifications are not missed and is separate from the background location declaration.

## Release evidence checklist

| Item | Evidence |
| --- | --- |
| AAB targets Android 15 / API 35 or later | AAB details or Play Console validation |
| Privacy Policy URL is set on the store listing | URL and screenshot |
| Background location declaration is submitted | Declaration submission screenshot |
| Foreground service declaration is submitted, if requested | Declaration submission screenshot |
| Video is uploaded as YouTube or Drive URL | Video URL |
| In-app disclosure appears before runtime location permission | Video timestamp |
| Closed testing release is available to testers | Track name / versionCode |
