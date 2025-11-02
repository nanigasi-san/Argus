import 'package:collection/collection.dart';

import '../geo/area_index.dart';
import '../geo/geo_model.dart';
import '../geo/point_in_polygon.dart';
import '../platform/location_service.dart';
import '../io/config.dart';
import 'hysteresis_counter.dart';
import 'state.dart';

class StateMachineContext {
  StateMachineContext({
    required this.config,
    required this.geoModel,
    required this.areaIndex,
    required this.pointInPolygon,
  });

  final AppConfig config;
  final GeoModel geoModel;
  final AreaIndex areaIndex;
  final PointInPolygon pointInPolygon;

  bool get hasGeometry => geoModel.hasGeometry;
}

class StateMachine {
  StateMachine({
    required AppConfig config,
    GeoModel? geoModel,
    AreaIndex? areaIndex,
    PointInPolygon? pointInPolygon,
  })  : _config = config,
        _geoModel = geoModel ?? GeoModel.empty(),
        _areaIndex = areaIndex ?? AreaIndex.empty(),
        _pip = pointInPolygon ?? const PointInPolygon(),
        _hysteresis = HysteresisCounter(
          requiredSamples: config.leaveConfirmSamples,
          requiredDuration: Duration(seconds: config.leaveConfirmSeconds),
        );

  AppConfig _config;
  GeoModel _geoModel;
  AreaIndex _areaIndex;
  final PointInPolygon _pip;
  HysteresisCounter _hysteresis;
  LocationStateStatus _current = LocationStateStatus.waitGeoJson;

  LocationStateStatus get current => _current;

  void updateConfig(AppConfig config) {
    _config = config;
    _hysteresis = HysteresisCounter(
      requiredSamples: config.leaveConfirmSamples,
      requiredDuration: Duration(seconds: config.leaveConfirmSeconds),
    );
  }

  void updateGeometry(GeoModel geoModel, AreaIndex index) {
    _geoModel = geoModel;
    _areaIndex = index;
  }

  StateSnapshot evaluate(LocationFix fix) {
    final snapshot = _evaluateInternal(fix);
    _current = snapshot.status;
    return snapshot;
  }

  StateSnapshot _evaluateInternal(LocationFix fix) {
    if (!_geoModel.hasGeometry) {
      _current = LocationStateStatus.waitGeoJson;
      return StateSnapshot(
        status: LocationStateStatus.waitGeoJson,
        timestamp: fix.timestamp,
        horizontalAccuracyM: fix.accuracyMeters,
        notes: 'GeoJSON not loaded',
      );
    }

    if (fix.accuracyMeters == null ||
        fix.accuracyMeters! > _config.gpsAccuracyBadMeters) {
      // outer になった場合は GPS_BAD の精度チェックでは取り消さない。
      if (_current == LocationStateStatus.outer) {
        // OUTER状態の場合は精度が悪くてもOUTERを維持する
        // この場合は次の評価に進む（ヒステリシスはリセットしない）
        // ただし、OUTER状態を維持するため、距離計算を試みる
        final candidatePolys = _areaIndex
            .lookup(
              fix.latitude,
              fix.longitude,
            )
            .toList();
        final searchPolys =
            candidatePolys.isEmpty ? _geoModel.polygons : candidatePolys;

        final nearestEval = searchPolys
            .map(
              (poly) => _pip.evaluatePoint(
                fix.latitude,
                fix.longitude,
                poly,
              ),
            )
            .sortedBy<num>((r) => r.distanceToBoundaryM)
            .firstOrNull;

        final distance = nearestEval?.distanceToBoundaryM;
        return StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: fix.timestamp,
          horizontalAccuracyM: fix.accuracyMeters,
          distanceToBoundaryM: distance,
          geoJsonLoaded: true,
          notes:
              'Low accuracy ${fix.accuracyMeters?.toStringAsFixed(1) ?? '-'}m, but maintaining OUTER state',
        );
      }
      // OUTER状態でない場合のみ、GPS_BADに遷移
      _hysteresis.reset();
      return StateSnapshot(
        status: LocationStateStatus.gpsBad,
        timestamp: fix.timestamp,
        horizontalAccuracyM: fix.accuracyMeters,
        distanceToBoundaryM: null,
        notes: 'Low accuracy ${fix.accuracyMeters?.toStringAsFixed(1) ?? '-'}m',
        geoJsonLoaded: true,
      );
    }

    final candidatePolys = _areaIndex
        .lookup(
          fix.latitude,
          fix.longitude,
        )
        .toList();
    final searchPolys =
        candidatePolys.isEmpty ? _geoModel.polygons : candidatePolys;

    final evaluation = searchPolys
        .map(
          (poly) => _pip.evaluatePoint(
            fix.latitude,
            fix.longitude,
            poly,
          ),
        )
        .firstWhereOrNull((result) => result.contains);

    if (evaluation != null && evaluation.contains) {
      _hysteresis.reset();
      final distance = evaluation.distanceToBoundaryM;
      final isNear = distance < _config.innerBufferM;
      return StateSnapshot(
        status: isNear ? LocationStateStatus.near : LocationStateStatus.inner,
        timestamp: fix.timestamp,
        horizontalAccuracyM: fix.accuracyMeters,
        distanceToBoundaryM: distance,
        geoJsonLoaded: true,
      );
    }

    final nearest = searchPolys
        .map(
          (poly) => _pip.evaluatePoint(
            fix.latitude,
            fix.longitude,
            poly,
          ),
        )
        .sortedBy<num>((r) => r.distanceToBoundaryM)
        .firstOrNull;

    final distance = nearest?.distanceToBoundaryM;
    final reached = _hysteresis.addSample(fix.timestamp) && distance != null;

    if (!reached) {
      return StateSnapshot(
        status: LocationStateStatus.outerPending,
        timestamp: fix.timestamp,
        horizontalAccuracyM: fix.accuracyMeters,
        distanceToBoundaryM: distance,
        geoJsonLoaded: true,
        notes: 'Monitoring exit hysteresis',
      );
    }

    final outerSnapshot = StateSnapshot(
      status: LocationStateStatus.outer,
      timestamp: fix.timestamp,
      horizontalAccuracyM: fix.accuracyMeters,
      distanceToBoundaryM: distance,
      geoJsonLoaded: true,
      notes: 'Confirmed exit',
    );

    // outer になった場合は GPS_BAD の精度チェックでは取り消さない。
    return outerSnapshot;
  }
}
