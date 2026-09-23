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
    expect(payload.checksum, matches(RegExp(r'^\d+$')));
    expect(payload.toMap()['armedUntil'], 2000000000);
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
}
