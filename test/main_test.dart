import 'package:flutter_test/flutter_test.dart';

import 'package:argus/main.dart';
import 'package:argus/state_machine/state.dart';

import 'support/test_doubles.dart';

void main() {
  testWidgets('ArgusApp provides controller and renders HomePage', (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        hasGeoJson: true,
      ),
      geoJsonFileName: 'test.geojson',
    );

    await tester.pumpWidget(ArgusApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Argus'), findsOneWidget);
    expect(find.textContaining('GeoJSON'), findsWidgets);
  });
}
