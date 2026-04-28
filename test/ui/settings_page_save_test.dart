import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/io/config.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/ui/settings_page.dart';
import 'package:permission_handler/permission_handler.dart';

import '../support/notifier_fakes.dart';
import '../support/platform_mocks.dart';
import '../support/test_doubles.dart';

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
  tester.widget<ElevatedButton>(finder).onPressed!.call();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await mockDefaultConfigAsset();
  });

  tearDownAll(() async {
    await clearDefaultConfigAssetMock();
  });

  testWidgets('valid settings values are normalized and saved', (tester) async {
    final controller = _RecordingSettingsController();

    await _pumpSettings(tester, controller);
    await _enterFieldText(tester, const Key('innerBufferField'), '45.5');
    await _enterFieldText(tester, const Key('pollingIntervalField'), '2');
    await _enterFieldText(tester, const Key('gpsAccuracyField'), '55.5');
    await _enterFieldText(tester, const Key('leaveConfirmSamplesField'), '4');
    await _enterFieldText(tester, const Key('leaveConfirmSecondsField'), '12');
    await _invokeSaveButton(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(controller.updateConfigCalls, 1);
    expect(controller.savedConfig?.innerBufferM, 45.5);
    expect(controller.savedConfig?.effectiveFastSampleIntervalS, 2);
    expect(controller.savedConfig?.gpsAccuracyBadMeters, 55.5);
    expect(controller.savedConfig?.leaveConfirmSamples, 4);
    expect(controller.savedConfig?.leaveConfirmSeconds, 12);
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
  int updateConfigCalls = 0;

  @override
  Future<void> updateConfig(AppConfig newConfig) async {
    updateConfigCalls += 1;
    savedConfig = newConfig;
    debugSeed(config: newConfig);
  }
}
