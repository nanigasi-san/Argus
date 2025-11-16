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

  group('State transitions', () {
    test('waitGeoJson → waitStart (updateGeometry)', () {
      final machineWithoutGeometry = StateMachine(config: config);
      expect(machineWithoutGeometry.current, LocationStateStatus.waitGeoJson);

      machineWithoutGeometry.updateGeometry(
        geoModel,
        AreaIndex.build(geoModel.polygons),
      );
      expect(machineWithoutGeometry.current, LocationStateStatus.waitStart);
    });

    test('waitGeoJson → waitGeoJson (evaluate without geometry)', () {
      final machineWithoutGeometry = StateMachine(config: config);
      final fix = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );

      final snapshot = machineWithoutGeometry.evaluate(fix);
      expect(snapshot.status, LocationStateStatus.waitGeoJson);
      expect(machineWithoutGeometry.current, LocationStateStatus.waitGeoJson);
    });

    test('waitStart → inner (監視開始後、エリア内、精度良好、distance >= innerBufferM)', () {
      final fix = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );

      final snapshot = machine.evaluate(fix);
      expect(snapshot.status, LocationStateStatus.inner);
    });

    test('waitStart → near (監視開始後、エリア内、精度良好、distance < innerBufferM)', () {
      final fix = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );

      final snapshot = machine.evaluate(fix);
      expect(snapshot.status, LocationStateStatus.near);
    });

    test('waitStart → outerPending (監視開始後、エリア外、精度良好、hysteresis未到達)', () {
      final fix = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );

      final snapshot = machine.evaluate(fix);
      expect(snapshot.status, LocationStateStatus.outerPending);
    });

    test('waitStart → gpsBad (監視開始後、精度不良)', () {
      final fix = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 50,
        timestamp: DateTime.now(),
      );

      final snapshot = machine.evaluate(fix);
      expect(snapshot.status, LocationStateStatus.gpsBad);
    });

    test('inner → inner (継続)', () {
      final fix1 = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(fix1);
      expect(machine.current, LocationStateStatus.inner);

      final fix2 = LocationFix(
        latitude: 35.0055,
        longitude: 139.0055,
        accuracyMeters: 5,
        timestamp: fix1.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(fix2);
      expect(snapshot.status, LocationStateStatus.inner);
    });

    test('inner → near', () {
      final fix1 = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(fix1);

      final fix2 = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 5,
        timestamp: fix1.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(fix2);
      expect(snapshot.status, LocationStateStatus.near);
    });

    test('inner → outerPending', () {
      final fix1 = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(fix1);

      final fix2 = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: fix1.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(fix2);
      expect(snapshot.status, LocationStateStatus.outerPending);
    });

    test('inner → gpsBad', () {
      final fix1 = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(fix1);

      final fix2 = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 50,
        timestamp: fix1.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(fix2);
      expect(snapshot.status, LocationStateStatus.gpsBad);
    });

    test('near → inner', () {
      final fix1 = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(fix1);

      final fix2 = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: fix1.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(fix2);
      expect(snapshot.status, LocationStateStatus.inner);
    });

    test('near → near (継続)', () {
      final fix1 = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(fix1);

      final fix2 = LocationFix(
        latitude: 35.0,
        longitude: 139.0096,
        accuracyMeters: 5,
        timestamp: fix1.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(fix2);
      expect(snapshot.status, LocationStateStatus.near);
    });

    test('near → outerPending', () {
      final fix1 = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(fix1);

      final fix2 = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: fix1.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(fix2);
      expect(snapshot.status, LocationStateStatus.outerPending);
    });

    test('near → gpsBad', () {
      final fix1 = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(fix1);

      final fix2 = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 50,
        timestamp: fix1.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(fix2);
      expect(snapshot.status, LocationStateStatus.gpsBad);
    });

    test('outerPending → inner (エリア内に戻る)', () {
      final outsideFix = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(outsideFix);

      final insideFix = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: outsideFix.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(insideFix);
      expect(snapshot.status, LocationStateStatus.inner);
    });

    test('outerPending → near (エリア内に戻る)', () {
      final outsideFix = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(outsideFix);

      final insideFix = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 5,
        timestamp: outsideFix.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(insideFix);
      expect(snapshot.status, LocationStateStatus.near);
    });

    test('outerPending → outer (hysteresis到達)', () {
      final outsideFix = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(outsideFix);

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
    });

    test('outerPending → outerPending (継続)', () {
      final outsideFix = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(outsideFix);

      final snapshot = machine.evaluate(
        LocationFix(
          latitude: outsideFix.latitude,
          longitude: outsideFix.longitude,
          accuracyMeters: 5,
          timestamp: outsideFix.timestamp.add(const Duration(seconds: 1)),
        ),
      );
      expect(snapshot.status, LocationStateStatus.outerPending);
    });

    test('outerPending → gpsBad', () {
      final outsideFix = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      );
      machine.evaluate(outsideFix);

      final snapshot = machine.evaluate(
        LocationFix(
          latitude: outsideFix.latitude,
          longitude: outsideFix.longitude,
          accuracyMeters: 50,
          timestamp: outsideFix.timestamp.add(const Duration(seconds: 1)),
        ),
      );
      expect(snapshot.status, LocationStateStatus.gpsBad);
    });

    test('outer → inner (精度良好)', () {
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

      final insideFix = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: outsideFix.timestamp.add(const Duration(seconds: 30)),
      );
      snapshot = machine.evaluate(insideFix);
      expect(snapshot.status, LocationStateStatus.inner);
    });

    test('outer → near (精度良好)', () {
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

      final insideFix = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 5,
        timestamp: outsideFix.timestamp.add(const Duration(seconds: 30)),
      );
      snapshot = machine.evaluate(insideFix);
      expect(snapshot.status, LocationStateStatus.near);
    });

    test('outer → inner (精度不良でも内側)', () {
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

      final insideWithBadGPS = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 50,
        timestamp: outsideFix.timestamp.add(const Duration(seconds: 30)),
      );
      snapshot = machine.evaluate(insideWithBadGPS);
      expect(snapshot.status, LocationStateStatus.inner);
      expect(snapshot.horizontalAccuracyM, 50);
    });

    test('outer → near (精度不良でも内側)', () {
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

      final insideWithBadGPS = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 50,
        timestamp: outsideFix.timestamp.add(const Duration(seconds: 30)),
      );
      snapshot = machine.evaluate(insideWithBadGPS);
      expect(snapshot.status, LocationStateStatus.near);
      expect(snapshot.horizontalAccuracyM, 50);
    });

    test('outer → outer (精度不良でも外側)', () {
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

      final outsideWithBadGPS = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 50,
        timestamp: outsideFix.timestamp.add(const Duration(seconds: 30)),
      );
      snapshot = machine.evaluate(outsideWithBadGPS);
      expect(snapshot.status, LocationStateStatus.outer);
      expect(snapshot.horizontalAccuracyM, 50);
    });

    test('gpsBad → inner (精度改善 + エリア内)', () {
      final badFix = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 50,
        timestamp: DateTime.now(),
      );
      machine.evaluate(badFix);

      final goodFix = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: badFix.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(goodFix);
      expect(snapshot.status, LocationStateStatus.inner);
    });

    test('gpsBad → near (精度改善 + エリア内)', () {
      final badFix = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 50,
        timestamp: DateTime.now(),
      );
      machine.evaluate(badFix);

      final goodFix = LocationFix(
        latitude: 35.0,
        longitude: 139.0095,
        accuracyMeters: 5,
        timestamp: badFix.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(goodFix);
      expect(snapshot.status, LocationStateStatus.near);
    });

    test('gpsBad → outerPending (精度改善 + エリア外)', () {
      final badFix = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 50,
        timestamp: DateTime.now(),
      );
      machine.evaluate(badFix);

      final goodFix = LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: badFix.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(goodFix);
      expect(snapshot.status, LocationStateStatus.outerPending);
    });

    test('gpsBad → gpsBad (継続)', () {
      final badFix1 = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 50,
        timestamp: DateTime.now(),
      );
      machine.evaluate(badFix1);

      final badFix2 = LocationFix(
        latitude: 35.005,
        longitude: 139.005,
        accuracyMeters: 45,
        timestamp: badFix1.timestamp.add(const Duration(seconds: 1)),
      );
      final snapshot = machine.evaluate(badFix2);
      expect(snapshot.status, LocationStateStatus.gpsBad);
    });
  });
}
