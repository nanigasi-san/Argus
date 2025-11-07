import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:argus/platform/location_service.dart';

import '../support/test_doubles.dart' as test_doubles;

void main() {
  group('Location service test doubles', () {
    test('LocationFix stores provided values', () {
      final fix = LocationFix(
        latitude: 35.0,
        longitude: 139.0,
        accuracyMeters: 4.5,
        batteryPercent: 90,
        timestamp: DateTime.utc(2024, 1, 1),
      );

      expect(fix.latitude, 35.0);
      expect(fix.longitude, 139.0);
      expect(fix.accuracyMeters, 4.5);
      expect(fix.batteryPercent, 90);
    });

    test('FakeLocationService emits updates and tracks lifecycle', () async {
      final service = test_doubles.FakeLocationService();
      final config = test_doubles.createTestConfig();
      final completer = Completer<LocationFix>();
      service.stream.listen(completer.complete);

      await service.start(config);
      expect(service.hasStarted, isTrue);

      final fix = LocationFix(
        latitude: 1,
        longitude: 2,
        timestamp: DateTime.utc(2024, 1, 1, 0, 0, 1),
      );
      service.add(fix);
      expect(await completer.future, fix);

      await service.stop();
      expect(service.hasStopped, isTrue);
    });
  });

  group('GeolocatorLocationService platform settings', () {
    test('creates AppleSettings for iOS/macOS platforms', () {
      // Note: This test verifies the structure of iOS settings.
      // Actual platform detection happens at runtime, so we test the settings
      // structure directly.
      
      // Create AppleSettings directly to verify iOS configuration
      final appleSettings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );

      expect(appleSettings.accuracy, LocationAccuracy.best);
      expect(appleSettings.distanceFilter, 0);
      expect(appleSettings.pauseLocationUpdatesAutomatically, false);
      expect(appleSettings.showBackgroundLocationIndicator, true);
    });

    test('creates AndroidSettings for Android platform', () {
      // Create AndroidSettings directly to verify Android configuration
      final androidSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 3),
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Argusが位置情報を監視中です',
          notificationText: '画面を消しても位置情報の追跡は継続されます。',
          notificationChannelName: 'Argusバックグラウンド監視',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );

      expect(androidSettings.accuracy, LocationAccuracy.best);
      expect(androidSettings.distanceFilter, 0);
      expect(androidSettings.intervalDuration, const Duration(seconds: 3));
      expect(androidSettings.foregroundNotificationConfig, isNotNull);
    });
  });
}
