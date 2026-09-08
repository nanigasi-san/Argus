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
  double? _lastTrustedOuterDistanceM;
  LatLng? _lastTrustedOuterBoundaryPoint;
  double? _lastTrustedOuterBearingDeg;

  /// 現在の状態を取得します。
  LocationStateStatus get current => _current;

  int get pendingSampleCount => _hysteresis.sampleCount;

  Duration pendingElapsed(Duration observedAt) =>
      _hysteresis.elapsedAt(observedAt);

  void resetMonitoring() {
    _hysteresis.reset();
    _clearTrustedOuterNavigation();
    _current = _geoModel.hasGeometry
        ? LocationStateStatus.waitStart
        : LocationStateStatus.waitGeoJson;
  }

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
    _clearTrustedOuterNavigation();
    _current = geoModel.hasGeometry
        ? LocationStateStatus.waitStart
        : LocationStateStatus.waitGeoJson;
  }

  /// 位置情報を評価し、現在の状態を返します。
  ///
  /// 位置情報の精度、エリア内外の判定、ヒステリシス条件などを考慮して
  /// 適切な状態を決定します。
  StateSnapshot evaluate(LocationFix fix) {
    final observedAt = fix.monitoringElapsed ??
        Duration(microseconds: fix.timestamp.microsecondsSinceEpoch);
    final snapshot = _evaluateInternal(fix, observedAt);
    final hasHealthyAccuracy = _isUsableFix(fix);
    if (hasHealthyAccuracy && snapshot.status == LocationStateStatus.outer) {
      // 値が取れなかったfixで上書きしない。上書きすると、直前まで表示できて
      // いた最後の信頼できる案内が消えてしまう。
      if (snapshot.distanceToBoundaryM != null) {
        _lastTrustedOuterDistanceM = snapshot.distanceToBoundaryM;
        _lastTrustedOuterBoundaryPoint = snapshot.nearestBoundaryPoint;
        _lastTrustedOuterBearingDeg = snapshot.bearingToBoundaryDeg;
      }
    } else if (hasHealthyAccuracy &&
        snapshot.status != LocationStateStatus.outerPending) {
      _clearTrustedOuterNavigation();
    }
    _current = snapshot.status;
    return snapshot;
  }

  /// 判定に使える測位か。
  ///
  /// 精度に加えて座標の有限性と範囲も見る。NaN や範囲外の座標が来ると、
  /// バウンディングボックスの比較がすべて false になって候補ポリゴンが空になり、
  /// 距離計算も NaN になる。結果として「エリア外だがOUTERに確定しない」
  /// outerPending のまま警報が鳴らない状態が続く。
  bool _isUsableFix(LocationFix fix) {
    final accuracy = fix.accuracyMeters;
    if (accuracy == null ||
        !accuracy.isFinite ||
        accuracy > _config.gpsAccuracyBadMeters) {
      return false;
    }
    final latitude = fix.latitude;
    final longitude = fix.longitude;
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  StateSnapshot _evaluateInternal(LocationFix fix, Duration observedAt) {
    if (!_geoModel.hasGeometry) {
      _current = LocationStateStatus.waitGeoJson;
      return StateSnapshot(
        status: LocationStateStatus.waitGeoJson,
        timestamp: fix.timestamp,
        horizontalAccuracyM: fix.accuracyMeters,
        notes: 'GeoJSON not loaded',
      );
    }

    if (!_isUsableFix(fix)) {
      // 確定済みOUTERは、精度不良の測位では解除しない。
      // 誤差の大きい1点が偶然エリア内を指して警報を止める方が危険なため、
      // 警報は維持し、案内には最後の信頼できるfixだけを使用する。
      if (_current == LocationStateStatus.outer) {
        return StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: fix.timestamp,
          horizontalAccuracyM: fix.accuracyMeters,
          distanceToBoundaryM: _lastTrustedOuterDistanceM,
          geoJsonLoaded: true,
          nearestBoundaryPoint: _lastTrustedOuterBoundaryPoint,
          bearingToBoundaryDeg: _lastTrustedOuterBearingDeg,
          navigationFromLastReliableFix: true,
          notes:
              'Low accuracy ${fix.accuracyMeters?.toStringAsFixed(1) ?? '-'}m; maintaining OUTER with last reliable guidance',
        );
      }
      // OUTER状態でない場合のみ、GPS_BADに遷移。
      // ヒステリシスはリセットしない。使えない測位は「エリア内に戻った証拠」
      // ではないので、これまでに数えた良好なエリア外サンプルを捨てる理由がない。
      // リセットしていると、木の下などで精度が一定周期で悪化する環境では
      // leaveConfirmSeconds に到達できず、実際にエリア外なのに警報が
      // 永久に鳴らない。エリア内へ戻ったことは精度良好なfixだけが証明する。
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
      // 確定条件はヒステリシスだけで決める。distance は案内表示用の値であり、
      // これを条件に混ぜると、距離を計算できなかっただけで警報が出なくなる。
      final reached = _hysteresis.addSample(observedAt);

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
        notes: reached ? 'Confirmed exit' : _pendingNotes(observedAt),
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
    final reached = _hysteresis.addSample(observedAt);

    if (!reached) {
      return StateSnapshot(
        status: LocationStateStatus.outerPending,
        timestamp: fix.timestamp,
        horizontalAccuracyM: fix.accuracyMeters,
        distanceToBoundaryM: distance,
        geoJsonLoaded: true,
        nearestBoundaryPoint: polygonEval.nearest?.nearestPoint,
        bearingToBoundaryDeg: polygonEval.nearest?.bearingToBoundaryDeg,
        notes: _pendingNotes(observedAt),
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

  String _pendingNotes(Duration observedAt) {
    final elapsedMs = _hysteresis.elapsedAt(observedAt).inMilliseconds;
    return 'Monitoring exit hysteresis: '
        'samples=${_hysteresis.sampleCount}/${_config.leaveConfirmSamples} '
        'elapsed=${(elapsedMs / 1000).toStringAsFixed(1)}/'
        '${_config.leaveConfirmSeconds}s';
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
      final evaluation = _pip.evaluatePoint(latitude, longitude, polygon);
      if (nearest == null ||
          evaluation.distanceToBoundaryM < nearest.distanceToBoundaryM) {
        nearest = evaluation;
      }
      if (evaluation.contains) {
        inside ??= evaluation;
      }
    }

    return _PolygonEvaluationResult(inside: inside, nearest: nearest);
  }

  void _clearTrustedOuterNavigation() {
    _lastTrustedOuterDistanceM = null;
    _lastTrustedOuterBoundaryPoint = null;
    _lastTrustedOuterBearingDeg = null;
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
