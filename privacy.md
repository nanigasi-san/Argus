# ARGUS Privacy Policy

Last updated: 2026-09-29

ARGUS is a geofencing support app. This policy explains what data the app uses and how that data is handled.

## 1. Data used by the app

ARGUS uses the following data to provide its core features on the phone and, when the user chooses GARMIN transfer, on the selected watch:

- Location data
  After the user starts monitoring, the phone can use foreground and background location while its screen is locked or another app is in use. Monitoring does not automatically restart after ARGUS is terminated.
- Camera access
  The app uses the camera to scan GeoJSON QR codes.
- Local files selected by the user
  The app can import GeoJSON files that the user chooses.
- Notification permission
  The app uses notifications to warn the user when they leave the configured area.

## 2. How the data is handled

- Location data is processed on the device to evaluate geofence status.
  Background location is used only to keep geofence monitoring active after the user starts monitoring.
- Camera input is processed on the device to decode QR codes.
- Imported GeoJSON data is stored on the phone. When the user selects GARMIN transfer, ARGUS converts the selected boundary and sends its geometry and file name to the selected paired watch through Connect IQ. The watch stores that boundary to monitor a Run. The transfer does not send the phone's location history or camera input.
- Temporary files created while restoring GeoJSON from QR codes are kept only on the device and can be deleted by the app.

ARGUS does not send location data, camera frames, GeoJSON files, or personal information to an external server operated by the developer.

## 3. Third-party services

ARGUS is built with Flutter and may rely on platform components provided by Android, Google Play services, and related libraries such as ML Kit for barcode scanning. User-initiated GARMIN transfer uses Garmin Connect or the Connect IQ Companion SDK and Bluetooth. Release builds may also check the app store for updates. These third-party components and services are governed by their own terms and privacy policies.

## 4. Third-party sharing

The developer does not sell personal data or send location data, camera frames, or GeoJSON files to a server operated by the developer. Boundary transfer to a paired GARMIN watch occurs only when the user requests it.

## 5. Data retention

Imported files and settings remain on the phone until the user removes the app or deletes the related files. Temporary GeoJSON files created from QR codes may be removed by the app. A boundary sent to a GARMIN watch is enabled for one Run and has a 12-hour deadline for starting that Run. Ending the associated Run deletes its boundary. The phone's stop command also requests deletion, and ARGUS reports completion only after the watch confirms deletion. Pausing and resuming the same Run retains the boundary. A Run started before the deadline can continue until that Run ends. If no Run is started, passing the deadline alone does not delete the stored boundary; it remains until a later transfer replaces it, the phone requests deletion, or an associated Run ends.

## 6. Contact

Questions about this policy can be sent to:

- [yamada.orien@gmail.com](mailto:yamada.orien@gmail.com)

## 7. Changes

This policy may be updated when the app or legal requirements change. The latest version will be published at:

- [ARGUS Privacy Policy](https://argus-lp.vercel.app/privacy.html)
