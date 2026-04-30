import 'package:argus/app_controller.dart';
import 'package:argus/io/config.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../support/notifier_fakes.dart';
import '../support/platform_mocks.dart';
import '../support/test_doubles.dart';

Future<void> _pumpSettings(
  WidgetTester tester,
  AppController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider.value(
        value: controller,
        child: SettingsPage(key: UniqueKey()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _enterFieldText(
  WidgetTester tester,
  Key key,
  String value,
) async {
  final finder = find.byKey(key);
  await _scrollUntilVisible(tester, finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.enterText(finder, value);
  await tester.pump();
}

Future<void> _invokeSaveButton(WidgetTester tester) async {
  final finder = find.byKey(const Key('saveSettingsButton'));
  await _scrollUntilVisible(tester, finder);
  final button = tester.widget<ElevatedButton>(finder);
  expect(button.onPressed, isNotNull);
  button.onPressed!.call();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    await mockDefaultConfigAsset();
  });

  tearDown(() async {
    await mockDefaultConfigAsset();
  });

  tearDownAll(() async {
    await clearDefaultConfigAssetMock();
  });

  testWidgets('empty fields save with defaults and slider updates volume',
      (tester) async {
    final controller = _RecordingSettingsController();

    await _pumpSettings(tester, controller);
    await _enterFieldText(tester, const Key('innerBufferField'), '');
    await _enterFieldText(tester, const Key('pollingIntervalField'), '');
    await _scrollUntilVisible(tester, find.byType(Slider));
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();
    await _invokeSaveButton(tester);

    expect(controller.updateConfigCalls, 1);
    expect(controller.savedConfig, isNotNull);
    expect(controller.savedConfig!.innerBufferM, AppConfig.defaultInnerBufferM);
    expect(controller.savedConfig!.alarmVolume, greaterThan(0.5));
    expect(find.text('設定を反映しました'), findsOneWidget);
  });
}

class _RecordingSettingsController extends AppController {
  _RecordingSettingsController()
      : super(
          stateMachine: StateMachine(config: createTestConfig()),
          locationService: FakeLocationService(),
          fileManager: FakeFileManager(config: createTestConfig()),
          logger: FakeEventLogger(),
          notifier: Notifier(
            notificationsClient: FakeLocalNotificationsClient(),
            alarmPlayer: FakeAlarmPlayer(),
          ),
        ) {
    debugSeed(
      config: createTestConfig(),
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.granted,
        locationAlwaysStatus: PermissionStatus.granted,
        locationServicesEnabled: true,
      ),
    );
  }

  AppConfig? savedConfig;
  Object? updateConfigError;
  int updateConfigCalls = 0;

  @override
  Future<void> updateConfig(AppConfig newConfig) async {
    updateConfigCalls += 1;
    if (updateConfigError != null) {
      throw updateConfigError!;
    }
    savedConfig = newConfig;
    debugSeed(config: newConfig);
  }
}
