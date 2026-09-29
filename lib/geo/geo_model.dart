import 'dart:convert';

import 'package:collection/collection.dart';

class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
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
  GeoModel(List<GeoPolygon> polygons)
      : polygons = List<GeoPolygon>.unmodifiable(polygons);

  factory GeoModel.fromGeoJson(String raw) {
    final decoded = _object(jsonDecode(raw), 'GeoJSON');
    final features = _list(decoded['features'] ?? [], 'features');
    final polygons = <GeoPolygon>[];

    for (final feature in features) {
      final featureMap = _object(feature, 'Feature');
      final properties = _object(
          featureMap['properties'] ?? <String, dynamic>{}, 'properties');
      final geometry =
          _object(featureMap['geometry'] ?? <String, dynamic>{}, 'geometry');
      for (final ring in _exteriorRings(geometry)) {
        if (ring.length < 3) {
          continue;
        }
        final points = ring.map(_coordinate).toList(growable: false);
        final name = properties['name'];
        final version = properties['version'];
        if ((name != null && name is! String) ||
            (version != null && (version is! num || !version.isFinite))) {
          throw const FormatException('nameは文字列、versionは有限の数値にしてください。');
        }
        polygons.add(
          GeoPolygon(
            points: points,
            name: name as String?,
            version: (version as num?)?.toInt(),
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

Map<String, dynamic> _object(dynamic value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$fieldはオブジェクトにしてください。');
  }
  return value;
}

List<dynamic> _list(dynamic value, String field) {
  if (value is! List) {
    throw FormatException('$fieldは配列にしてください。');
  }
  return value;
}

// Keep the existing exterior-ring-only interpretation for both geometry types.
Iterable<List<dynamic>> _exteriorRings(Map<String, dynamic> geometry) sync* {
  final type = geometry['type'];
  if (type != 'Polygon' && type != 'MultiPolygon') return;
  final coordinates = _list(geometry['coordinates'] ?? [], 'coordinates');
  final polygons = type == 'Polygon' ? [coordinates] : coordinates;
  for (final polygon in polygons) {
    final rings = _list(polygon, 'Polygon');
    if (rings.isNotEmpty) yield _list(rings.first, '外周リング');
  }
}

LatLng _coordinate(dynamic value) {
  final pair = _list(value, '座標');
  if (pair.length < 2 || pair[0] is! num || pair[1] is! num) {
    throw const FormatException('座標は[経度, 緯度]の数値配列にしてください。');
  }
  final point =
      LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
  if (!isValidCoordinate(point)) {
    throw const FormatException('緯度は-90〜90、経度は-180〜180の有限値にしてください。');
  }
  return point;
}

/// Whether a position can be represented as geographic latitude/longitude.
bool isValidCoordinate(LatLng point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude.abs() <= 90 &&
    point.longitude.abs() <= 180;
