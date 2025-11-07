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

  /// 位置情報を評価して状態スナップショットを生成します。
  StateSnapshot _evaluateInternal(LocationFix fix) {
    if (!_geoModel.hasGeometry) {
      return _createWaitGeoJsonSnapshot(fix);
    }

    if (_isAccuracyBad(fix)) {
      return _evaluateWithBadAccuracy(fix);
    }

    return _evaluateWithGoodAccuracy(fix);
  }

  /// GeoJSON未ロード時のスナップショットを生成します。
  StateSnapshot _createWaitGeoJsonSnapshot(LocationFix fix) {
    _current = LocationStateStatus.waitGeoJson;
    return StateSnapshot(
      status: LocationStateStatus.waitGeoJson,
      timestamp: fix.timestamp,
      horizontalAccuracyM: fix.accuracyMeters,
      notes: 'GeoJSON not loaded',
    );
  }

  /// 精度が不良な場合の評価を行います。
  ///
  /// OUTER状態の場合は内側に戻ったかどうかをチェックし、
  /// それ以外の場合はGPS_BAD状態に遷移します。
  StateSnapshot _evaluateWithBadAccuracy(LocationFix fix) {
    if (_current == LocationStateStatus.outer) {
      return _evaluateOuterWithBadAccuracy(fix);
    }
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

  /// OUTER状態で精度が不良な場合の評価を行います。
  ///
  /// 内側に戻ったかどうかをチェックし、内側ならINNER/NEARに遷移、
  /// 外側ならOUTERを維持します。
  StateSnapshot _evaluateOuterWithBadAccuracy(LocationFix fix) {
    final candidatePolys = _areaIndex
        .lookup(fix.latitude, fix.longitude)
        .toList();
    final searchPolys =
        candidatePolys.isEmpty ? _geoModel.polygons : candidatePolys;
    final polygonEval = _evaluatePolygons(
      fix.latitude,
      fix.longitude,
      searchPolys,
    );

    final insideEval = polygonEval.inside;
    if (insideEval != null && insideEval.contains) {
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

  /// 精度が良好な場合の評価を行います。
  StateSnapshot _evaluateWithGoodAccuracy(LocationFix fix) {
    final candidatePolys = _areaIndex
        .lookup(fix.latitude, fix.longitude)
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
      return _createInsideSnapshot(fix, evaluation);
    }

    return _createOutsideSnapshot(fix, polygonEval.nearest);
  }

  /// エリア内のスナップショットを生成します。
  StateSnapshot _createInsideSnapshot(
    LocationFix fix,
    PointInPolygonEvaluation evaluation,
  ) {
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

  /// エリア外のスナップショットを生成します。
  StateSnapshot _createOutsideSnapshot(
    LocationFix fix,
    PointInPolygonEvaluation? nearest,
  ) {
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

    return StateSnapshot(
      status: LocationStateStatus.outer,
      timestamp: fix.timestamp,
      horizontalAccuracyM: fix.accuracyMeters,
      distanceToBoundaryM: distance,
      geoJsonLoaded: true,
      nearestBoundaryPoint: nearest?.nearestPoint,
      bearingToBoundaryDeg: nearest?.bearingToBoundaryDeg,
      notes: 'Confirmed exit',
    );
  }

  /// 位置情報の精度が不良かどうかを判定します。
  bool _isAccuracyBad(LocationFix fix) {
    return fix.accuracyMeters == null ||
        fix.accuracyMeters! > _config.gpsAccuracyBadMeters;
  }

  /// 複数のポリゴンに対して位置情報を評価します。
  ///
  /// エリア内のポリゴンと最寄りのポリゴンの両方を検出します。
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
