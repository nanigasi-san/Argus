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
  AppController controller,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
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

    await _pumpSettings(tester, controller);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders form fields when config available', (tester) async {
    final controller = buildTestController(hasGeoJson: true);

    await _pumpSettings(tester, controller);

    expect(find.text('反応距離 (Inner buffer)'), findsOneWidget);
    final textField = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(textField.controller?.text.isNotEmpty, isTrue);
  });

  testWidgets('toggling developer mode switch calls controller',
      (tester) async {
    final controller = buildTestController(hasGeoJson: true);

    await _pumpSettings(tester, controller);

    final switchFinder = find.byType(SwitchListTile);
    expect(switchFinder, findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(controller.isDeveloperModeEnabled, isTrue);
  });
}
