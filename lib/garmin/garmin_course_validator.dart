import 'dart:convert';
import 'dart:math' as math;

import '../geo/geo_model.dart';
import '../geo/geojson_validator.dart';

class GarminLocalPoint {
  const GarminLocalPoint(this.x, this.y);

  final int x;
  final int y;
}

/// Numeric data prepared before any AGW1 serialization takes place.
final class GarminPreparedCourse {
  GarminPreparedCourse._({
    required this.originLat,
    required this.originLon,
    required List<GarminLocalPoint> points,
    required this.dataBytes,
  }) : points = List.unmodifiable(points);

  final double originLat;
  final double originLon;
  final List<GarminLocalPoint> points;
  final int dataBytes;
  int get vertexCount => points.length;
}

class GarminCourseValidationResult {
  GarminCourseValidationResult(
      {required this.prepared, required List<GeoJsonValidationIssue> issues})
      : issues = List.unmodifiable(issues);

  final GarminPreparedCourse? prepared;
  final List<GeoJsonValidationIssue> issues;
  bool get validForGarmin => prepared != null && issues.isEmpty;
}

/// Checks source geometry and projected integers before AGW1 is constructed.
class GarminCourseValidator {
  const GarminCourseValidator();

  static const int maxVertices = 100;
  static const int maxDataBytes = 2048;

  GarminCourseValidationResult validate(GeoJsonValidationResult source) {
    if (!source.validForPhone) {
      return GarminCourseValidationResult(
          prepared: null, issues: source.errors);
    }
    if (source.polygonCount != 1 || source.hasMultiPolygon) {
      return GarminCourseValidationResult(
          prepared: null,
          issues: const [GeoJsonValidationIssue('E_GARMIN_SINGLE_POLYGON')]);
    }
    final polygon = source.model!.polygons.single;
    final vertices = polygon.points.sublist(0, polygon.points.length - 1);
    return _validateVertices(vertices);
  }

  /// Compatibility entry point for callers that construct GeoModel in memory.
  /// Production file and QR paths use [validate] so original ring types survive.
  GarminCourseValidationResult validateModel(GeoModel model) {
    try {
      final raw = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          for (final polygon in model.polygons)
            {
              'type': 'Feature',
              'properties': <String, Object>{},
              'geometry': {
                'type': 'Polygon',
                'coordinates': [
                  [
                    for (final point in polygon.points)
                      [point.longitude, point.latitude]
                  ]
                ],
              }
            }
        ],
      });
      return validate(const GeoJsonValidator().validate(raw));
    } catch (_) {
      return GarminCourseValidationResult(
          prepared: null,
          issues: const [GeoJsonValidationIssue('E_INVALID_COORDINATE')]);
    }
  }

  GarminCourseValidationResult _validateVertices(List<LatLng> vertices) {
    if (vertices.length < 3) {
      return GarminCourseValidationResult(prepared: null, issues: [
        GeoJsonValidationIssue('E_TOO_FEW_POINTS',
            actual: vertices.length, limit: 3)
      ]);
    }
    if (vertices.length > maxVertices) {
      return GarminCourseValidationResult(prepared: null, issues: [
        GeoJsonValidationIssue('E_TOO_MANY_VERTICES',
            actual: vertices.length, limit: maxVertices)
      ]);
    }
    final originLat = vertices.map((p) => p.latitude).reduce((a, b) => a + b) /
        vertices.length;
    final originLon = vertices.map((p) => p.longitude).reduce((a, b) => a + b) /
        vertices.length;
    final metersPerLon = 111320.0 * math.cos(originLat * math.pi / 180);
    final local = <GarminLocalPoint>[];
    var dataBytes = 5; // ASCII prefix AGW1|
    for (var index = 0; index < vertices.length; index++) {
      final point = vertices[index];
      final x = ((point.longitude - originLon) * metersPerLon).round();
      final y = ((point.latitude - originLat) * 110540.0).round();
      if (x < -32768 || x > 32767 || y < -32768 || y > 32767) {
        final exceeded = x < -32768 || x > 32767 ? x : y;
        return GarminCourseValidationResult(prepared: null, issues: [
          GeoJsonValidationIssue('E_LOCAL_COORD_OVERFLOW',
              vertexIndex: index,
              actual: exceeded,
              limit: exceeded < 0 ? -32768 : 32767)
        ]);
      }
      local.add(GarminLocalPoint(x, y));
      dataBytes += '$x,$y'.length;
    }
    dataBytes += local.length - 1; // semicolon separators
    if (dataBytes > maxDataBytes) {
      return GarminCourseValidationResult(prepared: null, issues: [
        GeoJsonValidationIssue('E_PAYLOAD_TOO_LARGE',
            actual: dataBytes, limit: maxDataBytes)
      ]);
    }
    final quantized = [
      for (final point in local) LatLng(point.y.toDouble(), point.x.toDouble())
    ];
    if (quantized.map((p) => (p.latitude, p.longitude)).toSet().length < 3 ||
        List.generate(local.length, (i) => i).any((i) =>
            local[i].x == local[(i + 1) % local.length].x &&
            local[i].y == local[(i + 1) % local.length].y) ||
        firstPolygonSelfIntersection(quantized) != null ||
        _signedAreaTwice(local) == 0) {
      return GarminCourseValidationResult(prepared: null, issues: const [
        GeoJsonValidationIssue('E_GARMIN_QUANTIZED_GEOMETRY')
      ]);
    }
    return GarminCourseValidationResult(
      prepared: GarminPreparedCourse._(
        originLat: originLat,
        originLon: originLon,
        points: local,
        dataBytes: dataBytes,
      ),
      issues: const [],
    );
  }
}

int _signedAreaTwice(List<GarminLocalPoint> points) {
  var area = 0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    area += a.x * b.y - b.x * a.y;
  }
  return area;
}
