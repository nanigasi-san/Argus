import 'dart:math';

import 'geo_model.dart';

/// 点とポリゴンの関係を評価した結果。
class PointInPolygonEvaluation {
  const PointInPolygonEvaluation({
    required this.contains,
    required this.distanceToBoundaryM,
    this.nearestPoint,
    this.bearingToBoundaryDeg,
  });

  /// 点がポリゴン内部に含まれているかどうか。
  final bool contains;

  /// ポリゴンの境界までの距離（メートル）。
  final double distanceToBoundaryM;

  /// 境界上の最寄り点。
  final LatLng? nearestPoint;

  /// 最寄り境界点への方位角（0-360度、北が0度）。
  final double? bearingToBoundaryDeg;
}

/// 点とポリゴンの関係を判定するクラス。
///
/// Ray Castingアルゴリズムを使用して内外判定を行い、
/// Haversine公式を使用して距離と方位角を計算します。
class PointInPolygon {
  const PointInPolygon();

  /// 点とポリゴンの関係を評価します。
  ///
  /// 内外判定、境界までの距離、最寄り境界点、方位角を計算します。
  PointInPolygonEvaluation evaluatePoint(
    double lat,
    double lon,
    GeoPolygon polygon,
  ) {
    final contains = _rayCast(lat, lon, polygon.points);
    final nearest = _nearestPointOnPolygon(lat, lon, polygon.points);
    final distance = nearest?.distanceM ?? 0;
    final bearing = nearest != null
        ? _bearingDegrees(
            lat,
            lon,
            nearest.point.latitude,
            nearest.point.longitude,
          )
        : null;
    return PointInPolygonEvaluation(
      contains: contains,
      distanceToBoundaryM: distance,
      nearestPoint: nearest?.point,
      bearingToBoundaryDeg: bearing,
    );
  }

  /// Ray Castingアルゴリズムを使用して内外判定を行います。
  bool _rayCast(double lat, double lon, List<LatLng> points) {
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final xi = points[i].latitude;
      final yi = points[i].longitude;
      final xj = points[j].latitude;
      final yj = points[j].longitude;

      final intersect = ((yi > lon) != (yj > lon)) &&
          (lat <
              (xj - xi) * (lon - yi) / ((yj - yi) + 1e-12) +
                  xi);
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// ポリゴン境界上の最寄り点を計算します。
  _NearestBoundary? _nearestPointOnPolygon(
    double lat,
    double lon,
    List<LatLng> points,
  ) {
    var minDistance = double.infinity;
    LatLng? closestPoint;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final candidate = _nearestPointOnSegment(
        lat,
        lon,
        a,
        b,
      );
      if (candidate.distanceM < minDistance) {
        minDistance = candidate.distanceM;
        closestPoint = candidate.point;
      }
    }

    if (!minDistance.isFinite || closestPoint == null) {
      return null;
    }
    return _NearestBoundary(distanceM: minDistance, point: closestPoint);
  }

  /// 線分上の最寄り点を計算します。
  _NearestBoundary _nearestPointOnSegment(
    double px,
    double py,
    LatLng a,
    LatLng b,
  ) {
    final apx = px - a.latitude;
    final apy = py - a.longitude;
    final abx = b.latitude - a.latitude;
    final aby = b.longitude - a.longitude;
    final abLen2 = abx * abx + aby * aby;
    final t = ((apx * abx) + (apy * aby)) / (abLen2 + 1e-12);
    final clampedT = t.clamp(0.0, 1.0);
    final closestX = a.latitude + abx * clampedT;
    final closestY = a.longitude + aby * clampedT;
    final distance = _haversine(
      px,
      py,
      closestX,
      closestY,
    );
    return _NearestBoundary(
      distanceM: distance,
      point: LatLng(closestX, closestY),
    );
  }

  /// Haversine公式を使用して2点間の距離を計算します（メートル）。
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

  /// 2点間の方位角を計算します（0-360度、北が0度）。
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
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLon);
    final bearingRad = atan2(y, x);
    final bearingDeg = _radToDeg(bearingRad);
    return (bearingDeg + 360) % 360;
  }

  double _degToRad(double deg) => deg * pi / 180;
  double _radToDeg(double rad) => rad * 180 / pi;
}

class _NearestBoundary {
  const _NearestBoundary({
    required this.distanceM,
    required this.point,
  });

  final double distanceM;
  final LatLng point;
}
