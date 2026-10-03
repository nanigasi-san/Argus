import 'dart:convert';
import 'dart:math' as math;

import 'geo_model.dart';

enum GeoJsonIssueSeverity { error, warning }

/// A machine-readable finding. User-facing text belongs in the presentation layer.
class GeoJsonValidationIssue {
  const GeoJsonValidationIssue(
    this.code, {
    this.severity = GeoJsonIssueSeverity.error,
    this.featureIndex,
    this.polygonIndex,
    this.ringIndex,
    this.vertexIndex,
    this.coordinateIndex,
    this.edgeIndex,
    this.otherEdgeIndex,
    this.actual,
    this.limit,
  });

  final String code;
  final GeoJsonIssueSeverity severity;
  final int? featureIndex;
  final int? polygonIndex;
  final int? ringIndex;
  final int? vertexIndex;

  /// The position component: 0 for longitude and 1 for latitude.
  final int? coordinateIndex;
  final int? edgeIndex;
  final int? otherEdgeIndex;
  final num? actual;
  final num? limit;
}

class GeoJsonValidationResult {
  GeoJsonValidationResult({
    required this.model,
    required List<GeoJsonValidationIssue> issues,
    required this.featureCount,
    required this.polygonCount,
    required this.hasMultiPolygon,
    required this.singleFeaturePolygon,
    required this.areaSquareMeters,
  }) : issues = List.unmodifiable(issues);

  final GeoModel? model;
  final List<GeoJsonValidationIssue> issues;
  final int featureCount;
  final int polygonCount;
  final bool hasMultiPolygon;
  final bool singleFeaturePolygon;
  final double areaSquareMeters;

  bool get validForPhone => model != null && errors.isEmpty;
  List<GeoJsonValidationIssue> get errors => issues
      .where((issue) => issue.severity == GeoJsonIssueSeverity.error)
      .toList(growable: false);
  List<GeoJsonValidationIssue> get warnings => issues
      .where((issue) => issue.severity == GeoJsonIssueSeverity.warning)
      .toList(growable: false);

  GeoModel requireModel() {
    if (!validForPhone) {
      throw FormatException(errors.first.code);
    }
    return model!;
  }
}

/// The sole phone geometry validator for files, QR creation and QR restoration.
class GeoJsonValidator {
  const GeoJsonValidator();

  static const double shortEdgeMeters = 1;
  static const double longEdgeMeters = 50000;
  static const double tinyAreaSquareMeters = 100;
  static const int maxVertices = 1000;

  GeoJsonValidationResult validate(String raw) {
    final issues = <GeoJsonValidationIssue>[];
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return _result(issues: [const GeoJsonValidationIssue('E_INVALID_JSON')]);
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['type'] != 'FeatureCollection' ||
        decoded['features'] is! List) {
      return _result(issues: [
        const GeoJsonValidationIssue('E_INVALID_FEATURE_COLLECTION')
      ]);
    }

    final features = decoded['features'] as List;
    if (features.isEmpty) {
      return _result(issues: [const GeoJsonValidationIssue('E_NO_POLYGON')]);
    }
    if (features.length != 1) {
      return _result(issues: [
        const GeoJsonValidationIssue('E_SINGLE_FEATURE_POLYGON_REQUIRED')
      ]);
    }
    final polygons = <GeoPolygon>[];
    var polygonCount = 0;
    var areaSquareMeters = 0.0;
    var singleFeaturePolygon = false;
    var vertexCount = 0;

