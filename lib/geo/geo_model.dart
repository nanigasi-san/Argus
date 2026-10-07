import 'package:collection/collection.dart';

import 'geojson_validator.dart';

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
    return const GeoJsonValidator().validate(raw).requireModel();
  }

  factory GeoModel.empty() => GeoModel(const []);

  final List<GeoPolygon> polygons;

  bool get hasGeometry => polygons.isNotEmpty;
}

/// Whether a position can be represented as geographic latitude/longitude.
bool isValidCoordinate(LatLng point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude.abs() <= 90 &&
    point.longitude.abs() <= 180;
