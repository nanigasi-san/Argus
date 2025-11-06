import 'package:flutter_test/flutter_test.dart';

import 'package:argus/geo/geo_model.dart';
import 'package:argus/state_machine/state.dart';

void main() {
  test('StateSnapshot copyWith overrides selected fields', () {
    final original = StateSnapshot(
      status: LocationStateStatus.inner,
      timestamp: DateTime.utc(2024, 1, 1),
      distanceToBoundaryM: 12.0,
      horizontalAccuracyM: 5.0,
      hasGeoJson: true,
      notes: 'note',
      nearestBoundaryPoint: const LatLng(35.0, 139.0),
      bearingToBoundaryDeg: 123,
    );

    final copy = original.copyWith(
      status: LocationStateStatus.outer,
      notes: 'changed',
      hasGeoJson: false,
    );

    expect(copy.status, LocationStateStatus.outer);
    expect(copy.notes, 'changed');
    expect(copy.hasGeoJson, isFalse);
    expect(copy.distanceToBoundaryM, original.distanceToBoundaryM);
    expect(copy.nearestBoundaryPoint, original.nearestBoundaryPoint);
  });
}
