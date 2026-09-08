import 'dart:convert';

import 'package:argus/geo/geo_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoModel validation and limits', () {
    test('rejects polygons with holes', () {
      final raw = _featureCollection([
        _polygon([
          _ring(0),
          _ring(0.2),
        ]),
      ]);

      expect(() => GeoModel.fromGeoJson(raw), throwsFormatException);
    });

    test('rejects open, zero-area, and out-of-range rings', () {
      final invalidRings = <List<List<num>>>[
        [
          [0, 0],
          [1, 0],
          [1, 1],
          [0, 1],
        ],
        [
          [0, 0],
          [1, 0],
          [2, 0],
          [0, 0],
        ],
        [
          [181, 0],
          [1, 0],
          [1, 1],
          [181, 0],
        ],
        [
          [0, 91],
          [1, 0],
          [1, 1],
          [0, 91],
        ],
      ];

      for (final ring in invalidRings) {
        final raw = _featureCollection([
          _polygon([ring]),
        ]);
        expect(() => GeoModel.fromGeoJson(raw), throwsFormatException);
      }
    });

    test('rejects a self-intersecting exterior ring', () {
      final raw = _featureCollection([
        _polygon([
          <List<num>>[
            [0, 0],
            [4, 0],
            [1, 3],
            [3, 3],
            [0, 0],
          ],
        ]),
      ]);

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('自己交差'),
          ),
        ),
      );
    });

    test('rejects adjacent edges that double back over each other', () {
      final raw = _featureCollection([
        _polygon([
          <List<num>>[
            [0, 0],
            [3, 0],
            [1, 0],
            [3, 2],
            [0, 2],
            [0, 0],
          ],
        ]),
      ]);

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('自己交差'),
          ),
        ),
      );
    });

    test('rejects a non-adjacent edge touching another edge', () {
      final raw = _featureCollection([
        _polygon([
          <List<num>>[
            [0, 0],
            [4, 0],
            [4, 4],
            [2, 0],
            [0, 4],
            [0, 0],
          ],
        ]),
      ]);

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('自己交差'),
          ),
        ),
      );
    });

    test('rejects a ring that crosses the international date line', () {
      final raw = _featureCollection([
        _polygon([
          <List<num>>[
            [179, 0],
            [-179, 0],
            [-179, 1],
            [179, 1],
            [179, 0],
          ],
        ]),
      ]);

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('日付変更線'),
          ),
        ),
      );
    });

    test('accepts a non-intersecting concave exterior ring', () {
      final raw = _featureCollection([
        _polygon([
          <List<num>>[
            [0, 0],
            [3, 0],
            [1.5, 1],
            [3, 3],
            [0, 3],
            [0, 0],
          ],
        ]),
      ]);

      expect(GeoModel.fromGeoJson(raw).polygons, hasLength(1));
    });

    test('rejects source bytes above the configured limit', () {
      final raw = _featureCollection([
        _polygon([_ring(0)]),
      ]);

      expect(
        () => GeoModel.fromGeoJson(
          raw,
          limits: const GeoJsonLimits(maxSourceBytes: 10),
        ),
        throwsFormatException,
      );
    });

    test('rejects polygon, per-polygon, and total vertex limit overflow', () {
      final twoPolygons = _featureCollection([
        _polygon([_ring(0)]),
        _polygon([_ring(2)]),
      ]);
      expect(
        () => GeoModel.fromGeoJson(
          twoPolygons,
          limits: const GeoJsonLimits(maxPolygons: 1),
        ),
        throwsFormatException,
      );

      final sixPointRing = <List<num>>[
        [0, 0],
        [1, 0],
        [1.5, 0.5],
        [1, 1],
        [0, 1],
        [0, 0],
      ];
      expect(
        () => GeoModel.fromGeoJson(
          _featureCollection([
            _polygon([sixPointRing]),
          ]),
          limits: const GeoJsonLimits(maxVerticesPerPolygon: 5),
        ),
        throwsFormatException,
      );

      expect(
        () => GeoModel.fromGeoJson(
          twoPolygons,
          limits: const GeoJsonLimits(maxTotalVertices: 9),
        ),
        throwsFormatException,
      );
    });

    test('ignores a non-numeric optional version instead of crashing', () {
      final raw = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'version': 'not-a-number'},
            'geometry': _polygon([_ring(0)]),
          },
        ],
      });

      final model = GeoModel.fromGeoJson(raw);

      expect(model.polygons.single.version, isNull);
    });

    test('rejects malformed structures with a located message', () {
      const cases = <String, String>{
        '{"type":"FeatureCollection","features":["nope"]}':
            'Featureはオブジェクトである必要があります',
        '{"type":"FeatureCollection","features":[{"type":"Feature",'
                '"geometry":{"type":"MultiPolygon","coordinates":"nope"}}]}':
            'MultiPolygon.coordinatesは配列である必要があります',
        '{"type":"FeatureCollection","features":[{"type":"Feature",'
                '"geometry":{"type":"Polygon","coordinates":"nope"}}]}':
            'coordinatesは配列である必要があります',
        '{"type":"FeatureCollection","features":[{"type":"Feature",'
                '"geometry":{"type":"Polygon","coordinates":["nope"]}}]}':
            '外周は配列である必要があります',
        '{"type":"FeatureCollection","features":[{"type":"Feature",'
                '"geometry":{"type":"MultiPolygon","coordinates":[[]]}}]}':
            '外周がありません',
        '{"type":"FeatureCollection","features":[{"type":"Feature",'
                '"geometry":{"type":42,"coordinates":[]}}]}':
            '対応していないgeometry type（int）',
        '{"type":"FeatureCollection","features":[{"type":"Feature",'
            '"geometry":{"type":"Polygon","coordinates":'
            '[["nope",[1,1],[1,2],[2,2]]]}}]}': '座標は[経度, 緯度]の配列である必要があります',
        '{"type":"FeatureCollection","features":[{"type":"Feature",'
            '"geometry":{"type":"Polygon","coordinates":'
            '[[[1],[1,1],[1,2],[2,2]]]}}]}': '座標には経度と緯度が必要です',
        '{"type":"FeatureCollection","features":[{"type":"Feature",'
            '"geometry":{"type":"Polygon","coordinates":'
            '[[["a","b"],[1,1],[1,2],[2,2]]]}}]}': '緯度・経度は数値である必要があります',
      };

      cases.forEach((raw, expected) {
        expect(
          () => GeoModel.fromGeoJson(raw),
          throwsA(
            isA<FormatException>()
                .having((e) => e.message, 'message', contains(expected)),
          ),
          reason: raw,
        );
      });
    });

    test('rejects non-finite coordinates', () {
      // JSONにInfinityは書けないので、極端な指数で無限大にする。
      final raw = '{"type":"FeatureCollection","features":[{"type":"Feature",'
          '"geometry":{"type":"Polygon","coordinates":'
          '[[[1e400,1],[1,1],[1,2],[1,1]]]}}]}';

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('有限の数値である必要があります'),
          ),
        ),
      );
    });

    test('rejects a ring with fewer than three distinct vertices', () {
      final raw = _featureCollection([
        _polygon([
          [
            [139.0, 35.0],
            [139.01, 35.0],
            [139.0, 35.0],
            [139.01, 35.0],
            [139.0, 35.0],
          ],
        ]),
      ]);

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('3つ以上の異なる頂点が必要です'),
          ),
        ),
      );
    });

    test('rejects consecutive duplicate vertices with a dedicated message', () {
      // GISの書き出しで普通に混ざる。自己交差と同じメッセージで弾くと
      // 「辺が交差しない外周に修正してください」と言われて原因に辿り着けない。
      final raw = _featureCollection([
        _polygon([
          [
            [139.0, 35.0],
            [139.01, 35.0],
            [139.01, 35.0],
            [139.01, 35.01],
            [139.0, 35.0],
          ],
        ]),
      ]);

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('頂点[1]'),
              contains('頂点[2]'),
              contains('連続する重複頂点を削除してください'),
            ),
          ),
        ),
      );
    });

    test('rejects a feature without geometry instead of skipping it', () {
      const raw = '''
{"type":"FeatureCollection","features":[{"type":"Feature","properties":{}}]}
''';

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Feature[0]'), contains('geometryがありません')),
          ),
        ),
      );
    });

    test('names the feature, polygon and vertex in coordinate errors', () {
      final raw = _featureCollection([
        _polygon([
          [
            [139.0, 35.0],
            [139.01, 35.0],
            [139.01, 95.0],
            [139.0, 35.0],
          ],
        ]),
      ]);

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Feature[0]'),
              contains('Polygon[0]'),
              contains('頂点[2]'),
              contains('緯度が範囲外です'),
              contains('[経度, 緯度]'),
            ),
          ),
        ),
      );
    });

    test('reports how many holes an unsupported polygon has', () {
      final raw = _featureCollection([
        _polygon([
          [
            [139.0, 35.0],
            [139.1, 35.0],
            [139.1, 35.1],
            [139.0, 35.0],
          ],
          [
            [139.02, 35.02],
            [139.03, 35.02],
            [139.03, 35.03],
            [139.02, 35.02],
          ],
        ]),
      ]);

      expect(
        () => GeoModel.fromGeoJson(raw),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('穴（1個）'), contains('対応していません')),
          ),
        ),
      );
    });
  });
}

String _featureCollection(List<Map<String, Object>> geometries) {
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final geometry in geometries)
        {
          'type': 'Feature',
          'properties': <String, Object>{},
          'geometry': geometry,
        },
    ],
  });
}

Map<String, Object> _polygon(List<List<List<num>>> rings) {
  return <String, Object>{
    'type': 'Polygon',
    'coordinates': rings,
  };
}

List<List<num>> _ring(num offset) {
  return <List<num>>[
    [offset, offset],
    [offset + 1, offset],
    [offset + 1, offset + 1],
    [offset, offset + 1],
    [offset, offset],
  ];
}
