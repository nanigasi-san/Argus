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
      logEnabled: true,
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
          timestamp: outsideFix.timestamp.add(Duration(seconds: i + 1)),
        ),
      );
    }

    expect(snapshot.status, LocationStateStatus.outer);
  });
}
