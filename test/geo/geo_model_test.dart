import 'package:flutter_test/flutter_test.dart';

import 'package:argus/geo/geo_model.dart';

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

    test('parses GeoJSON FeatureCollection with MultiPolygon', () {
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

      final model = GeoModel.fromGeoJson(geoJson);
      expect(model.polygons.length, 2);
      expect(model.hasGeometry, true);
    });

    test('rejects an empty FeatureCollection', () {
      const geoJson = '''
      {
        "type": "FeatureCollection",
        "features": []
      }
      ''';

      expect(
        () => GeoModel.fromGeoJson(geoJson),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('featuresが空です'),
          ),
        ),
      );
    });

    test('rejects unsupported geometry types instead of skipping them', () {
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

      // 黙って読み飛ばすと競技エリアが欠けたまま監視を開始してしまう。
      expect(
        () => GeoModel.fromGeoJson(geoJson),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Feature[0]'),
              contains('対応していないgeometry type'),
              contains('Point'),
            ),
          ),
        ),
      );
    });

    test('rejects polygons with insufficient points', () {
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

      expect(
        () => GeoModel.fromGeoJson(geoJson),
        throwsA(isA<FormatException>()),
      );
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

    test('rejects an empty MultiPolygon', () {
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

      expect(
        () => GeoModel.fromGeoJson(geoJson),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('MultiPolygonにPolygonがありません'),
          ),
        ),
      );
    });
  });
}
