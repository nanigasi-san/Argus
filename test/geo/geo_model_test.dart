import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:argus/geo/geo_model.dart';
import 'package:argus/geo/geojson_validator.dart';

void main() {
  group('GeoPolygon', () {
    test('creates polygon with valid points', () {
      final polygon = GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.0, 139.01),
          LatLng(35.01, 139.01),
          LatLng(35.01, 139.0),
        ],
        name: 'Test Area',
        version: 1,
      );

      // Polygon is automatically closed, so length is 5 (4 original + 1 closing point)
      expect(polygon.points.length, 5);
      expect(polygon.name, 'Test Area');
      expect(polygon.version, 1);
      expect(polygon.minLat, 35.0);
      expect(polygon.maxLat, 35.01);
      expect(polygon.minLon, 139.0);
      expect(polygon.maxLon, 139.01);
    });

    test('closes polygon if not already closed', () {
      final polygon = GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.0, 139.01),
          LatLng(35.01, 139.01),
          LatLng(35.01, 139.0),
          // Not closed - missing first point
        ],
      );

      // Should have 5 points (4 original + 1 closing)
      expect(polygon.points.length, 5);
      expect(polygon.points.first, polygon.points.last);
    });

    test('does not duplicate closing point if already closed', () {
      final polygon = GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.0, 139.01),
          LatLng(35.01, 139.01),
          LatLng(35.01, 139.0),
          LatLng(35.0, 139.0), // Already closed
        ],
      );

      expect(polygon.points.length, 5);
    });

    test('calculates bounds correctly', () {
      final polygon = GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.02, 139.03),
          LatLng(35.01, 139.01),
        ],
      );

      expect(polygon.minLat, 35.0);
      expect(polygon.maxLat, 35.02);
      expect(polygon.minLon, 139.0);
      expect(polygon.maxLon, 139.03);
    });
  });

  group('GeoModel', () {
    test('owns an immutable copy of the polygons', () {
      final polygons = <GeoPolygon>[];
      final model = GeoModel(polygons);
      polygons.add(GeoPolygon(points: const []));
      expect(model.hasGeometry, isFalse);
      expect(() => model.polygons.clear(), throwsUnsupportedError);
    });

    test('malformed JSON structures produce recoverable format errors', () {
      for (final raw in ['[]', 'null', '{"features":{}}', '{"features":[1]}']) {
        expect(() => GeoModel.fromGeoJson(raw), throwsFormatException,
            reason: raw);
      }
    });

    test('rejects incomplete, nonnumeric and out-of-range coordinates', () {
      for (final pair in <Object>[
        [],
        [139],
        ['139', 35],
        [139, null],
        [181, 35],
        [139, 91],
      ]) {
        final raw = jsonEncode({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [
                  [
                    [139, 35],
                    pair,
                    [139.01, 35.01],
                    [139, 35.01],
                    [139, 35],
                  ]
                ]
              }
            }
          ],
        });
        final result = const GeoJsonValidator().validate(raw);
        expect(result.errors.single.code, 'E_INVALID_COORDINATE',
            reason: '$pair');
        expect(() => GeoModel.fromGeoJson(raw), throwsFormatException,
            reason: '$pair');
      }
    });

    test('rejects nonfinite coordinates decoded from JSON exponents', () {
      for (final position in ['[1e400,35]', '[139,1e400]']) {
        final raw = '{"type":"FeatureCollection","features":'
            '[{"type":"Feature","geometry":{"type":"Polygon",'
            '"coordinates":[[[139,35],$position,[139.01,35.01],'
            '[139,35.01],[139,35]]]}}]}';
        final result = const GeoJsonValidator().validate(raw);
        expect(result.errors.single.code, 'E_INVALID_COORDINATE',
            reason: position);
        expect(() => GeoModel.fromGeoJson(raw), throwsFormatException,
            reason: position);
      }
    });

    test('accepts optional altitude in a valid exterior ring', () {
      final model = GeoModel.fromGeoJson(jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'name': 'area', 'version': 2},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [139, 35, 5],
                  [139.01, 35, 6],
                  [139, 35.01, 7],
                  [139, 35, 5]
                ],
              ]
            },
          }
        ],
      }));
      expect(model.polygons, hasLength(1));
      expect(model.polygons.single.points, hasLength(4));
      expect(model.polygons.single.name, 'area');
    });

    test('creates empty model', () {
      final model = GeoModel.empty();
      expect(model.polygons, isEmpty);
      expect(model.hasGeometry, false);
    });

    test('creates model with polygons', () {
      final polygon1 = GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.0, 139.01),
          LatLng(35.01, 139.01),
          LatLng(35.01, 139.0),
        ],
      );
      final polygon2 = GeoPolygon(
        points: const [
          LatLng(36.0, 140.0),
          LatLng(36.0, 140.01),
          LatLng(36.01, 140.01),
          LatLng(36.01, 140.0),
        ],
      );

      final model = GeoModel([polygon1, polygon2]);
      expect(model.polygons.length, 2);
      expect(model.hasGeometry, true);
    });

    test('parses GeoJSON FeatureCollection with Polygon', () {
      const geoJson = '''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {
              "name": "Test Area",
              "version": 1
            },
            "geometry": {
              "type": "Polygon",
              "coordinates": [[
                [139.0, 35.0],
                [139.01, 35.0],
                [139.01, 35.01],
                [139.0, 35.01],
                [139.0, 35.0]
              ]]
            }
          }
        ]
      }
      ''';

      final model = GeoModel.fromGeoJson(geoJson);
      expect(model.polygons.length, 1);
      expect(model.hasGeometry, true);
      expect(model.polygons.first.name, 'Test Area');
      expect(model.polygons.first.version, 1);
    });

    test('rejects GeoJSON FeatureCollection with MultiPolygon', () {
      const geoJson = '''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {
              "name": "Multi Area"
            },
            "geometry": {
              "type": "MultiPolygon",
              "coordinates": [
                [[[139.0, 35.0], [139.01, 35.0], [139.01, 35.01], [139.0, 35.01], [139.0, 35.0]]],
                [[[140.0, 36.0], [140.01, 36.0], [140.01, 36.01], [140.0, 36.01], [140.0, 36.0]]]
              ]
            }
          }
        ]
      }
      ''';

      expect(() => GeoModel.fromGeoJson(geoJson), throwsFormatException);
    });

    test('handles empty FeatureCollection', () {
      const geoJson = '''
      {
        "type": "FeatureCollection",
        "features": []
      }
      ''';

      expect(() => GeoModel.fromGeoJson(geoJson), throwsFormatException);
    });

    test('handles GeoJSON with unsupported geometry types', () {
      const geoJson = '''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [139.0, 35.0]
            }
          },
          {
            "type": "Feature",
            "geometry": {
              "type": "Polygon",
              "coordinates": [[[139.0, 35.0], [139.01, 35.0], [139.01, 35.01], [139.0, 35.01], [139.0, 35.0]]]
            }
          }
        ]
      }
      ''';

      expect(() => GeoModel.fromGeoJson(geoJson), throwsFormatException);
    });

    test('handles polygons with insufficient points', () {
      const geoJson = '''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Polygon",
              "coordinates": [[[139.0, 35.0], [139.01, 35.0]]]
            }
          }
        ]
      }
      ''';

      expect(() => GeoModel.fromGeoJson(geoJson), throwsFormatException);
    });

    test('handles missing properties', () {
      const geoJson = '''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Polygon",
              "coordinates": [[[139.0, 35.0], [139.01, 35.0], [139.01, 35.01], [139.0, 35.01], [139.0, 35.0]]]
            }
          }
        ]
      }
      ''';

      final model = GeoModel.fromGeoJson(geoJson);
      expect(model.polygons.length, 1);
      expect(model.polygons.first.name, null);
      expect(model.polygons.first.version, null);
    });

    test('handles empty MultiPolygon', () {
      const geoJson = '''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "MultiPolygon",
              "coordinates": []
            }
          }
        ]
      }
      ''';

      expect(() => GeoModel.fromGeoJson(geoJson), throwsFormatException);
    });
  });
}
