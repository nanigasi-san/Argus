import 'geo_model.dart';

class AreaIndex {
  AreaIndex(this._entries);

  factory AreaIndex.build(List<GeoPolygon> polygons) {
    final entries = polygons
        .map(
          (poly) => _AreaEntry(
            polygon: poly,
            minLat: poly.minLat,
            maxLat: poly.maxLat,
            minLon: poly.minLon,
            maxLon: poly.maxLon,
          ),
        )
        .toList(growable: false);
    return AreaIndex(entries);
  }

  factory AreaIndex.empty() => AreaIndex(const []);

  final List<_AreaEntry> _entries;

  Iterable<GeoPolygon> lookup(double lat, double lon) sync* {
    for (final entry in _entries) {
      if (lat >= entry.minLat &&
          lat <= entry.maxLat &&
          lon >= entry.minLon &&
          lon <= entry.maxLon) {
        yield entry.polygon;
      }
    }
    if (_entries.isEmpty) {
      yield* const Iterable<GeoPolygon>.empty();
    }
  }
}

class _AreaEntry {
  _AreaEntry({
    required this.polygon,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  final GeoPolygon polygon;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
}
