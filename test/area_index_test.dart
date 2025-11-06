import 'package:argus/geo/area_index.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AreaIndex.lookup', () {
    late GeoPolygon square;
    late GeoPolygon rectangle;
    late AreaIndex index;

    setUp(() {
      square = GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.0, 139.01),
          LatLng(35.01, 139.01),
          LatLng(35.01, 139.0),
        ],
        name: 'Square',
      );
      rectangle = GeoPolygon(
        points: const [
          LatLng(36.0, 140.0),
          LatLng(36.0, 140.02),
          LatLng(36.01, 140.02),
          LatLng(36.01, 140.0),
        ],
        name: 'Rectangle',
      );
      index = AreaIndex.build([square, rectangle]);
    });

    test('returns polygons whose bounding box contains the point', () {
      final candidates = index.lookup(35.005, 139.005).toList();

      expect(candidates.length, 1);
      expect(candidates.first.name, 'Square');
    });

    test('returns multiple candidates when bounding boxes overlap point', () {
      final overlapping = GeoPolygon(
        points: const [
          LatLng(35.004, 139.004),
          LatLng(35.004, 139.006),
          LatLng(35.006, 139.006),
          LatLng(35.006, 139.004),
        ],
        name: 'Overlay',
      );
      index = AreaIndex.build([square, overlapping]);

      final candidates = index.lookup(35.005, 139.005).toList();
      final names = candidates.map((p) => p.name).toList();

      expect(names, containsAll(['Square', 'Overlay']));
    });

    test('returns empty iterable when point outside all bounding boxes', () {
      final candidates = index.lookup(37.0, 141.0).toList();

      expect(candidates, isEmpty);
    });

    test('empty index yields empty iterable without errors', () {
      final emptyIndex = AreaIndex.empty();

      expect(emptyIndex.lookup(0, 0), isEmpty);
    });
  });
}
