import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:argus/io/logger.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/state_machine/state.dart';

void main() {
  group('EventLogger', () {
    test('exportJsonl returns empty array when no records', () async {
      final logger = EventLogger();
      final result = await logger.exportJsonl();
      final decoded = jsonDecode(result) as List;
      expect(decoded, isEmpty);
    });

    test('exportJsonl exports state change records', () async {
      final logger = EventLogger();
      final snapshot = StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.now(),
        distanceToBoundaryM: 10.5,
        horizontalAccuracyM: 5.0,
      );
      await logger.logStateChange(snapshot);
      final result = await logger.exportJsonl();
      final decoded = jsonDecode(result) as List;
      expect(decoded.length, 1);
      expect(decoded[0]['type'], 'state');
      expect(decoded[0]['status'], 'inner');
    });

    test('exportJsonl exports location fix records', () async {
      final logger = EventLogger();
      final fix = LocationFix(
        timestamp: DateTime.now(),
        latitude: 35.0,
        longitude: 139.0,
        accuracyMeters: 10.0,
      );
      await logger.logLocationFix(fix);
      final result = await logger.exportJsonl();
      final decoded = jsonDecode(result) as List;
      expect(decoded.length, 1);
      expect(decoded[0]['type'], 'location');
      expect(decoded[0]['lat'], 35.0);
      expect(decoded[0]['lon'], 139.0);
    });

    test('exportJsonl exports multiple records in order', () async {
      final logger = EventLogger();
      final snapshot1 = StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.now(),
      );
      final snapshot2 = StateSnapshot(
        status: LocationStateStatus.outer,
        timestamp: DateTime.now(),
      );
      await logger.logStateChange(snapshot1);
      await logger.logStateChange(snapshot2);
      final result = await logger.exportJsonl();
      final decoded = jsonDecode(result) as List;
      expect(decoded.length, 2);
      expect(decoded[0]['status'], 'inner');
      expect(decoded[1]['status'], 'outer');
    });
  });
}
