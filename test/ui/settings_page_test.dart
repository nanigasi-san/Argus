import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:argus/io/config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/ui/settings_page.dart';

import '../support/notifier_fakes.dart';
import '../support/platform_mocks.dart';
import '../support/test_doubles.dart';

Future<void> _pumpSettings(
  WidgetTester tester,
  AppController controller, {
  bool settle = true,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(home: SettingsPage(key: UniqueKey())),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    await mockDefaultConfigAsset();
  });

  tearDown(() async {
    await clearUrlLauncherMock();
    await mockDefaultConfigAsset();
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

    await _pumpSettings(tester, controller);

    expect(find.text('境界バッファ距離'), findsOneWidget);
    expect(find.text('プライバシーポリシー'), findsOneWidget);
    expect(find.textContaining('デフォルト:'), findsWidgets);
  });

  testWidgets('falls back when default config asset cannot load',
      (tester) async {
    await clearDefaultConfigAssetMock();
    addTearDown(mockDefaultConfigAsset);
    final controller = buildTestController(hasGeoJson: true);

    await _pumpSettings(tester, controller);

    expect(find.text('境界バッファ距離'), findsOneWidget);
    expect(find.textContaining('デフォルト:'), findsWidgets);
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

    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(controller.developerMode, isTrue);
  });

  testWidgets('permission card opens disclosure flow', (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.granted,
        locationAlwaysStatus: PermissionStatus.denied,
        locationServicesEnabled: true,
      ),
    );

    await _pumpSettings(tester, controller);

    await tester.tap(find.text('監視開始前に設定する'));
    await tester.pumpAndSettle();

    expect(find.text('バックグラウンド位置情報の開示'), findsOneWidget);
    expect(
      find.textContaining('アプリを閉じているときや使用していないとき'),
      findsWidgets,
    );
  });

  testWidgets('privacy policy failure shows snackbar', (tester) async {
    await mockUrlLauncher(launchResult: false);
    final controller = _RecordingSettingsController();

    await _pumpSettings(tester, controller);

    await tester.tap(find.byKey(const Key('privacyPolicyTile')));
    await tester.pumpAndSettle();

    expect(find.text('プライバシーポリシーを開けませんでした。'), findsOneWidget);
  });

  testWidgets('export logs opens dialog and can close', (tester) async {
    final controller = _RecordingSettingsController();

    await _pumpSettings(tester, controller);
    await _scrollUntilVisible(
        tester, find.byKey(const Key('exportLogsButton')));
    await tester.tap(find.byKey(const Key('exportLogsButton')));
    await tester.pumpAndSettle();

    expect(find.text('ログ出力 (JSONL)'), findsOneWidget);
    expect(find.text('閉じる'), findsOneWidget);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    expect(find.text('ログ出力 (JSONL)'), findsNothing);
  });

  testWidgets('invalid values block save and show validation errors',
      (tester) async {
    final controller = _RecordingSettingsController();

    await _pumpSettings(tester, controller);
    await _enterFieldText(
      tester,
      const Key('pollingIntervalField'),
      '0',
    );
    await _enterFieldText(
      tester,
      const Key('leaveConfirmSamplesField'),
      '0',
    );
    await _enterFieldText(
      tester,
      const Key('leaveConfirmSecondsField'),
      '0',
    );
    await _invokeSaveButton(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('範囲で入力してください'), findsWidgets);
    expect(controller.updateConfigCalls, 0);
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
