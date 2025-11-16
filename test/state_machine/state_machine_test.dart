import 'package:flutter_test/flutter_test.dart';

import 'package:argus/geo/area_index.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/io/config.dart';

void main() {
  late AppConfig config;
  late StateMachine machine;
  late GeoModel geoModel;

  setUp(() {
    config = AppConfig(
      innerBufferM: 30,
      leaveConfirmSamples: 3,
      leaveConfirmSeconds: 10,
      gpsAccuracyBadMeters: 40,
      sampleIntervalS: const {'normal': 8},
      sampleDistanceM: const {'normal': 15},
      screenWakeOnLeave: true,
      alarmVolume: 1.0,
    );

    final polygon = GeoPolygon(
      points: const [
        LatLng(35.0, 139.0),
        LatLng(35.0, 139.01),
        LatLng(35.01, 139.01),
        LatLng(35.01, 139.0),
      ],
      name: 'Test Area',
      version: 1,
    );

    geoModel = GeoModel([polygon]);
    machine = StateMachine(config: config)
      ..updateGeometry(
        geoModel,
        AreaIndex.build(geoModel.polygons),
      );
  });

  test('returns INNER when fix is inside with healthy accuracy', () {
    final fix = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: 5,
      timestamp: DateTime.now(),
    );

    final snapshot = machine.evaluate(fix);
    expect(snapshot.status, LocationStateStatus.inner);
  });

  test('returns NEAR when inside but close to boundary', () {
    final fix = LocationFix(
      latitude: 35.0,
      longitude: 139.0095,
      accuracyMeters: 5,
      timestamp: DateTime.now(),
    );

    final snapshot = machine.evaluate(fix);
    expect(snapshot.status, LocationStateStatus.near);
  });

  test('transitions to OUTER after hysteresis when outside', () {
    final outsideFix = LocationFix(
      latitude: 35.02,
      longitude: 139.02,
      accuracyMeters: 5,
      timestamp: DateTime.now(),
    );

    var snapshot = machine.evaluate(outsideFix);
    expect(snapshot.status, LocationStateStatus.outerPending);

    for (var i = 0; i < config.leaveConfirmSamples; i++) {
      snapshot = machine.evaluate(
        LocationFix(
          latitude: outsideFix.latitude,
          longitude: outsideFix.longitude,
          accuracyMeters: 5,
          timestamp: outsideFix.timestamp.add(Duration(seconds: 10 + i)),
        ),
      );
    }

    expect(snapshot.status, LocationStateStatus.outer);
  });

  test('returns WAIT_GEOJSON when GeoJSON is not loaded', () {
    final machineWithoutGeometry = StateMachine(config: config);
    final fix = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: 5,
      timestamp: DateTime.now(),
    );

    final snapshot = machineWithoutGeometry.evaluate(fix);
    expect(snapshot.status, LocationStateStatus.waitGeoJson);
    expect(snapshot.geoJsonLoaded, false);
  });

  test('returns GPS_BAD when accuracy is too low', () {
    final fix = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: 50, // > gpsAccuracyBadMeters (40)
      timestamp: DateTime.now(),
    );

    final snapshot = machine.evaluate(fix);
    expect(snapshot.status, LocationStateStatus.gpsBad);
    expect(snapshot.horizontalAccuracyM, 50);
  });

  test('returns GPS_BAD when accuracy is null', () {
    final fix = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: null,
      timestamp: DateTime.now(),
    );

    final snapshot = machine.evaluate(fix);
    expect(snapshot.status, LocationStateStatus.gpsBad);
  });

  test('resets hysteresis and transitions to INNER when recovering from OUTER',
      () {
    // First, transition to OUTER
    final outsideFix = LocationFix(
      latitude: 35.02,
      longitude: 139.02,
      accuracyMeters: 5,
      timestamp: DateTime.now(),
    );

    var snapshot = machine.evaluate(outsideFix);
    for (var i = 0; i < config.leaveConfirmSamples; i++) {
      snapshot = machine.evaluate(
        LocationFix(
          latitude: outsideFix.latitude,
          longitude: outsideFix.longitude,
          accuracyMeters: 5,
          timestamp: outsideFix.timestamp.add(Duration(seconds: 10 + i)),
        ),
      );
    }
    expect(snapshot.status, LocationStateStatus.outer);

    // Then move back inside
    final insideFix = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: 5,
      timestamp: outsideFix.timestamp.add(const Duration(seconds: 20)),
    );

    snapshot = machine.evaluate(insideFix);
    expect(snapshot.status, LocationStateStatus.inner);
  });

  test('recovers from GPS_BAD to INNER when accuracy improves', () {
    // Start with bad GPS
    final badFix = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: 50,
      timestamp: DateTime.now(),
    );
    var snapshot = machine.evaluate(badFix);
    expect(snapshot.status, LocationStateStatus.gpsBad);

    // Recover with good GPS
    final goodFix = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: 5,
      timestamp: badFix.timestamp.add(const Duration(seconds: 1)),
    );
    snapshot = machine.evaluate(goodFix);
    expect(snapshot.status, LocationStateStatus.inner);
  });

  test('resets hysteresis when moving from OUTER_PENDING to INNER', () {
    // Move outside
    final outsideFix = LocationFix(
      latitude: 35.02,
      longitude: 139.02,
      accuracyMeters: 5,
      timestamp: DateTime.now(),
    );
    var snapshot = machine.evaluate(outsideFix);
    expect(snapshot.status, LocationStateStatus.outerPending);

    // Add one sample but not enough for OUTER
    snapshot = machine.evaluate(
      LocationFix(
        latitude: outsideFix.latitude,
        longitude: outsideFix.longitude,
        accuracyMeters: 5,
        timestamp: outsideFix.timestamp.add(const Duration(seconds: 1)),
      ),
    );
    expect(snapshot.status, LocationStateStatus.outerPending);

    // Move back inside - should reset hysteresis
    final insideFix = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: 5,
      timestamp: outsideFix.timestamp.add(const Duration(seconds: 2)),
    );
    snapshot = machine.evaluate(insideFix);
    expect(snapshot.status, LocationStateStatus.inner);

    // Move outside again - should start hysteresis from scratch
    final outsideAgain = LocationFix(
      latitude: 35.02,
      longitude: 139.02,
      accuracyMeters: 5,
      timestamp: insideFix.timestamp.add(const Duration(seconds: 1)),
    );
    snapshot = machine.evaluate(outsideAgain);
    expect(snapshot.status, LocationStateStatus.outerPending);
  });

  test('transitions from OUTER to INNER even with bad GPS when inside', () {
    // First, transition to OUTER
    final outsideFix = LocationFix(
      latitude: 35.02,
      longitude: 139.02,
      accuracyMeters: 5,
      timestamp: DateTime.now(),
    );

    var snapshot = machine.evaluate(outsideFix);
    for (var i = 0; i < config.leaveConfirmSamples; i++) {
      snapshot = machine.evaluate(
        LocationFix(
          latitude: outsideFix.latitude,
          longitude: outsideFix.longitude,
          accuracyMeters: 5,
          timestamp: outsideFix.timestamp.add(Duration(seconds: 10 + i)),
        ),
      );
    }
    expect(snapshot.status, LocationStateStatus.outer);

    // Now move back inside with bad GPS accuracy
    final insideWithBadGPS = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: 50, // > gpsAccuracyBadMeters (40)
      timestamp: outsideFix.timestamp.add(const Duration(seconds: 30)),
    );

    snapshot = machine.evaluate(insideWithBadGPS);
    // Should transition to INNER even with bad GPS if actually inside
    expect(snapshot.status, LocationStateStatus.inner);
    expect(snapshot.horizontalAccuracyM, 50);
  });

  test('maintains OUTER with bad GPS when still outside', () {
    // First, transition to OUTER
    final outsideFix = LocationFix(
      latitude: 35.02,
      longitude: 139.02,
      accuracyMeters: 5,
      timestamp: DateTime.now(),
    );

    var snapshot = machine.evaluate(outsideFix);
    for (var i = 0; i < config.leaveConfirmSamples; i++) {
      snapshot = machine.evaluate(
        LocationFix(
          latitude: outsideFix.latitude,
          longitude: outsideFix.longitude,
          accuracyMeters: 5,
          timestamp: outsideFix.timestamp.add(Duration(seconds: 10 + i)),
        ),
      );
    }
    expect(snapshot.status, LocationStateStatus.outer);

    // Stay outside with bad GPS accuracy
    final outsideWithBadGPS = LocationFix(
      latitude: 35.02,
      longitude: 139.02,
      accuracyMeters: 50, // > gpsAccuracyBadMeters (40)
      timestamp: outsideFix.timestamp.add(const Duration(seconds: 30)),
    );

    snapshot = machine.evaluate(outsideWithBadGPS);
    // Should maintain OUTER when still outside even with bad GPS
    expect(snapshot.status, LocationStateStatus.outer);
    expect(snapshot.horizontalAccuracyM, 50);
  });
}
