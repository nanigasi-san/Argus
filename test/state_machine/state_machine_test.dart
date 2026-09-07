import 'package:flutter_test/flutter_test.dart';

import 'package:argus/geo/area_index.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/geo/point_in_polygon.dart';
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
    expect(snapshot.distanceToBoundaryM, isNotNull);
    expect(snapshot.nearestBoundaryPoint, isNotNull);
    expect(snapshot.bearingToBoundaryDeg, isNotNull);
  });

  test('GPS timestamp cannot satisfy monotonic leave duration early', () {
    final baseTimestamp = DateTime.utc(2024, 1, 1);

    for (var i = 0; i < 3; i++) {
      final snapshot = machine.evaluate(
        LocationFix(
          latitude: 35.02,
          longitude: 139.02,
          accuracyMeters: 5,
          timestamp: baseTimestamp.add(Duration(seconds: i * 30)),
          monitoringElapsed: Duration(seconds: i),
        ),
      );
      expect(snapshot.status, LocationStateStatus.outerPending);
    }

    final confirmed = machine.evaluate(
      LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: baseTimestamp.add(const Duration(minutes: 10)),
        monitoringElapsed: const Duration(seconds: 10),
      ),
    );
    expect(confirmed.status, LocationStateStatus.outer);
  });

  test('resetMonitoring clears pending samples and elapsed origin', () {
    machine.evaluate(
      LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: DateTime.utc(2024, 1, 1),
        monitoringElapsed: Duration.zero,
      ),
    );
    expect(machine.pendingSampleCount, 1);
    expect(machine.pendingElapsed(const Duration(seconds: 3)),
        const Duration(seconds: 3));

    machine.resetMonitoring();

    expect(machine.pendingSampleCount, 0);
    final snapshot = machine.evaluate(
      LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: DateTime.utc(2024, 1, 1, 0, 1),
        monitoringElapsed: const Duration(seconds: 20),
      ),
    );
    expect(snapshot.status, LocationStateStatus.outerPending);
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

  test('keeps OUTER when an inside-looking fix has bad GPS accuracy', () {
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
    final trustedDistance = snapshot.distanceToBoundaryM;
    final trustedBoundary = snapshot.nearestBoundaryPoint;
    final trustedBearing = snapshot.bearingToBoundaryDeg;

    // Now move back inside with bad GPS accuracy
    final insideWithBadGPS = LocationFix(
      latitude: 35.005,
      longitude: 139.005,
      accuracyMeters: 50, // > gpsAccuracyBadMeters (40)
      timestamp: outsideFix.timestamp.add(const Duration(seconds: 30)),
    );

    snapshot = machine.evaluate(insideWithBadGPS);
    // A low-quality fix must never silence an active OUTER alert.
    expect(snapshot.status, LocationStateStatus.outer);
    expect(snapshot.horizontalAccuracyM, 50);
    expect(snapshot.distanceToBoundaryM, trustedDistance);
    expect(snapshot.nearestBoundaryPoint?.latitude, trustedBoundary?.latitude);
    expect(
        snapshot.nearestBoundaryPoint?.longitude, trustedBoundary?.longitude);
    expect(snapshot.bearingToBoundaryDeg, trustedBearing);
    expect(snapshot.notes, contains('last reliable guidance'));
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

  test('maintains OUTER with bad GPS inside bounds but outside polygon', () {
    final concave = GeoPolygon(
      points: const [
        LatLng(0, 0),
        LatLng(0, 2),
        LatLng(0.75, 2),
        LatLng(0.75, 0.75),
        LatLng(2, 0.75),
        LatLng(2, 0),
      ],
      name: 'L',
    );
    final model = GeoModel([concave]);
    final localMachine = StateMachine(config: config)
      ..updateGeometry(model, AreaIndex.build(model.polygons));
    final base = DateTime.utc(2024, 1, 1);

    var snapshot = localMachine.evaluate(
      LocationFix(
        latitude: 1.5,
        longitude: 1.5,
        accuracyMeters: 5,
        timestamp: base,
      ),
    );
    for (var i = 0; i < config.leaveConfirmSamples; i++) {
      snapshot = localMachine.evaluate(
        LocationFix(
          latitude: 1.5,
          longitude: 1.5,
          accuracyMeters: 5,
          timestamp: base.add(Duration(seconds: 20 + i)),
        ),
      );
    }
    expect(snapshot.status, LocationStateStatus.outer);

    snapshot = localMachine.evaluate(
      LocationFix(
        latitude: 1.5,
        longitude: 1.5,
        accuracyMeters: 80,
        timestamp: base.add(const Duration(seconds: 40)),
      ),
    );

    expect(snapshot.status, LocationStateStatus.outer);
    expect(snapshot.notes, contains('maintaining OUTER'));
    expect(snapshot.distanceToBoundaryM, isNotNull);
    expect(snapshot.nearestBoundaryPoint, isNotNull);
    expect(snapshot.bearingToBoundaryDeg, isNotNull);
  });

  test('confirms OUTER using bounds distance when no polygon is nearby', () {
    final base = DateTime.utc(2024, 1, 1);
    late StateSnapshot snapshot;

    for (var i = 0; i <= config.leaveConfirmSamples; i++) {
      snapshot = machine.evaluate(
        LocationFix(
          latitude: 35.5,
          longitude: 139.5,
          accuracyMeters: 5,
          timestamp: base.add(Duration(seconds: 20 * i)),
        ),
      );
    }

    expect(snapshot.status, LocationStateStatus.outer);
    expect(snapshot.distanceToBoundaryM, isNotNull);
    expect(snapshot.nearestBoundaryPoint, isNotNull);
    expect(snapshot.bearingToBoundaryDeg, isNotNull);
    expect(snapshot.notes, 'Confirmed exit');
  });

  test('chooses nearest evaluation when multiple polygons contain point', () {
    final broad = GeoPolygon(
      points: const [
        LatLng(0, 0),
        LatLng(0, 10),
        LatLng(10, 10),
        LatLng(10, 0),
      ],
      name: 'broad',
    );
    final tight = GeoPolygon(
      points: const [
        LatLng(4.9999, 4.9999),
        LatLng(4.9999, 5.0001),
        LatLng(5.0001, 5.0001),
        LatLng(5.0001, 4.9999),
      ],
      name: 'tight',
    );
    final model = GeoModel([broad, tight]);
    final localMachine = StateMachine(config: config)
      ..updateGeometry(model, AreaIndex.build(model.polygons));

    final snapshot = localMachine.evaluate(
      LocationFix(
        latitude: 5,
        longitude: 5,
        accuracyMeters: 5,
        timestamp: DateTime.utc(2024, 1, 1),
      ),
    );

    expect(snapshot.status, LocationStateStatus.inner);
    expect(snapshot.distanceToBoundaryM, greaterThan(20000));
  });

  test('skips polygon vertex evaluation when outside all bounds', () {
    final polygons = <GeoPolygon>[
      GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.0, 139.01),
          LatLng(35.01, 139.01),
          LatLng(35.01, 139.0),
        ],
        name: 'near',
      ),
      for (var i = 0; i < 20; i++)
        GeoPolygon(
          points: [
            LatLng(45.0 + i, 149.0 + i),
            LatLng(45.0 + i, 149.01 + i),
            LatLng(45.01 + i, 149.01 + i),
            LatLng(45.01 + i, 149.0 + i),
          ],
          name: 'far-$i',
        ),
    ];
    final model = GeoModel(polygons);
    final countingPip = _CountingPointInPolygon();
    final indexedMachine = StateMachine(
      config: config,
      pointInPolygon: countingPip,
    )..updateGeometry(model, AreaIndex.build(model.polygons));

    final snapshot = indexedMachine.evaluate(
      LocationFix(
        latitude: 35.02,
        longitude: 139.02,
        accuracyMeters: 5,
        timestamp: DateTime.now(),
      ),
    );

    expect(snapshot.status, LocationStateStatus.outerPending);
    expect(snapshot.distanceToBoundaryM, greaterThan(0));
    expect(countingPip.evaluationCount, 0);
  });

  test('treats non-finite coordinates as an unusable fix', () {
    // 回帰テスト: NaN座標はバウンディングボックス比較がすべてfalseになるため
    // 候補ポリゴンが空になり、距離もNaNになる。素通しすると「エリア外だが
    // OUTERに確定しない」outerPending のまま警報が鳴らない。
    machine.resetMonitoring();

    final snapshot = machine.evaluate(
      LocationFix(
        latitude: double.nan,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: DateTime.utc(2024, 1, 1),
        monitoringElapsed: Duration.zero,
      ),
    );

    expect(snapshot.status, LocationStateStatus.gpsBad);
  });

  test('treats out-of-range coordinates as an unusable fix', () {
    machine.resetMonitoring();

    final snapshot = machine.evaluate(
      LocationFix(
        latitude: 91,
        longitude: 139.005,
        accuracyMeters: 5,
        timestamp: DateTime.utc(2024, 1, 1),
        monitoringElapsed: Duration.zero,
      ),
    );

    expect(snapshot.status, LocationStateStatus.gpsBad);
  });

  test('a bad-accuracy fix does not discard exit evidence', () {
    // 回帰テスト: 精度不良でヒステリシスをリセットすると、木の下などで精度が
    // 周期的に悪化する環境では leaveConfirmSeconds に到達できず、実際に
    // エリア外なのに警報が永久に鳴らない。
    machine.resetMonitoring();

    LocationFix outside(int second, {double accuracy = 5}) => LocationFix(
          latitude: 35.05,
          longitude: 139.05,
          accuracyMeters: accuracy,
          timestamp: DateTime.utc(2024, 1, 1).add(Duration(seconds: second)),
          monitoringElapsed: Duration(seconds: second),
        );

    expect(
      machine.evaluate(outside(0)).status,
      LocationStateStatus.outerPending,
    );
    expect(
      machine.evaluate(outside(4)).status,
      LocationStateStatus.outerPending,
    );

    // 精度不良の1点をはさむ。エリア内に戻った証拠ではないので、
    // これまでのエリア外サンプルは捨てない。
    expect(
      machine.evaluate(outside(6, accuracy: 999)).status,
      LocationStateStatus.gpsBad,
    );

    expect(machine.evaluate(outside(11)).status, LocationStateStatus.outer);
  });

  test('a good fix inside still clears exit evidence', () {
    machine.resetMonitoring();

    LocationFix at(double lat, double lon, int second) => LocationFix(
          latitude: lat,
          longitude: lon,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1).add(Duration(seconds: second)),
          monitoringElapsed: Duration(seconds: second),
        );

    machine.evaluate(at(35.05, 139.05, 0));
    machine.evaluate(at(35.05, 139.05, 4));
    // 精度良好でエリア内 → 証拠はリセットされる。
    expect(
      machine.evaluate(at(35.005, 139.005, 5)).status,
      anyOf(LocationStateStatus.inner, LocationStateStatus.near),
    );
    expect(
      machine.evaluate(at(35.05, 139.05, 20)).status,
      LocationStateStatus.outerPending,
    );
  });
}

class _CountingPointInPolygon extends PointInPolygon {
  _CountingPointInPolygon();

  final evaluatedNames = <String>[];

  int get evaluationCount => evaluatedNames.length;

  @override
  PointInPolygonEvaluation evaluatePoint(
    double lat,
    double lon,
    GeoPolygon polygon,
  ) {
    evaluatedNames.add(polygon.name ?? '');
    return super.evaluatePoint(lat, lon, polygon);
  }
}
