import 'dart:convert';
import 'dart:math' as math;

import 'package:argus/garmin/garmin_course_encoder.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes a closed polygon as compact AGW1 coordinates', () {
    final model = GeoModel([
      GeoPolygon(points: const [
        LatLng(35.0, 139.0),
        LatLng(35.0, 139.001),
        LatLng(35.001, 139.001),
        LatLng(35.001, 139.0),
      ]),
    ]);

    final payload = GarminCourseEncoder().encode(
      model,
      fileName: 'race.geojson',
      armedUntil: DateTime.fromMillisecondsSinceEpoch(2000000000000),
    );

    expect(payload.data, startsWith('AGW1|'));
    expect(payload.vertexCount, 4);
    expect(payload.bytes, payload.data.length);
    expect(payload.courseId, startsWith('race.geojson_'));
    expect(payload.displayName, 'race.geojson');
    expect(payload.toMap()['displayName'], 'race.geojson');
    expect(payload.checksum, matches(RegExp(r'^\d+$')));
    expect(payload.toMap()['armedUntil'], 2000000000);
  });

  test('preserves a Japanese basename for the watch display', () {
    final model = GeoModel([
      GeoPolygon(points: const [
        LatLng(35, 139),
        LatLng(35, 139.001),
        LatLng(35.001, 139),
      ]),
    ]);
    final payload = GarminCourseEncoder().encode(
      model,
      fileName: r'/courses/千葉大.geojson',
    );
    expect(payload.displayName, '千葉大.geojson');
    final longName = GarminCourseEncoder().encode(
      model,
      fileName: '${List.filled(20, '長い名前').join()}.geojson',
    );
    expect(utf8.encode(longName.displayName).length, lessThanOrEqualTo(48));
  });

  test('rejects multiple polygons and polygons over 100 vertices', () {
    final triangle = GeoPolygon(points: const [
      LatLng(35, 139),
      LatLng(35, 139.001),
      LatLng(35.001, 139),
    ]);
    expect(
      () => GarminCourseEncoder().encode(
        GeoModel([triangle, triangle]),
        fileName: 'two.geojson',
      ),
      throwsFormatException,
    );

    final many = List.generate(
      101,
      (index) => LatLng(35 + index / 100000, 139 + index / 100000),
    );
    expect(
      () => GarminCourseEncoder().encode(
        GeoModel([GeoPolygon(points: many)]),
        fileName: 'many.geojson',
      ),
      throwsFormatException,
    );
  });

  test('encodes a 100-vertex ten-kilometre square within the byte limit', () {
    const originLat = 35.0;
    const originLon = 140.0;
    final metresPerLon = 111320 * math.cos(originLat * math.pi / 180);
    final xy = <(int, int)>[
      for (var i = 0; i < 25; i++) (-5000 + 400 * i, -5000),
      for (var i = 0; i < 25; i++) (5000, -5000 + 400 * i),
      for (var i = 0; i < 25; i++) (5000 - 400 * i, 5000),
      for (var i = 0; i < 25; i++) (-5000, 5000 - 400 * i),
    ];
    final model = GeoModel([
      GeoPolygon(
        points: [
          for (final (x, y) in xy)
            LatLng(originLat + y / 110540, originLon + x / metresPerLon),
        ],
      ),
    ]);

    final payload = GarminCourseEncoder().encode(
      model,
      fileName: 'ten-kilometre.geojson',
    );

    expect(payload.vertexCount, 100);
    expect(payload.bytes, 1088);
    expect(payload.bytes, lessThanOrEqualTo(2048));
  });
}
