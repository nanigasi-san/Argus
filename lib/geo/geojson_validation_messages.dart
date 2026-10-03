import 'geojson_validator.dart';

/// Presentation-only Japanese descriptions for stable validation codes.
class GeoJsonValidationMessages {
  const GeoJsonValidationMessages._();

  static String describe(GeoJsonValidationIssue issue) {
    final location = _location(issue);
    final reason = switch (issue.code) {
      'E_INVALID_JSON' => 'JSONとして読み取れません。',
      'E_INVALID_FEATURE_COLLECTION' =>
        'GeoJSONはfeatures配列を持つFeatureCollectionにしてください。',
      'E_INVALID_FEATURE' => 'Featureの形式またはpropertiesが不正です。',
      'E_INVALID_GEOMETRY' => 'Geometryまたはcoordinatesの形式が不正です。',
      'E_UNSUPPORTED_GEOMETRY' => 'このQR形式で扱えるのは単一Featureの単一Polygonだけです。',
      'E_SINGLE_FEATURE_POLYGON_REQUIRED' =>
        'GeoJSONは1つのFeatureに1つのPolygonを持つ形式にしてください。複数の範囲やMultiPolygonには対応していません。',
      'E_NO_POLYGON' => 'GeoJSONに監視可能なPolygonがありません。',
      'E_MISSING_RING' => 'Polygonの外周ringがありません。',
      'E_HOLES_UNSUPPORTED' => '穴のあるPolygonには対応していません。内側ringを取り除いてください。',
      'E_TOO_FEW_POINTS' => '外周ringには閉路の終点を除いて異なる3頂点以上が必要です。',
      'E_PHONE_TOO_MANY_VERTICES' =>
        'GeoJSON全体の頂点数が${_number(issue.actual)}点です。上限${_number(issue.limit)}点以内に減らしてください（閉路の終点は除きます）。',
      'E_INVALID_COORDINATE' => _invalidCoordinate(issue),
      'E_POLYGON_NOT_CLOSED' => '外周ringの末尾を先頭と同じ座標にして閉じてください。',
      'E_DUPLICATE_CONSECUTIVE_POINT' => '連続する同じ座標を取り除いてください。',
      'E_SELF_INTERSECTION' => 'Polygonの辺が自己交差または接触しています。交差付近を修正してください。',
      'E_ZERO_AREA' => 'Polygonの面積が0です。頂点の配置を修正してください。',
      'E_ANTIMERIDIAN_UNSUPPORTED' => '日付変更線をまたぐ辺には対応していません。Polygonを分割してください。',
      'W_SHORT_EDGE' =>
        '辺の長さが${_number(issue.actual)}mで、${_number(issue.limit)}m未満です。',
      'W_LONG_EDGE' =>
        '辺の長さが${_number(issue.actual)}mで、${_number(issue.limit)}mを超えています。',
      'W_TINY_AREA' =>
        '面積が${_number(issue.actual)}m²で、${_number(issue.limit)}m²未満です。',
      'E_GARMIN_SINGLE_POLYGON' => 'Garminへ送れるのは単一Polygonのみです。',
      'E_TOO_MANY_VERTICES' =>
        '頂点数が${_number(issue.actual)}点です。Garmin上限は${_number(issue.limit)}点です。',
      'E_LOCAL_COORD_OVERFLOW' =>
        'ローカルXY値${_number(issue.actual)}がGarminのint16境界${_number(issue.limit)}を超えています。',
      'E_PAYLOAD_TOO_LARGE' =>
        'Garmin用データが${_number(issue.actual)}バイトで、上限${_number(issue.limit)}バイトを超えています。',
      'E_GARMIN_QUANTIZED_GEOMETRY' =>
        'Garmin用の1m座標に丸めるとPolygonが退化します。形状を修正してください。',
      _ => issue.code,
    };
    return '$location$reason';
  }

  static String _invalidCoordinate(GeoJsonValidationIssue issue) {
    final axis = switch (issue.coordinateIndex) {
      0 => '経度',
      1 => '緯度',
      _ => null,
    };
    if (axis != null && issue.actual != null && issue.limit != null) {
      final comparison = issue.limit! < 0 ? '以上' : '以下';
      return '$axisが${issue.actual}°です。'
          '${_number(issue.limit)}°$comparisonにしてください。';
    }
    if (axis != null) {
      return '$axisは有限の数値にしてください。';
    }
    return '座標は有限な[経度, 緯度]とし、経度±180・緯度±90以内にしてください。';
  }

  static String _location(GeoJsonValidationIssue issue) {
    final parts = <String>[];
    if (issue.featureIndex != null) {
      parts.add('Feature ${issue.featureIndex! + 1}');
    }
    if (issue.polygonIndex != null) {
      parts.add('Polygon ${issue.polygonIndex! + 1}');
    }
    if (issue.ringIndex != null) {
      parts.add('ring ${issue.ringIndex! + 1}');
    }
    if (issue.vertexIndex != null) {
      parts.add('頂点 ${issue.vertexIndex! + 1}');
    }
    if (issue.edgeIndex != null) {
      parts.add('辺 ${issue.edgeIndex! + 1}');
    }
    if (issue.otherEdgeIndex != null) {
      parts.add('辺 ${issue.otherEdgeIndex! + 1}');
    }
    return parts.isEmpty ? '' : '${parts.join(' / ')}: ';
  }

  static String _number(num? value) {
    if (value == null) {
      return '?';
    }
    if (value is int || value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }
}
