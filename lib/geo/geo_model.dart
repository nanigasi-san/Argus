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

    if (features.isEmpty) {
      throw const FormatException(
        'FeatureCollection.featuresが空です。監視する競技エリアのPolygonを'
        '1つ以上含めてください。',
      );
    }

    for (var featureIndex = 0; featureIndex < features.length; featureIndex++) {
      final feature = features[featureIndex];
      final at = 'Feature[$featureIndex]';
      if (feature is! Map) {
        throw FormatException('$at: Featureはオブジェクトである必要があります。');
      }
      final propertiesValue = feature['properties'];
      final properties =
          propertiesValue is Map ? propertiesValue : const <String, dynamic>{};
      final geometry = feature['geometry'];
      // geometry や type が想定外のものを黙って読み飛ばすと、競技エリアが
      // 1つ欠けたまま監視を開始してしまう。穴を拒否するのと同じ理由で
      // ここもエラーにする。
      if (geometry is! Map) {
        throw FormatException(
          '$at: geometryがありません。'
          'geometryを持つFeatureだけを含めてください。',
        );
      }
      final type = geometry['type'];
      final coordinates = geometry['coordinates'];

      final Iterable<dynamic> polygonCoordinates;
      if (type == 'Polygon') {
        polygonCoordinates = [coordinates];
      } else if (type == 'MultiPolygon') {
        if (coordinates is! List) {
          throw FormatException(
            '$at: MultiPolygon.coordinatesは配列である必要があります。',
          );
        }
        if (coordinates.isEmpty) {
          throw FormatException('$at: MultiPolygonにPolygonがありません。');
        }
        polygonCoordinates = coordinates;
      } else {
        throw FormatException(
          '$at: 対応していないgeometry type（${_describeValue(type)}）です。'
          'PolygonまたはMultiPolygonへ変換してください。',
        );
      }

      var polygonIndex = -1;
      for (final polygonValue in polygonCoordinates) {
        polygonIndex += 1;
        final ringAt = '$at のPolygon[$polygonIndex]';
        if (polygonValue is! List) {
          throw FormatException('$ringAt: coordinatesは配列である必要があります。');
        }
        if (polygonValue.isEmpty) {
          throw FormatException('$ringAt: 外周がありません。');
        }
        if (polygonValue.length > 1) {
          throw FormatException(
            '$ringAt: 穴（${polygonValue.length - 1}個）を含むPolygonには'
            '対応していません。穴のないPolygonへ変換してください。',
          );
        }

        final ring = polygonValue.single;
        if (ring is! List) {
          throw FormatException('$ringAt: 外周は配列である必要があります。');
        }
        if (polygons.length >= limits.maxPolygons) {
          throw FormatException(
            'Polygon数が上限（${limits.maxPolygons}個）を超えています。',
          );
        }
        final points = _parseAndValidateRing(ring, limits, ringAt);
        totalVertices += points.length;
        if (totalVertices > limits.maxTotalVertices) {
          throw FormatException(
            'GeoJSONの総頂点数が上限（${limits.maxTotalVertices}点）を超えています。',
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

/// 値の型と内容をエラーメッセージ用に短く表します。
String _describeValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return '"$value"';
  }
  return '${value.runtimeType}';
}

List<LatLng> _parseAndValidateRing(
  List<dynamic> ring,
  GeoJsonLimits limits,
  String at,
) {
  if (ring.length < 4) {
    throw FormatException(
      '$at: 外周には始点と終点を含む4点以上が必要です（${ring.length}点しかありません）。'
      '始点と同じ座標を終点に追加してリングを閉じてください。',
    );
  }
  if (ring.length > limits.maxVerticesPerPolygon) {
    throw FormatException(
      '$at: 頂点数が上限（${limits.maxVerticesPerPolygon}点）を超えています'
      '（${ring.length}点）。',
    );
  }

  final points = <LatLng>[];
  for (var index = 0; index < ring.length; index++) {
    final coordinate = ring[index];
    final vertexAt = '$at の頂点[$index]';
    if (coordinate is! List) {
      throw FormatException(
        '$vertexAt: 座標は[経度, 緯度]の配列である必要があります'
        '（${_describeValue(coordinate)}）。',
      );
    }
    if (coordinate.length < 2) {
      throw FormatException(
        '$vertexAt: 座標には経度と緯度が必要です（${coordinate.length}要素）。',
      );
    }
    final longitudeValue = coordinate[0];
    final latitudeValue = coordinate[1];
    if (longitudeValue is! num || latitudeValue is! num) {
      throw FormatException(
        '$vertexAt: 緯度・経度は数値である必要があります'
        '（経度=${_describeValue(longitudeValue)}, '
        '緯度=${_describeValue(latitudeValue)}）。',
      );
    }
    final longitude = longitudeValue.toDouble();
    final latitude = latitudeValue.toDouble();
    if (!longitude.isFinite || !latitude.isFinite) {
      throw FormatException(
        '$vertexAt: 緯度・経度は有限の数値である必要があります'
        '（経度=$longitude, 緯度=$latitude）。',
      );
    }
    if (longitude < -180 || longitude > 180) {
      throw FormatException(
        '$vertexAt: 経度が範囲外です（$longitude）。'
        'GeoJSONの座標順は[経度, 緯度]です。緯度と入れ替わっていないか確認してください。',
      );
    }
    if (latitude < -90 || latitude > 90) {
      throw FormatException(
        '$vertexAt: 緯度が範囲外です（$latitude）。'
        'GeoJSONの座標順は[経度, 緯度]です。経度と入れ替わっていないか確認してください。',
      );
    }
    points.add(LatLng(latitude, longitude));
  }

  final first = points.first;
  final last = points.last;
  if (first.latitude != last.latitude || first.longitude != last.longitude) {
    throw FormatException(
      '$at: 外周の始点と終点が一致していません'
      '（始点=${first.latitude}, ${first.longitude} / '
      '終点=${last.latitude}, ${last.longitude}）。'
      '始点と同じ座標を終点に追加してリングを閉じてください。',
    );
  }

  // 連続する重複頂点はGISの書き出しで普通に混ざる。自己交差と同じ
  // メッセージで弾くと原因に辿り着けないため、専用のエラーにする。
  for (var index = 0; index < points.length - 1; index++) {
    final current = points[index];
    final next = points[index + 1];
    if (current.latitude == next.latitude &&
        current.longitude == next.longitude) {
      throw FormatException(
        '$at: 頂点[$index]と頂点[${index + 1}]が同じ座標です'
        '（${current.latitude}, ${current.longitude}）。'
        '連続する重複頂点を削除してください。',
      );
    }
  }

  final distinct = <(double, double)>{
    for (final point in points.take(points.length - 1))
      (point.latitude, point.longitude),
  };
  if (distinct.length < 3) {
    throw FormatException(
      '$at: 外周には3つ以上の異なる頂点が必要です'
      '（${distinct.length}点しかありません）。',
    );
  }

  final longitudes = points.map((point) => point.longitude);
  final longitudeSpan = longitudes.max - longitudes.min;
  if (longitudeSpan > 180) {
    throw FormatException(
      '$at: 日付変更線をまたぐPolygonには対応していません'
      '（経度の幅が${longitudeSpan.toStringAsFixed(1)}度）。'
      '日付変更線をまたがない座標系へ変換してください。',
    );
  }

  // シューレース公式は原点を始点へ寄せてから計算する。生の緯度経度のままだと
  // 1項が最大1.6e4程度になり、5000頂点の合計では丸め誤差が1e-8前後まで
  // 膨らむため、閾値1e-12が浮動小数点ノイズに埋もれて機能しない。
  var twiceArea = 0.0;
  for (var index = 0; index < points.length - 1; index++) {
    final current = points[index];
    final next = points[index + 1];
    final currentLon = current.longitude - first.longitude;
    final currentLat = current.latitude - first.latitude;
    final nextLon = next.longitude - first.longitude;
    final nextLat = next.latitude - first.latitude;
    twiceArea += currentLon * nextLat;
    twiceArea -= nextLon * currentLat;
  }
  if (twiceArea.abs() <= 1e-12) {
    throw FormatException(
      '$at: 面積が0に近いPolygonは使用できません。'
      '頂点が一直線に並んでいないか確認してください。',
    );
  }

  if (_hasSelfIntersection(points)) {
    throw FormatException(
      '$at: 自己交差するPolygonは使用できません。'
      '辺が交差しない外周に修正してください。',
    );
  }

  return List<LatLng>.unmodifiable(points);
}

// 呼び出し前に連続する重複頂点は専用のエラーで弾いてあるため、
// ここでは長さ0の辺を考慮しない。
bool _hasSelfIntersection(List<LatLng> points) {
  final segmentCount = points.length - 1;

  // 隣り合う辺は共通頂点で交わるのが正常だが、同じ直線上を
  // 折り返す辺は重なりを持つため自己交差として扱う。
  for (var index = 0; index < segmentCount; index++) {
    final previous = points[(index - 1 + segmentCount) % segmentCount];
    final vertex = points[index];
    final next = points[(index + 1) % segmentCount];
    if (!_isZero(_orientation(previous, vertex, next))) {
      continue;
    }
    final previousRayLon = previous.longitude - vertex.longitude;
    final previousRayLat = previous.latitude - vertex.latitude;
    final nextRayLon = next.longitude - vertex.longitude;
    final nextRayLat = next.latitude - vertex.latitude;
    final rayDotProduct =
        previousRayLon * nextRayLon + previousRayLat * nextRayLat;
    if (rayDotProduct > 1e-12) {
      return true;
    }
  }

  final segments = <_RingSegment>[
    for (var index = 0; index < segmentCount; index++)
      _RingSegment(index, points[index], points[index + 1]),
  ]..sort((left, right) => left.minLon.compareTo(right.minLon));

  // 経度の範囲が重なる辺だけを比較する。単純な図形では、
  // 全5000頂点の総当たり比較を避けられる。
  for (var leftIndex = 0; leftIndex < segments.length; leftIndex++) {
    final left = segments[leftIndex];
    for (var rightIndex = leftIndex + 1;
        rightIndex < segments.length;
        rightIndex++) {
      final right = segments[rightIndex];
      if (right.minLon > left.maxLon) {
        break;
      }
      if (_areAdjacentSegments(left.index, right.index, segmentCount) ||
          right.minLat > left.maxLat ||
          right.maxLat < left.minLat) {
        continue;
      }
      if (_segmentsIntersect(left.start, left.end, right.start, right.end)) {
        return true;
      }
    }
  }
  return false;
}

bool _areAdjacentSegments(int left, int right, int segmentCount) {
  final difference = (left - right).abs();
  return difference == 1 || difference == segmentCount - 1;
}

bool _segmentsIntersect(LatLng a, LatLng b, LatLng c, LatLng d) {
  final abC = _orientation(a, b, c);
  final abD = _orientation(a, b, d);
  final cdA = _orientation(c, d, a);
  final cdB = _orientation(c, d, b);

  if (_oppositeSigns(abC, abD) && _oppositeSigns(cdA, cdB)) {
    return true;
  }
  final collinearTouches = <bool>[
    _isZero(abC) && _isOnSegment(a, b, c),
    _isZero(abD) && _isOnSegment(a, b, d),
    _isZero(cdA) && _isOnSegment(c, d, a),
    _isZero(cdB) && _isOnSegment(c, d, b),
  ];
  return collinearTouches.any((touches) => touches);
}

double _orientation(LatLng a, LatLng b, LatLng c) {
  return (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);
}

bool _oppositeSigns(double left, double right) =>
    (left > 1e-12 && right < -1e-12) || (left < -1e-12 && right > 1e-12);

bool _isZero(double value) => value.abs() <= 1e-12;

bool _isOnSegment(LatLng start, LatLng end, LatLng point) {
  const epsilon = 1e-12;
  return point.longitude >=
          (start.longitude < end.longitude ? start.longitude : end.longitude) -
              epsilon &&
      point.longitude <=
          (start.longitude > end.longitude ? start.longitude : end.longitude) +
              epsilon &&
      point.latitude >=
          (start.latitude < end.latitude ? start.latitude : end.latitude) -
              epsilon &&
      point.latitude <=
          (start.latitude > end.latitude ? start.latitude : end.latitude) +
              epsilon;
}

class _RingSegment {
  _RingSegment(this.index, this.start, this.end)
      : minLat = start.latitude < end.latitude ? start.latitude : end.latitude,
        maxLat = start.latitude > end.latitude ? start.latitude : end.latitude,
        minLon =
            start.longitude < end.longitude ? start.longitude : end.longitude,
        maxLon =
            start.longitude > end.longitude ? start.longitude : end.longitude;

  final int index;
  final LatLng start;
  final LatLng end;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
}
