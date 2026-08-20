import 'dart:convert';

import 'package:collection/collection.dart';

class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class GeoJsonLimits {
  const GeoJsonLimits({
    this.maxSourceBytes = 1024 * 1024,
    this.maxPolygons = 10,
    this.maxVerticesPerPolygon = 5000,
    this.maxTotalVertices = 10000,
  })  : assert(maxSourceBytes > 0),
        assert(maxPolygons > 0),
        assert(maxVerticesPerPolygon >= 4),
        assert(maxTotalVertices >= 4);

  static const defaults = GeoJsonLimits();

  final int maxSourceBytes;
  final int maxPolygons;
  final int maxVerticesPerPolygon;
  final int maxTotalVertices;
}

class GeoPolygon {
  factory GeoPolygon({
    required List<LatLng> points,
    String? name,
    int? version,
  }) {
    final sealed = _ensureClosed(points);
    final bounds = _Bounds.fromPoints(sealed);
    return GeoPolygon._(
      points: sealed,
      name: name,
      version: version,
      minLat: bounds.minLat,
      maxLat: bounds.maxLat,
      minLon: bounds.minLon,
      maxLon: bounds.maxLon,
    );
  }

  const GeoPolygon._({
    required this.points,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    this.name,
    this.version,
  });

  final List<LatLng> points;
  final String? name;
  final int? version;

  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
}

List<LatLng> _ensureClosed(List<LatLng> points) {
  if (points.isEmpty) {
    return const [];
  }
  final first = points.first;
  final last = points.last;
  if (first.latitude == last.latitude && first.longitude == last.longitude) {
    return List<LatLng>.unmodifiable(points);
  }
  return List<LatLng>.unmodifiable(
    List<LatLng>.from(points)..add(first),
  );
}

