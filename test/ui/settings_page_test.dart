import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/ui/settings_page.dart';

import '../support/notifier_fakes.dart';
import '../support/test_doubles.dart';

Future<void> _mockDefaultConfigAsset() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = await File('assets/config/default_config.json').readAsBytes();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter/assets'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'loadString' &&
          methodCall.arguments == 'assets/config/default_config.json') {
        return String.fromCharCodes(bytes);
      }
      return null;
    },
  );
}

Future<void> _pumpSettings(
  WidgetTester tester,
  AppController controller, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxTicks = 10,
}) async {
  for (var i = 0; i < maxTicks; i++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Widget matching ${finder.description} not found after pumping.');
}

void main() {
  setUpAll(() async {
    await _mockDefaultConfigAsset();
  });

  testWidgets('shows progress indicator when config is null', (tester) async {
    final config = createTestConfig();
    final controller = AppController(
      stateMachine: StateMachine(config: config),
      locationService: FakeLocationService(),
      fileManager: FakeFileManager(config: config),
      logger: FakeEventLogger(),
      notifier: Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: FakeAlarmPlayer(),
      ),
    );

    await _pumpSettings(tester, controller, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders form fields when config available', (tester) async {
    final controller = buildTestController(hasGeoJson: true);
    expect(controller.config, isNotNull);

    await _pumpSettings(tester, controller, settle: false);
    await _pumpUntilVisible(
      tester,
      find.text('反応距離 (Inner buffer)'),
    );

    expect(find.text('反応距離 (Inner buffer)'), findsOneWidget);
  });

  testWidgets('toggling developer mode switch calls controller',
      (tester) async {
    final controller = buildTestController(hasGeoJson: true);
    expect(controller.config, isNotNull);

    await _pumpSettings(tester, controller, settle: false);
    final switchFinder = find.byKey(const Key('developerModeSwitch'));
    final listFinder = find.byType(ListView);
    var attempts = 0;
    while (switchFinder.evaluate().isEmpty && attempts < 5) {
      await tester.drag(listFinder, const Offset(0, -300));
      await tester.pump();
      attempts += 1;
    }
    expect(switchFinder, findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(controller.developerMode, isTrue);
  });
}
