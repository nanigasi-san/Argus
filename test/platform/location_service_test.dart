import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

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
}
