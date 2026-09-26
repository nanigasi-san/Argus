import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';

import 'package:argus/main.dart';
import 'package:argus/ui/usage_mode_selection_page.dart';

import 'support/test_doubles.dart';

void main() {
  testWidgets('Argus app starts with the usage-mode choice',
      (WidgetTester tester) async {
    final controller = buildTestController();

    await tester.pumpWidget(ArgusApp(controller: controller));
    await tester.pump();

    expect(find.text('ARGUS'), findsWidgets);
    expect(find.byType(UsageModeSelectionPage), findsOneWidget);
    expect(find.text('スマホで利用'), findsOneWidget);
  });

  testWidgets('Argus app wraps the entry screen with store update checks',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'ARGUS',
      packageName: 'com.argus.orienteering',
      version: '0.5.0',
      buildNumber: '1005',
      buildSignature: '',
    );
    final controller = buildTestController();

    await tester.pumpWidget(
      ArgusApp(
        controller: controller,
        upgrader: Upgrader(
          countryCode: 'JP',
          languageCode: 'ja',
          storeController: UpgraderStoreController(
            onAndroid: null,
            oniOS: null,
            onLinux: null,
            onMacOS: null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(UpgradeAlert), findsOneWidget);
    expect(find.byType(UsageModeSelectionPage), findsOneWidget);
    expect(find.text('ARGUS'), findsWidgets);
  });
}
