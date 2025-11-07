import 'geo_model.dart';

/// ポリゴンの空間インデックス。
///
/// 境界ボックス（バウンディングボックス）を使用して、
/// 指定された位置に近いポリゴンを高速に検索できます。
class AreaIndex {
  AreaIndex(this._entries);

  /// ポリゴンリストから空間インデックスを構築します。
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

  /// 空のインデックスを作成します。
  factory AreaIndex.empty() => AreaIndex(const []);

  final List<_AreaEntry> _entries;

  /// 指定された位置に近いポリゴンを検索します。
  ///
  /// 境界ボックス内に含まれるポリゴンを返します。
  /// 結果は距離順ではなく、インデックス順で返されます。
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