    for (var featureIndex = 0; featureIndex < features.length; featureIndex++) {
      final feature = features[featureIndex];
      if (feature is! Map<String, dynamic> || feature['type'] != 'Feature') {
        issues.add(GeoJsonValidationIssue('E_INVALID_FEATURE',
            featureIndex: featureIndex));
        continue;
      }
      final geometry = feature['geometry'];
      if (geometry == null) continue;
      if (geometry is! Map<String, dynamic>) {
        issues.add(GeoJsonValidationIssue('E_INVALID_GEOMETRY',
            featureIndex: featureIndex));
        continue;
      }
      final type = geometry['type'];
      if (type != 'Polygon') {
        issues.add(GeoJsonValidationIssue('E_SINGLE_FEATURE_POLYGON_REQUIRED',
            featureIndex: featureIndex));
        continue;
      }
      final coordinates = geometry['coordinates'];
      if (coordinates is! List) {
        issues.add(GeoJsonValidationIssue('E_INVALID_GEOMETRY',
            featureIndex: featureIndex));
        continue;
      }
      final polygonArrays = [coordinates];
      if (polygonArrays.isEmpty) {
        issues.add(GeoJsonValidationIssue('E_MISSING_RING',
            featureIndex: featureIndex));
      }
      for (final polygonArray in polygonArrays) {
        final polygonIndex = polygonCount++;
        if (polygonArray.isEmpty) {
          issues.add(GeoJsonValidationIssue('E_MISSING_RING',
              featureIndex: featureIndex, polygonIndex: polygonIndex));
          continue;
        }
        // A second ring is a hole even when it is empty or malformed.
        if (polygonArray.length != 1) {
          issues.add(GeoJsonValidationIssue('E_HOLES_UNSUPPORTED',
              featureIndex: featureIndex,
              polygonIndex: polygonIndex,
              ringIndex: 1));
        }
        final ring = polygonArray.first;
        if (ring is! List) {
          issues.add(GeoJsonValidationIssue('E_INVALID_COORDINATE',
              featureIndex: featureIndex, polygonIndex: polygonIndex));
          continue;
        }
        if (ring.length < 4) {
          issues.add(GeoJsonValidationIssue('E_TOO_FEW_POINTS',
              featureIndex: featureIndex, polygonIndex: polygonIndex));
          continue;
        }
        // Count exterior vertices before the
        // quadratic intersection check. The closing point is not a vertex.
        vertexCount += ring.length - 1;
        if (vertexCount > maxVertices) {
          return _result(issues: [
            GeoJsonValidationIssue('E_PHONE_TOO_MANY_VERTICES',
                actual: vertexCount, limit: maxVertices)
          ]);
        }
        final points = <LatLng>[];
        GeoJsonValidationIssue? coordinateIssue;
        for (var vertexIndex = 0; vertexIndex < ring.length; vertexIndex++) {
          final position = ring[vertexIndex];
          if (position is! List || position.length < 2) {
            coordinateIssue = GeoJsonValidationIssue('E_INVALID_COORDINATE',
                featureIndex: featureIndex,
                polygonIndex: polygonIndex,
                ringIndex: 0,
                vertexIndex: vertexIndex);
            break;
          }
          for (var coordinateIndex = 0;
              coordinateIndex < 2;
              coordinateIndex++) {
            final value = position[coordinateIndex];
            final limit = coordinateIndex == 0 ? 180 : 90;
            if (value is! num ||
                !value.isFinite ||
                value < -limit ||
                value > limit) {
              coordinateIssue = GeoJsonValidationIssue('E_INVALID_COORDINATE',
                  featureIndex: featureIndex,
                  polygonIndex: polygonIndex,
                  ringIndex: 0,
                  vertexIndex: vertexIndex,
                  coordinateIndex: coordinateIndex,
                  actual: value is num ? value : null,
                  limit: value is num && value.isFinite
                      ? (value < 0 ? -limit : limit)
                      : null);
              break;
            }
          }
          if (coordinateIssue != null) {
            break;
          }
          points.add(LatLng((position[1] as num).toDouble(),
              (position[0] as num).toDouble()));
        }
        if (coordinateIssue != null) {
          issues.add(coordinateIssue);
          continue;
        }
        if (!_samePoint(points.first, points.last)) {
          issues.add(GeoJsonValidationIssue('E_POLYGON_NOT_CLOSED',
              featureIndex: featureIndex, polygonIndex: polygonIndex));
          continue;
        }
        final vertices = points.sublist(0, points.length - 1);
        if (vertices.toSetByCoordinates().length < 3) {
          issues.add(GeoJsonValidationIssue('E_TOO_FEW_POINTS',
              featureIndex: featureIndex, polygonIndex: polygonIndex));
          continue;
        }
        var invalidRing = false;
        for (var edge = 0; edge < vertices.length; edge++) {
          final a = vertices[edge];
          final b = vertices[(edge + 1) % vertices.length];
          if (_samePoint(a, b)) {
            issues.add(GeoJsonValidationIssue('E_DUPLICATE_CONSECUTIVE_POINT',
                featureIndex: featureIndex,
                polygonIndex: polygonIndex,
                ringIndex: 0,
                edgeIndex: edge));
            invalidRing = true;
            break;
          }
          if ((a.longitude - b.longitude).abs() > 180) {
            issues.add(GeoJsonValidationIssue('E_ANTIMERIDIAN_UNSUPPORTED',
                featureIndex: featureIndex,
                polygonIndex: polygonIndex,
                edgeIndex: edge));
            invalidRing = true;
            break;
          }
          final meters = _distanceMeters(a, b);
          if (meters < shortEdgeMeters || meters > longEdgeMeters) {
            issues.add(GeoJsonValidationIssue(
              meters < shortEdgeMeters ? 'W_SHORT_EDGE' : 'W_LONG_EDGE',
              severity: GeoJsonIssueSeverity.warning,
              featureIndex: featureIndex,
              polygonIndex: polygonIndex,
              edgeIndex: edge,
              actual: meters,
              limit:
                  meters < shortEdgeMeters ? shortEdgeMeters : longEdgeMeters,
            ));
          }
        }
        if (invalidRing) continue;
        final crossing = firstPolygonSelfIntersection(vertices);
        if (crossing != null) {
          issues.add(GeoJsonValidationIssue('E_SELF_INTERSECTION',
              featureIndex: featureIndex,
              polygonIndex: polygonIndex,
              ringIndex: 0,
              edgeIndex: crossing.$1,
              otherEdgeIndex: crossing.$2));
        }
        final area = _areaSquareMeters(vertices);
        if (!area.isFinite || area <= 0) {
          issues.add(GeoJsonValidationIssue('E_ZERO_AREA',
              featureIndex: featureIndex, polygonIndex: polygonIndex));
        }
        if (crossing != null || !area.isFinite || area <= 0) {
          continue;
        }
        areaSquareMeters += area;
        if (area < tinyAreaSquareMeters) {
          issues.add(GeoJsonValidationIssue('W_TINY_AREA',
              severity: GeoJsonIssueSeverity.warning,
              featureIndex: featureIndex,
              polygonIndex: polygonIndex,
              actual: area,
              limit: tinyAreaSquareMeters));
        }
        final properties = feature['properties'];
        if (properties != null && properties is! Map<String, dynamic>) {
          issues.add(GeoJsonValidationIssue('E_INVALID_FEATURE',
              featureIndex: featureIndex));
          continue;
        }
        final propertyMap = properties as Map<String, dynamic>? ?? const {};
        final name = propertyMap['name'];
        final version = propertyMap['version'];
        if ((name != null && name is! String) ||
            (version != null && (version is! num || !version.isFinite))) {
          issues.add(GeoJsonValidationIssue('E_INVALID_FEATURE',
              featureIndex: featureIndex));
          continue;
        }
        polygons.add(GeoPolygon(
          points: points,
          name: name as String?,
          version: (version as num?)?.toInt(),
        ));
        if (features.length == 1 && type == 'Polygon') {
          singleFeaturePolygon = true;
        }
      }
    }
    if (polygonCount == 0) {
      issues.add(const GeoJsonValidationIssue('E_NO_POLYGON'));
    }
    final valid = !issues.any((i) => i.severity == GeoJsonIssueSeverity.error);
    return GeoJsonValidationResult(
      model: valid ? GeoModel(polygons) : null,
      issues: issues,
      featureCount: features.length,
      polygonCount: polygonCount,
      hasMultiPolygon: false,
      singleFeaturePolygon: singleFeaturePolygon,
      areaSquareMeters: areaSquareMeters,
    );
  }
}