class _Bounds {
  const _Bounds({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  factory _Bounds.fromPoints(List<LatLng> points) {
    if (points.isEmpty) {
      return const _Bounds(
        minLat: 0,
        maxLat: 0,
        minLon: 0,
        maxLon: 0,
      );
    }
    final minLat = points.map((p) => p.latitude).min;
    final maxLat = points.map((p) => p.latitude).max;
    final minLon = points.map((p) => p.longitude).min;
    final maxLon = points.map((p) => p.longitude).max;
    return _Bounds(
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
    );
  }
}

class GeoModel {
  GeoModel(this.polygons);

  factory GeoModel.fromGeoJson(
    String raw, {
    GeoJsonLimits limits = GeoJsonLimits.defaults,
  }) {
    if (utf8.encode(raw).length > limits.maxSourceBytes) {
      throw FormatException(
        'GeoJSONのサイズが上限（${limits.maxSourceBytes} bytes）を超えています。',
      );
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['type'] != 'FeatureCollection') {
      throw const FormatException(
        'GeoJSONのルートはFeatureCollectionである必要があります。',
      );
    }
    final features = decoded['features'];
    if (features is! List) {
      throw const FormatException(
        'FeatureCollection.featuresは配列である必要があります。',
      );
    }
    final polygons = <GeoPolygon>[];
    var totalVertices = 0;

    for (final feature in features) {
      if (feature is! Map) {
        throw const FormatException('Featureはオブジェクトである必要があります。');
      }
      final propertiesValue = feature['properties'];
      final properties =
          propertiesValue is Map ? propertiesValue : const <String, dynamic>{};
      final geometry = feature['geometry'];
      if (geometry is! Map) {
        continue;
      }
      final type = geometry['type'];
      final coordinates = geometry['coordinates'];

      final Iterable<dynamic> polygonCoordinates;
      if (type == 'Polygon') {
        polygonCoordinates = [coordinates];
      } else if (type == 'MultiPolygon') {
        if (coordinates is! List) {
          throw const FormatException('MultiPolygon.coordinatesは配列である必要があります。');
        }
        polygonCoordinates = coordinates;
      } else {
        continue;
      }

      for (final polygonValue in polygonCoordinates) {
        if (polygonValue is! List) {
          throw const FormatException('Polygon.coordinatesは配列である必要があります。');
        }
        if (polygonValue.isEmpty) {
          throw const FormatException('Polygonの外周がありません。');
        }
        if (polygonValue.length > 1) {
          throw const FormatException(
            '穴を含むPolygonには対応していません。穴のないPolygonへ変換してください。',
          );
        }

        final ring = polygonValue.single;
        if (ring is! List) {
          throw const FormatException('Polygonの外周は配列である必要があります。');
        }
        final points = _parseAndValidateRing(ring, limits);
        totalVertices += points.length;
        if (totalVertices > limits.maxTotalVertices) {
          throw FormatException(
            'GeoJSONの総頂点数が上限（${limits.maxTotalVertices}点）を超えています。',
          );
        }
        if (polygons.length >= limits.maxPolygons) {
          throw FormatException(
            'Polygon数が上限（${limits.maxPolygons}個）を超えています。',
          );
        }
        polygons.add(
          GeoPolygon(
            points: points,
            name: properties['name'] is String
                ? properties['name'] as String
                : null,
            version: properties['version'] is num
                ? (properties['version'] as num).toInt()
                : null,
          ),
        );
      }
    }

    return GeoModel(polygons);
  }

  factory GeoModel.empty() => GeoModel(const []);

  final List<GeoPolygon> polygons;

  bool get hasGeometry => polygons.isNotEmpty;
}

List<LatLng> _parseAndValidateRing(
  List<dynamic> ring,
  GeoJsonLimits limits,
) {
  if (ring.length < 4) {
    throw const FormatException(
      'Polygonには始点と終点を含む4点以上が必要です。',
    );
  }
  if (ring.length > limits.maxVerticesPerPolygon) {
    throw FormatException(
      '1つのPolygonの頂点数が上限（${limits.maxVerticesPerPolygon}点）を超えています。',
    );
  }

  final points = <LatLng>[];
  for (final coordinate in ring) {
    if (coordinate is! List || coordinate.length < 2) {
      throw const FormatException('座標は[経度, 緯度]の配列である必要があります。');
    }
    final longitudeValue = coordinate[0];
    final latitudeValue = coordinate[1];
    if (longitudeValue is! num || latitudeValue is! num) {
      throw const FormatException('緯度・経度は数値である必要があります。');
    }
    final longitude = longitudeValue.toDouble();
    final latitude = latitudeValue.toDouble();
    if (!longitude.isFinite || !latitude.isFinite) {
      throw const FormatException('緯度・経度は有限の数値である必要があります。');
    }
    if (longitude < -180 || longitude > 180) {
      throw FormatException('経度が範囲外です: $longitude');
    }
    if (latitude < -90 || latitude > 90) {
      throw FormatException('緯度が範囲外です: $latitude');
    }
    points.add(LatLng(latitude, longitude));
  }

  final first = points.first;
  final last = points.last;
  if (first.latitude != last.latitude || first.longitude != last.longitude) {
    throw const FormatException('Polygonの始点と終点が一致していません。');
  }

  final distinct = <(double, double)>{
    for (final point in points.take(points.length - 1))
      (point.latitude, point.longitude),
  };
  if (distinct.length < 3) {
    throw const FormatException('Polygonには3つ以上の異なる頂点が必要です。');
  }

  var twiceArea = 0.0;
  for (var index = 0; index < points.length - 1; index++) {
    final current = points[index];
    final next = points[index + 1];
    twiceArea += current.longitude * next.latitude;
    twiceArea -= next.longitude * current.latitude;
  }
  if (twiceArea.abs() <= 1e-12) {
    throw const FormatException('面積が0に近いPolygonは使用できません。');
  }

  return List<LatLng>.unmodifiable(points);
}
