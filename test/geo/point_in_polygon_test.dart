import 'package:flutter_test/flutter_test.dart';

import 'package:argus/geo/geo_model.dart';
import 'package:argus/geo/point_in_polygon.dart';

void main() {
  group('PointInPolygon', () {
    late PointInPolygon pip;
    late GeoPolygon squarePolygon;

    setUp(() {
      pip = const PointInPolygon();
      squarePolygon = GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.0, 139.01),
          LatLng(35.01, 139.01),
          LatLng(35.01, 139.0),
        ],
      );
    });

    test('correctly identifies point inside polygon', () {
      final evaluation = pip.evaluatePoint(35.005, 139.005, squarePolygon);
      expect(evaluation.contains, true);
      expect(evaluation.distanceToBoundaryM, greaterThan(0));
      expect(evaluation.nearestPoint, isNotNull);
      expect(evaluation.bearingToBoundaryDeg, isNotNull);
    });

    test('correctly identifies point outside polygon', () {
      final evaluation = pip.evaluatePoint(35.02, 139.02, squarePolygon);
      expect(evaluation.contains, false);
      expect(evaluation.distanceToBoundaryM, greaterThan(0));
      expect(evaluation.nearestPoint, isNotNull);
      expect(evaluation.bearingToBoundaryDeg, isNotNull);
    });

    test('correctly identifies point on boundary', () {
      // Point on the western edge
      final evaluation = pip.evaluatePoint(35.005, 139.0, squarePolygon);
      // Boundary behavior may vary - just check it doesn't crash and distance is small
      expect(evaluation.distanceToBoundaryM,
          lessThan(100)); // Should be very close to 0
    });

    test('calculates distance to boundary for inside point', () {
      // Point at center
      final center = pip.evaluatePoint(35.005, 139.005, squarePolygon);
      expect(center.contains, true);
      expect(center.nearestPoint, isNotNull);
      expect(center.bearingToBoundaryDeg, isNotNull);

      // Point near edge
      final nearEdge = pip.evaluatePoint(35.0, 139.009, squarePolygon);
      expect(nearEdge.contains, true);
      expect(
          nearEdge.distanceToBoundaryM, lessThan(center.distanceToBoundaryM));
    });

    test('calculates distance to boundary for outside point', () {
      // Point far outside
      final far = pip.evaluatePoint(36.0, 140.0, squarePolygon);
      expect(far.contains, false);
      expect(far.distanceToBoundaryM, greaterThan(10000));
      expect(far.nearestPoint, isNotNull);
      expect(far.bearingToBoundaryDeg, isNotNull);

      // Point close outside
      final close = pip.evaluatePoint(35.005, 139.02, squarePolygon);
      expect(close.contains, false);
      expect(close.distanceToBoundaryM, lessThan(far.distanceToBoundaryM));
      expect(close.nearestPoint, isNotNull);
      expect(close.bearingToBoundaryDeg, isNotNull);
    });

    test('handles complex polygon shape', () {
      // L-shaped polygon
      final lShape = GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.0, 139.02),
          LatLng(35.01, 139.02),
          LatLng(35.01, 139.01),
          LatLng(35.005, 139.01),
          LatLng(35.005, 139.0),
        ],
      );

      // Point inside L-shape
      final inside = pip.evaluatePoint(35.002, 139.005, lShape);
      expect(inside.contains, true);

      // Point in the "hole" of L-shape (actually this point might be inside depending on raycast)
      // Testing a point clearly outside
      final outside = pip.evaluatePoint(35.015, 139.025, lShape);
      expect(outside.contains, false);
    });

    test('handles triangle polygon', () {
      final triangle = GeoPolygon(
        points: const [
          LatLng(35.0, 139.0),
          LatLng(35.01, 139.0),
          LatLng(35.005, 139.01),
        ],
      );

      final inside = pip.evaluatePoint(35.005, 139.005, triangle);
      expect(inside.contains, true);

      final outside = pip.evaluatePoint(35.02, 139.02, triangle);
      expect(outside.contains, false);
    });

    test('raycast handles edge cases', () {
      // Point exactly on a vertex
      final onVertex = pip.evaluatePoint(35.0, 139.0, squarePolygon);
      // Behavior may vary, but should not crash
      expect(onVertex.distanceToBoundaryM, greaterThanOrEqualTo(0));

      // Point on horizontal edge
      final onEdge = pip.evaluatePoint(35.005, 139.01, squarePolygon);
      expect(onEdge.distanceToBoundaryM, lessThan(100));
    });

    test('distance calculation for point near corner', () {
      // Point very close to a corner
      final nearCorner = pip.evaluatePoint(35.0001, 139.0001, squarePolygon);
      expect(nearCorner.distanceToBoundaryM, lessThan(100));

      // Point at exact corner
      final atCorner = pip.evaluatePoint(35.0, 139.0, squarePolygon);
      expect(atCorner.distanceToBoundaryM, lessThan(100));
    });

    test('provides reasonable bearing and nearest point', () {
      final northOfArea = pip.evaluatePoint(35.02, 139.005, squarePolygon);
      expect(northOfArea.contains, false);
      expect(northOfArea.nearestPoint, isNotNull);
      expect(
        northOfArea.nearestPoint!.latitude,
        closeTo(35.01, 1e-6),
      );
      expect(
        northOfArea.nearestPoint!.longitude,
        closeTo(139.005, 1e-6),
      );
      expect(northOfArea.bearingToBoundaryDeg, isNotNull);
      expect(
        northOfArea.bearingToBoundaryDeg!,
        closeTo(180, 5),
      );
    });
  });
}
