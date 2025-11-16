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
  GeoModel(this.polygons);

  factory GeoModel.fromGeoJson(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final features = decoded['features'] as List<dynamic>? ?? [];
    final polygons = <GeoPolygon>[];

    for (final feature in features) {
      final featureMap = feature as Map<String, dynamic>;
      final properties =
          (featureMap['properties'] as Map<String, dynamic>? ?? {});
      final geometry = featureMap['geometry'] as Map<String, dynamic>? ?? {};
      final type = geometry['type'] as String? ?? '';
      final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];

      final Iterable<List<dynamic>> rings;
      if (type == 'Polygon') {
        rings = coordinates.isEmpty
            ? const Iterable<List<dynamic>>.empty()
            : [coordinates.first as List<dynamic>];
      } else if (type == 'MultiPolygon') {
        rings = coordinates
            .cast<List<dynamic>>()
            .where((poly) => poly.isNotEmpty)
            .map((poly) => poly.first as List<dynamic>);
      } else {
        continue;
      }

      for (final ring in rings) {
        final pairs = ring.cast<List<dynamic>>();
        if (pairs.length < 3) {
          continue;
        }
        final points = pairs
            .map(
              (pair) => LatLng(
                (pair[1] as num).toDouble(),
                (pair[0] as num).toDouble(),
              ),
            )
            .toList(growable: false);
        polygons.add(
          GeoPolygon(
            points: points,
            name: properties['name'] as String?,
            version: (properties['version'] as num?)?.toInt(),
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
