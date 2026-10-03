import 'dart:convert';
import 'dart:math' as math;

import 'package:argus/garmin/garmin_course_encoder.dart';
import 'package:argus/garmin/garmin_course_validator.dart';
import 'package:argus/geo/geojson_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const _originLatitude = 35.0;
const _originLongitude = 139.0;

/// Geographic fixtures described in metres about the expected projection origin.
String _course(List<(double, double)> vertices) {
  final longitudeScale = 111320 * math.cos(_originLatitude * math.pi / 180);
  final ring = [
    for (final (x, y) in vertices)
      [_originLongitude + x / longitudeScale, _originLatitude + y / 110540],
  ];
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [...ring, ring.first],
          ],
        },
      },
    ],
  });
}

void main() {
  const phone = GeoJsonValidator();
  const garmin = GarminCourseValidator();

  for (final axis in ['x', 'y']) {
    for (final extreme in [-32768, 32767, -32769, 32768]) {
      final accepted = extreme >= -32768 && extreme <= 32767;
      test(
          '$axis=$extreme is ${accepted ? 'accepted' : 'rejected'} by int16 '
          'validation before encoding', () {
        // The three axis values sum to zero. A symmetric rectangle would
        // exercise the positive limit first and miss the asymmetric lower bound.
        final second = -(extreme ~/ 2);
        final third = -extreme - second;
        final alongX = <(double, double)>[
          (extreme.toDouble(), 0),
          (second.toDouble(), -100),
          (third.toDouble(), 100),
        ];
        final vertices =
            axis == 'x' ? alongX : [for (final (x, y) in alongX) (y, x)];
        final source = phone.validate(_course(vertices));
        expect(source.validForPhone, isTrue);

        final result = garmin.validate(source);
        expect(result.validForGarmin, accepted);
        if (!accepted) {
          expect(result.prepared, isNull);
          expect(result.issues.single.code, 'E_LOCAL_COORD_OVERFLOW');
          expect(result.issues.single.vertexIndex, 0);
          expect(result.issues.single.actual, extreme);
          expect(result.issues.single.limit, extreme < 0 ? -32768 : 32767);
          return;
        }

        expect(result.issues, isEmpty);
        final prepared = result.prepared!;
        expect(axis == 'x' ? prepared.points.first.x : prepared.points.first.y,
            extreme);
        final payload = GarminCourseEncoder()
            .encodePrepared(prepared, fileName: 'boundary.geojson');
        expect(payload.vertexCount, 3);
        expect(payload.bytes, prepared.dataBytes);
        expect(payload.data, startsWith('AGW1|'));
      });
    }
  }

  test('integer rounding rejects a crossing introduced into a simple polygon',
      () {
    final source = phone.validate(_course(const [
      (-1.46746, 3.38272),
      (-2.37365, 0.16427),
      (-0.03339, -2.04649),
      (0.85528, 0.51162),
      (1.56015, -1.83125),
      (1.45906, -0.18088),
    ]));
    expect(source.validForPhone, isTrue);
    // Rounded vertices are (-1,3), (-2,0), (0,-2), (1,1), (2,-2), (1,0).
    // All six are distinct and their signed double area is 13. Only edges
    // (0,-2)->(1,1) and (1,0)->(-1,3) cross after rounding.
    final result = garmin.validate(source);
    expect(result.validForGarmin, isFalse);
    expect(result.prepared, isNull);
    expect(result.issues.single.code, 'E_GARMIN_QUANTIZED_GEOMETRY');
  });

  test('integer rounding rejects zero area even with three distinct vertices',
      () {
    final source = phone.validate(_course(const [
      (-10, 0.1),
      (0, -0.2),
      (10, 0.1),
    ]));
    expect(source.validForPhone, isTrue);
    expect(source.areaSquareMeters, greaterThan(0));
    // Rounding leaves (-10,0), (0,0), (10,0): three distinct but collinear points.
    final result = garmin.validate(source);
    expect(result.validForGarmin, isFalse);
    expect(result.prepared, isNull);
    expect(result.issues.single.code, 'E_GARMIN_QUANTIZED_GEOMETRY');
  });
}
