import 'dart:math';

import '../geo/area_index.dart';
import '../geo/geo_model.dart';
import '../geo/point_in_polygon.dart';
import '../io/config.dart';
import '../platform/location_service.dart';
import 'hysteresis_counter.dart';
import 'state.dart';

/// 位置情報に基づいて状態を評価し、状態遷移を管理する状態機械。
///
/// GeoJSONで定義されたエリアと現在位置の関係を評価し、
/// INNER、NEAR、OUTER_PENDING、OUTER、GPS_BADなどの状態を判定します。
/// ヒステリシス機構により、OUTER状態への遷移は複数のサンプルと時間条件を満たす必要があります。
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

  /// 現在の状態を取得します。
  LocationStateStatus get current => _current;

  /// 設定を更新します。
  ///
  /// 設定が更新されると、ヒステリシスカウンタも新しい設定値で再初期化されます。
  void updateConfig(AppConfig config) {
    _config = config;
    _hysteresis = HysteresisCounter(
      requiredSamples: config.leaveConfirmSamples,
      requiredDuration: Duration(seconds: config.leaveConfirmSeconds),
    );
  }

  /// GeoJSONジオメトリとエリアインデックスを更新します。
  ///
  /// ジオメトリが更新されると、ヒステリシスカウンタがリセットされ、
  /// 状態が`waitStart`（ジオメトリあり）または`waitGeoJson`（ジオメトリなし）に遷移します。
  void updateGeometry(GeoModel geoModel, AreaIndex index) {
    _geoModel = geoModel;
    _areaIndex = index;
    _hysteresis.reset();
    _current = geoModel.hasGeometry
        ? LocationStateStatus.waitStart
        : LocationStateStatus.waitGeoJson;
  }

  /// 位置情報を評価し、現在の状態を返します。
  ///
  /// 位置情報の精度、エリア内外の判定、ヒステリシス条件などを考慮して
  /// 適切な状態を決定します。
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
        final searchPolys = _candidatePolygons(fix.latitude, fix.longitude);
        if (searchPolys.isEmpty) {
          final boundsEval = _nearestBoundsEvaluation(
            fix.latitude,
            fix.longitude,
          );
          return StateSnapshot(
            status: LocationStateStatus.outer,
            timestamp: fix.timestamp,
            horizontalAccuracyM: fix.accuracyMeters,
            distanceToBoundaryM: boundsEval?.distanceToBoundaryM,
            geoJsonLoaded: true,
            nearestBoundaryPoint: boundsEval?.nearestPoint,
            bearingToBoundaryDeg: boundsEval?.bearingToBoundaryDeg,
            notes:
                'Low accuracy ${fix.accuracyMeters?.toStringAsFixed(1) ?? '-'}m, but maintaining OUTER state',
          );
        }

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

    final searchPolys = _candidatePolygons(fix.latitude, fix.longitude);
    if (searchPolys.isEmpty) {
      final boundsEval = _nearestBoundsEvaluation(
        fix.latitude,
        fix.longitude,
      );
      final distance = boundsEval?.distanceToBoundaryM;
      final reached = _hysteresis.addSample(fix.timestamp) && distance != null;

      return StateSnapshot(
        status: reached
            ? LocationStateStatus.outer
            : LocationStateStatus.outerPending,
        timestamp: fix.timestamp,
        horizontalAccuracyM: fix.accuracyMeters,
        distanceToBoundaryM: distance,
        geoJsonLoaded: true,
        nearestBoundaryPoint: boundsEval?.nearestPoint,
        bearingToBoundaryDeg: boundsEval?.bearingToBoundaryDeg,
        notes: reached ? 'Confirmed exit' : 'Monitoring exit hysteresis',
      );
    }

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

    final distance = polygonEval.nearest?.distanceToBoundaryM;
    final reached = _hysteresis.addSample(fix.timestamp);

    if (!reached) {
      return StateSnapshot(
        status: LocationStateStatus.outerPending,
        timestamp: fix.timestamp,
        horizontalAccuracyM: fix.accuracyMeters,
        distanceToBoundaryM: distance,
        geoJsonLoaded: true,
        nearestBoundaryPoint: polygonEval.nearest?.nearestPoint,
        bearingToBoundaryDeg: polygonEval.nearest?.bearingToBoundaryDeg,
        notes: 'Monitoring exit hysteresis',
      );
    }

    final outerSnapshot = StateSnapshot(
      status: LocationStateStatus.outer,
      timestamp: fix.timestamp,
      horizontalAccuracyM: fix.accuracyMeters,
      distanceToBoundaryM: distance,
      geoJsonLoaded: true,
      nearestBoundaryPoint: polygonEval.nearest?.nearestPoint,
      bearingToBoundaryDeg: polygonEval.nearest?.bearingToBoundaryDeg,
      notes: 'Confirmed exit',
    );

    // outer になった場合は GPS_BAD の精度チェックでは取り消さない。
    return outerSnapshot;
  }

  List<GeoPolygon> _candidatePolygons(double latitude, double longitude) {
    return _areaIndex.lookup(latitude, longitude).toList();
  }

  _BoundsEvaluation? _nearestBoundsEvaluation(
    double latitude,
    double longitude,
  ) {
    GeoPolygon? nearestPolygon;
    var nearestDistanceSquared = double.infinity;
    for (final polygon in _geoModel.polygons) {
      final distanceSquared = _distanceToBoundsSquared(
        latitude,
        longitude,
        polygon,
      );
      if (distanceSquared < nearestDistanceSquared) {
        nearestDistanceSquared = distanceSquared;
        nearestPolygon = polygon;
      }
    }
    if (nearestPolygon == null) {
      return null;
    }

    final nearestPoint = LatLng(
      latitude.clamp(nearestPolygon.minLat, nearestPolygon.maxLat),
      longitude.clamp(nearestPolygon.minLon, nearestPolygon.maxLon),
    );
    final distance = _haversine(
      latitude,
      longitude,
      nearestPoint.latitude,
      nearestPoint.longitude,
    );
    return _BoundsEvaluation(
      distanceToBoundaryM: distance,
      nearestPoint: nearestPoint,
      bearingToBoundaryDeg: _bearingDegrees(
        latitude,
        longitude,
        nearestPoint.latitude,
        nearestPoint.longitude,
      ),
    );
  }

  double _distanceToBoundsSquared(
    double latitude,
    double longitude,
    GeoPolygon polygon,
  ) {
    final latDelta = latitude < polygon.minLat
        ? polygon.minLat - latitude
        : latitude > polygon.maxLat
            ? latitude - polygon.maxLat
            : 0.0;
    final lonDelta = longitude < polygon.minLon
        ? polygon.minLon - longitude
        : longitude > polygon.maxLon
            ? longitude - polygon.maxLon
            : 0.0;
    return (latDelta * latDelta) + (lonDelta * lonDelta);
  }

  _PolygonEvaluationResult _evaluatePolygons(
    double latitude,
    double longitude,
    Iterable<GeoPolygon> polygons,
  ) {
    PointInPolygonEvaluation? inside;
    PointInPolygonEvaluation? nearest;
    for (final polygon in polygons) {
      if (!_pip.containsPoint(latitude, longitude, polygon)) {
        continue;
      }
      final evaluation = _pip.evaluatePoint(latitude, longitude, polygon);
      if (nearest == null ||
          evaluation.distanceToBoundaryM < nearest.distanceToBoundaryM) {
        nearest = evaluation;
      }
      inside ??= evaluation;
    }

    return _PolygonEvaluationResult(inside: inside, nearest: nearest);
  }

  double _haversine(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _bearingDegrees(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final lat1Rad = _degToRad(lat1);
    final lat2Rad = _degToRad(lat2);
    final dLon = _degToRad(lon2 - lon1);

    final y = sin(dLon) * cos(lat2Rad);
    final x =
        cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLon);
    final bearingRad = atan2(y, x);
    final bearingDeg = _radToDeg(bearingRad);
    return (bearingDeg + 360) % 360;
  }

  double _degToRad(double deg) => deg * pi / 180;
  double _radToDeg(double rad) => rad * 180 / pi;
}

class _PolygonEvaluationResult {
  const _PolygonEvaluationResult({
    this.inside,
    this.nearest,
  });

  final PointInPolygonEvaluation? inside;
  final PointInPolygonEvaluation? nearest;
}

class _BoundsEvaluation {
  const _BoundsEvaluation({
    required this.distanceToBoundaryM,
    required this.nearestPoint,
    required this.bearingToBoundaryDeg,
  });

  final double distanceToBoundaryM;
  final LatLng nearestPoint;
  final double bearingToBoundaryDeg;
}