GeoJsonValidationResult _result(
        {required List<GeoJsonValidationIssue> issues}) =>
    GeoJsonValidationResult(
      model: null,
      issues: issues,
      featureCount: 0,
      polygonCount: 0,
      hasMultiPolygon: false,
      singleFeaturePolygon: false,
      areaSquareMeters: 0,
    );

extension on List<LatLng> {
  Set<(double, double)> toSetByCoordinates() =>
      map((point) => (point.latitude, point.longitude)).toSet();
}

bool _samePoint(LatLng a, LatLng b) =>
    a.latitude == b.latitude && a.longitude == b.longitude;

double _distanceMeters(LatLng a, LatLng b) {
  const radius = 6371000.0;
  final latA = a.latitude * math.pi / 180;
  final latB = b.latitude * math.pi / 180;
  final dLat = latB - latA;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(latA) * math.cos(latB) * math.pow(math.sin(dLon / 2), 2);
  return 2 * radius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
}

double _areaSquareMeters(List<LatLng> points) {
  if (points.skip(2).every((p) => _orientation(points[0], points[1], p) == 0)) {
    return 0;
  }
  final meanLat =
      points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
  final lonScale = 111320.0 * math.cos(meanLat * math.pi / 180);
  const latScale = 110540.0;
  final originLon = points.first.longitude;
  final originLat = points.first.latitude;
  var twiceArea = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    final ax = (a.longitude - originLon) * lonScale;
    final ay = (a.latitude - originLat) * latScale;
    final bx = (b.longitude - originLon) * lonScale;
    final by = (b.latitude - originLat) * latScale;
    twiceArea += ax * by - bx * ay;
  }
  return twiceArea.abs() / 2;
}

