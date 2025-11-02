import 'dart:math';

import 'geo_model.dart';

class PointInPolygonEvaluation {
  const PointInPolygonEvaluation({
    required this.contains,
    required this.distanceToBoundaryM,
  });

  final bool contains;
  final double distanceToBoundaryM;
}

class PointInPolygon {
  const PointInPolygon();

  PointInPolygonEvaluation evaluatePoint(
    double lat,
    double lon,
    GeoPolygon polygon,
  ) {
    final contains = _rayCast(lat, lon, polygon.points);
    final distance = _distanceToPolygon(lat, lon, polygon.points);
    return PointInPolygonEvaluation(
      contains: contains,
      distanceToBoundaryM: distance,
    );
  }

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

  double _distanceToPolygon(
    double lat,
    double lon,
    List<LatLng> points,
  ) {
    var minDistance = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final distance = _distancePointToSegment(
        lat,
        lon,
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance.isFinite ? minDistance : 0;
  }

  double _distancePointToSegment(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final apx = px - ax;
    final apy = py - ay;
    final abx = bx - ax;
    final aby = by - ay;
    final abLen2 = abx * abx + aby * aby;
    final t = ((apx * abx) + (apy * aby)) / (abLen2 + 1e-12);
    final clampedT = t.clamp(0.0, 1.0);
    final closestX = ax + abx * clampedT;
    final closestY = ay + aby * clampedT;
    return _haversine(
      px,
      py,
      closestX,
      closestY,
    );
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

  double _degToRad(double deg) => deg * pi / 180;
}
