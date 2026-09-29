import 'package:argus/main.dart';
import 'package:argus/ui/garmin_transfer_page.dart';
import 'package:argus/ui/home_page.dart';
import 'package:argus/ui/usage_mode_selection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_doubles.dart';

void main() {
  testWidgets('phone mode is selected by default and opens the existing home',
      (tester) async {
    await tester.pumpWidget(ArgusApp(controller: buildTestController()));
    await tester.pumpAndSettle();

    expect(find.byType(UsageModeSelectionPage), findsOneWidget);
    expect(
        find.descendant(
          of: find.byKey(const Key('phoneModeChoice')),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget);
    expect(find.byType(HomePage), findsNothing);

    await tester.tap(find.byKey(const Key('usageModeNextButton')));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('WAIT GEOJSON'), findsOneWidget);
  });

  testWidgets('Garmin mode opens the existing transfer page', (tester) async {
    await tester.pumpWidget(ArgusApp(controller: buildTestController()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('garminModeChoice')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
          of: find.byKey(const Key('garminModeChoice')),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('usageModeNextButton')));
    await tester.pumpAndSettle();

    expect(find.byType(GarminTransferPage), findsOneWidget);
    expect(find.text('GARMINに送る'), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
  });

  testWidgets('mode choice remains usable on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(ArgusApp(controller: buildTestController()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('garminModeChoice')));
    await tester.tap(find.byKey(const Key('garminModeChoice')));
    await tester.ensureVisible(find.byKey(const Key('usageModeNextButton')));
    await tester.tap(find.byKey(const Key('usageModeNextButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(GarminTransferPage), findsOneWidget);
  });
}