/// Returns the first pair of crossing or overlapping edges, if any.
(int, int)? firstPolygonSelfIntersection(List<LatLng> points) {
  final count = points.length;
  for (var i = 0; i < count; i++) {
    final a = points[i];
    final b = points[(i + 1) % count];
    for (var j = i + 1; j < count; j++) {
      final c = points[j];
      final d = points[(j + 1) % count];
      final adjacent = j == i + 1 || (i == 0 && j == count - 1);
      if (adjacent) {
        // Adjacent collinear edges may retrace one another.
        if (_adjacentBacktrack(a, b, c, d)) return (i, j);
        continue;
      }
      if (_segmentsIntersect(a, b, c, d)) return (i, j);
    }
  }
  return null;
}

bool _adjacentBacktrack(LatLng a, LatLng b, LatLng c, LatLng d) {
  final shared = _samePoint(b, c) ? b : (_samePoint(a, d) ? a : null);
  if (shared == null) return false;
  final first = _samePoint(shared, b) ? a : b;
  final second = _samePoint(shared, c) ? d : c;
  if (_orientation(first, shared, second) != 0) return false;
  final ux = first.longitude - shared.longitude;
  final uy = first.latitude - shared.latitude;
  final vx = second.longitude - shared.longitude;
  final vy = second.latitude - shared.latitude;
  return ux * vx + uy * vy > 0;
}

bool _segmentsIntersect(LatLng a, LatLng b, LatLng c, LatLng d) {
  final abC = _orientation(a, b, c);
  final abD = _orientation(a, b, d);
  final cdA = _orientation(c, d, a);
  final cdB = _orientation(c, d, b);
  if (abC == 0 && _onSegment(a, b, c)) return true;
  if (abD == 0 && _onSegment(a, b, d)) return true;
  if (cdA == 0 && _onSegment(c, d, a)) return true;
  if (cdB == 0 && _onSegment(c, d, b)) return true;
  return abC * abD < 0 && cdA * cdB < 0;
}

/// Account for rounding both geographic coordinates and the determinant.
/// The bound scales with the inputs; it does not round coordinates or apply
/// a fixed geographic epsilon that could erase small, valid polygons.
int _orientation(LatLng a, LatLng b, LatLng c) {
  const epsilon = 2.220446049250313e-16;
  final abX = b.longitude - a.longitude;
  final abY = b.latitude - a.latitude;
  final acX = c.longitude - a.longitude;
  final acY = c.latitude - a.latitude;
  final left = abX * acY;
  final right = abY * acX;
  final scale = math.max(
    math.max(a.longitude.abs(), a.latitude.abs()),
    math.max(math.max(b.longitude.abs(), b.latitude.abs()),
        math.max(c.longitude.abs(), c.latitude.abs())),
  );
  final error = 4 *
      epsilon *
      (scale * (abX.abs() + abY.abs() + acX.abs() + acY.abs()) +
          left.abs() +
          right.abs());
  final cross = left - right;
  if (cross.abs() <= error) return 0;
  return cross < 0 ? -1 : 1;
}

bool _onSegment(LatLng a, LatLng b, LatLng p) =>
    p.longitude >= math.min(a.longitude, b.longitude) &&
    p.longitude <= math.max(a.longitude, b.longitude) &&
    p.latitude >= math.min(a.latitude, b.latitude) &&
    p.latitude <= math.max(a.latitude, b.latitude);
