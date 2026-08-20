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
      ];

      for (final ring in invalidRings) {
        final raw = _featureCollection([
          _polygon([ring]),
        ]);
        expect(() => GeoModel.fromGeoJson(raw), throwsFormatException);
      }
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
