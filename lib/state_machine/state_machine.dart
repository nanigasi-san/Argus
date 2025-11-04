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
    _hysteresis.reset();
    _current = geoModel.hasGeometry
        ? LocationStateStatus.init
        : LocationStateStatus.waitGeoJson;
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
      // ただし、実際に内側に戻ったかどうかはチェックする必要がある
      if (_current == LocationStateStatus.outer) {
        // OUTER状態の場合、精度が悪くても内側に戻ったかどうかをチェック
        final candidatePolys = _areaIndex
            .lookup(
              fix.latitude,
              fix.longitude,
            )
            .toList();
        final searchPolys =
            candidatePolys.isEmpty ? _geoModel.polygons : candidatePolys;

        final polygonEval = _evaluatePolygons(
          fix.latitude,
          fix.longitude,
          searchPolys,
        );

        // Check if the fix has re-entered the area
        final insideEval = polygonEval.inside;

        if (insideEval != null && insideEval.contains) {
          // When accuracy is poor but we are inside, treat as INNER/NEAR
          _hysteresis.reset();
          final distance = insideEval.distanceToBoundaryM;
          final isNear = distance < _config.innerBufferM;
          return StateSnapshot(
            status:
                isNear ? LocationStateStatus.near : LocationStateStatus.inner,
            timestamp: fix.timestamp,
            horizontalAccuracyM: fix.accuracyMeters,
            distanceToBoundaryM: distance,
            geoJsonLoaded: true,
            nearestBoundaryPoint: insideEval.nearestPoint,
            bearingToBoundaryDeg: insideEval.bearingToBoundaryDeg,
            notes:
                'Low accuracy ${fix.accuracyMeters?.toStringAsFixed(1) ?? '-'}m, but inside area',
          );
        }

        // Otherwise stay in OUTER with best-effort distance
        final nearestEval = polygonEval.nearest;
        final distance = nearestEval?.distanceToBoundaryM;
        return StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: fix.timestamp,
          horizontalAccuracyM: fix.accuracyMeters,
          distanceToBoundaryM: distance,
          geoJsonLoaded: true,
          nearestBoundaryPoint: nearestEval?.nearestPoint,
          bearingToBoundaryDeg: nearestEval?.bearingToBoundaryDeg,
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

    final polygonEval = _evaluatePolygons(
      fix.latitude,
      fix.longitude,
      searchPolys,
    );

    final evaluation = polygonEval.inside;

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
        nearestBoundaryPoint: evaluation.nearestPoint,
        bearingToBoundaryDeg: evaluation.bearingToBoundaryDeg,
      );
    }

    final nearest = polygonEval.nearest;

    final distance = nearest?.distanceToBoundaryM;
    final reached = _hysteresis.addSample(fix.timestamp) && distance != null;

    if (!reached) {
      return StateSnapshot(
        status: LocationStateStatus.outerPending,
        timestamp: fix.timestamp,
        horizontalAccuracyM: fix.accuracyMeters,
        distanceToBoundaryM: distance,
        geoJsonLoaded: true,
        nearestBoundaryPoint: nearest?.nearestPoint,
        bearingToBoundaryDeg: nearest?.bearingToBoundaryDeg,
        notes: 'Monitoring exit hysteresis',
      );
    }

    final outerSnapshot = StateSnapshot(
      status: LocationStateStatus.outer,
      timestamp: fix.timestamp,
      horizontalAccuracyM: fix.accuracyMeters,
      distanceToBoundaryM: distance,
      geoJsonLoaded: true,
      nearestBoundaryPoint: nearest?.nearestPoint,
      bearingToBoundaryDeg: nearest?.bearingToBoundaryDeg,
      notes: 'Confirmed exit',
    );

    // outer になった場合は GPS_BAD の精度チェックでは取り消さない。
    return outerSnapshot;
  }

  _PolygonEvaluationResult _evaluatePolygons(
    double latitude,
    double longitude,
    Iterable<GeoPolygon> polygons,
  ) {
    PointInPolygonEvaluation? inside;
    PointInPolygonEvaluation? nearest;
    for (final polygon in polygons) {
      final evaluation = _pip.evaluatePoint(
        latitude,
        longitude,
        polygon,
      );
      if (nearest == null ||
          evaluation.distanceToBoundaryM < nearest.distanceToBoundaryM) {
        nearest = evaluation;
      }
      if (inside == null && evaluation.contains) {
        inside = evaluation;
      }
    }
    return _PolygonEvaluationResult(inside: inside, nearest: nearest);
  }
}

class _PolygonEvaluationResult {
  const _PolygonEvaluationResult({
    this.inside,
    this.nearest,
  });

  final PointInPolygonEvaluation? inside;
  final PointInPolygonEvaluation? nearest;
}
