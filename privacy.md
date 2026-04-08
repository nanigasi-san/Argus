# ARGUS Privacy Policy

Last updated: 2026-04-04

ARGUS is a geofencing support app. This policy explains what data the app uses and how that data is handled.

## 1. Data used by the app

ARGUS uses the following data only to provide its core features on the device:

- Location data
  The app uses foreground and background location to monitor whether the device remains inside the loaded competition area.
- Camera access
  The app uses the camera to scan GeoJSON QR codes.
- Local files selected by the user
  The app can import GeoJSON files that the user chooses.
- Notification permission
  The app uses notifications to warn the user when they leave the configured area.

## 2. How the data is handled

- Location data is processed on the device to evaluate geofence status.
- Camera input is processed on the device to decode QR codes.
- Imported GeoJSON data is stored only on the device.
- Temporary files created while restoring GeoJSON from QR codes are kept only on the device and can be deleted by the app.

ARGUS does not send location data, camera frames, GeoJSON files, or personal information to an external server operated by the developer.

## 3. Third-party services

ARGUS is built with Flutter and may rely on platform components provided by Android, Google Play services, and related libraries such as ML Kit for barcode scanning. Their handling of data is governed by their own terms and privacy policies.

## 4. Third-party sharing

The developer does not sell, share, or provide personal data to third parties.

## 5. Data retention

Data used by ARGUS remains on the device unless the user removes the app or deletes the related files.

## 6. Contact

Questions about this policy can be sent through the repository issue tracker:

- [ARGUS Issues](https://github.com/nanigasi-san/Argus/issues)

## 7. Changes

This policy may be updated when the app or legal requirements change. The latest version will be published in this repository.
