# Google Play Background Location Declaration

Last updated: 2026-04-13

## Privacy Policy URL

Use this public URL in Play Console and in the app:

- https://github.com/nanigasi-san/Argus/blob/main/privacy.md

## Core functionality description

ARGUS is a geofence monitoring app for orienteering and similar field activities. The app lets the user load a GeoJSON competition area and start monitoring. After monitoring starts, ARGUS uses background location so it can detect when the user leaves the configured competition area and immediately notify them, even when the app is closed or not in use.

## Why background location is required

Background location is required because the app's core feature is continuous geofence monitoring after the user explicitly starts monitoring. If background location is not allowed, ARGUS cannot detect leaving the competition area while the phone screen is off, while the app is in the background, or while another app is being used.

## User benefit

The user benefit is immediate safety and rules-compliance feedback during an event. ARGUS warns the user as soon as they leave the configured area so they can return promptly.

## Data handling statement

ARGUS uses location data only to evaluate whether the device remains inside the loaded GeoJSON area. Location data is processed only on the device and is not sent to the developer's server.

## In-app disclosure summary

Before any location runtime permission request, the app shows an in-app disclosure screen stating that:

- ARGUS uses location data for geofence monitoring.
- Location is used even when the app is closed or not in use after monitoring starts.
- Location is used only to detect leaving the configured competition area.
- Location data is processed only on-device and is not sent to the developer's server.

## Short declaration text for Play Console

ARGUS uses background location only after the user starts monitoring a loaded GeoJSON competition area. This is required for the app's core feature: detecting when the user leaves the configured area and notifying them immediately, even when the app is closed or not in use. Location data is processed only on the device and is not sent to the developer's server.

## Video checklist

Record a short video that shows this exact flow:

1. Open ARGUS.
2. Show that a GeoJSON area is already loaded.
3. Tap `監視開始前に設定する` or the start action that leads to setup.
4. Show the in-app disclosure screen.
5. Tap `同意して位置情報の設定へ進む`.
6. Show the Android location permission screens.
7. Grant `アプリの使用中のみ`, then move to `常に許可`.
8. Return to ARGUS and show monitoring can start.

Do not include unrelated permission prompts if possible.
