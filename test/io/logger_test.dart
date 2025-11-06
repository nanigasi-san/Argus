import 'package:flutter_test/flutter_test.dart';

import 'package:argus/geo/geo_model.dart';
import 'package:argus/io/logger.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/state_machine/state.dart';

void main() {
  group('EventLogger', () {
    test('logStateChange formats message and emits record', () async {
      final logger = EventLogger();
      final snapshot = StateSnapshot(
        status: LocationStateStatus.near,
        timestamp: DateTime.utc(2024, 1, 1, 0, 0),
        distanceToBoundaryM: 5.25,
        horizontalAccuracyM: 3.5,
        bearingToBoundaryDeg: 123.4,
        nearestBoundaryPoint: const LatLng(35.0, 139.0),
        hasGeoJson: true,
        notes: 'testing',
      );

      final futureRecord = logger.events.first;
      final message = await logger.logStateChange(snapshot);
      final record = await futureRecord;

      expect(message, contains('[STATE] near'));
      expect(message, contains('dist=5.25m'));
      expect(message, contains('bearing=123deg'));
      expect(record['type'], 'state');
      expect(record['status'], 'near');
      expect(record['hasGeoJson'], isTrue);
      expect(record['nearestLat'], 35.0);
      expect(record['nearestLon'], 139.0);
      expect(record['notes'], 'testing');
    });

    test('logLocationFix emits GPS record with formatted message', () async {
      final logger = EventLogger();
      final fix = LocationFix(
        latitude: 35.123456,
        longitude: 139.654321,
        accuracyMeters: 4.2,
        batteryPercent: 88,
        timestamp: DateTime.utc(2024, 1, 1, 0, 0, 1),
      );

      final futureRecord = logger.events.first;
      final message = await logger.logLocationFix(fix);
      final record = await futureRecord;

      expect(message, contains('[GPS] lat=35.123456'));
      expect(message, contains('lon=139.654321'));
      expect(message, contains('acc=4.2m'));
      expect(record['type'], 'location');
      expect(record['lat'], 35.123456);
      expect(record['lon'], 139.654321);
      expect(record['accuracyM'], 4.2);
      expect(record['batteryPct'], 88);
    });

    test('exportJsonl outputs JSONL-formatted string', () async {
      final logger = EventLogger();
      await logger.logLocationFix(
        LocationFix(
          latitude: 1,
          longitude: 2,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );

      final export = await logger.exportJsonl();
      expect(export.trim(), isNotEmpty);
      expect(export, contains('"type": "location"'));
    });
  });
}
