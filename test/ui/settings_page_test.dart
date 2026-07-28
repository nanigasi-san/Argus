import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:argus/io/config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
  TargetPlatform platform = TargetPlatform.android,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: SettingsPage(key: UniqueKey()),
      ),
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
    PackageInfo.setMockInitialValues(
      appName: 'ARGUS',
      packageName: 'com.argus.orienteering',
      version: '0.4.1',
      buildNumber: '1005',
      buildSignature: '',
    );
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
    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('appVersionLabel')),
    );
    expect(find.text('バージョン 0.4.1 (1005)'), findsOneWidget);
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

  testWidgets('iOS permission card opens settings only after user taps it',
      (tester) async {
    final controller = _RecordingSettingsController(
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.permanentlyDenied,
        locationAlwaysStatus: PermissionStatus.permanentlyDenied,
        locationServicesEnabled: true,
        shouldOfferSettings: true,
      ),
    );

    await _pumpSettings(
      tester,
      controller,
      platform: TargetPlatform.iOS,
    );

    expect(controller.openPermissionSettingsCalls, 0);
    await tester.tap(find.text('アプリ設定を開く'));
    await tester.pumpAndSettle();

    expect(controller.openPermissionSettingsCalls, 1);
  });

  testWidgets('iOS permission settings failure shows guidance', (tester) async {
    final controller = _RecordingSettingsController(
      openPermissionSettingsResult: false,
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.permanentlyDenied,
        locationAlwaysStatus: PermissionStatus.permanentlyDenied,
        locationServicesEnabled: true,
        shouldOfferSettings: true,
      ),
    );

    await _pumpSettings(
      tester,
      controller,
      platform: TargetPlatform.iOS,
    );
    await tester.tap(find.text('アプリ設定を開く'));
    await tester.pumpAndSettle();

    expect(find.text('アプリ設定を開けませんでした。'), findsOneWidget);
  });

  testWidgets('iOS alarm preview toggles and stops when settings closes',
      (tester) async {
    final controller = _RecordingSettingsController();

    await _pumpSettings(
      tester,
      controller,
      platform: TargetPlatform.iOS,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('alarmPreviewButton')),
    );

    await tester.tap(find.byKey(const Key('alarmPreviewButton')));
    await tester.pumpAndSettle();
    expect(controller.isAlarmPreviewPlaying, isTrue);
    expect(find.text('テストを停止'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(controller.isAlarmPreviewPlaying, isFalse);
  });

  testWidgets('iOS alarm preview can be stopped with the same action',
      (tester) async {
    final controller = _RecordingSettingsController();

    await _pumpSettings(tester, controller, platform: TargetPlatform.iOS);
    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('alarmPreviewButton')),
    );
    await tester.tap(find.byKey(const Key('alarmPreviewButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('alarmPreviewButton')));
    await tester.pumpAndSettle();

    expect(controller.isAlarmPreviewPlaying, isFalse);
  });

  testWidgets('iOS alarm preview failure shows guidance', (tester) async {
    final controller = _RecordingSettingsController(
      alarmPreviewStartResult: false,
    );

    await _pumpSettings(tester, controller, platform: TargetPlatform.iOS);
    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('alarmPreviewButton')),
    );
    await tester.tap(find.byKey(const Key('alarmPreviewButton')));
    await tester.pumpAndSettle();

    expect(find.text('警告音を再生できませんでした。'), findsOneWidget);
  });

  testWidgets('saving settings stops an active alarm preview', (tester) async {
    final controller = _RecordingSettingsController();

    await _pumpSettings(tester, controller, platform: TargetPlatform.iOS);
    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('alarmPreviewButton')),
    );
    await tester.tap(find.byKey(const Key('alarmPreviewButton')));
    await tester.pumpAndSettle();
    expect(controller.isAlarmPreviewPlaying, isTrue);

    await _invokeSaveButton(tester);

    expect(controller.isAlarmPreviewPlaying, isFalse);
  });

  testWidgets('active preview remains stoppable when monitoring is unavailable',
      (tester) async {
    final controller = _RecordingSettingsController(
      reportPreviewPlaying: true,
      reportCanPreview: false,
    );

    await _pumpSettings(tester, controller, platform: TargetPlatform.iOS);
    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('alarmPreviewButton')),
    );

    expect(find.text('テストを停止'), findsOneWidget);
    expect(find.textContaining('ホーム画面へ移動しても'), findsOneWidget);
  });

  testWidgets('Android settings does not show the iOS alarm preview action',
      (tester) async {
    final controller = _RecordingSettingsController();

    await _pumpSettings(tester, controller);

    expect(find.byKey(const Key('alarmPreviewButton')), findsNothing);
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
  _RecordingSettingsController({
    this.openPermissionSettingsResult = true,
    this.alarmPreviewStartResult = true,
    this.reportPreviewPlaying,
    this.reportCanPreview,
    this.permissionState = const MonitoringPermissionState(
      notificationStatus: PermissionStatus.granted,
      locationWhenInUseStatus: PermissionStatus.granted,
      locationAlwaysStatus: PermissionStatus.granted,
      locationServicesEnabled: true,
    ),
  }) : super(
          stateMachine: StateMachine(config: createTestConfig()),
          locationService: FakeLocationService(),
          fileManager: FakeFileManager(config: createTestConfig()),
          logger: FakeEventLogger(),
          notifier: Notifier(
            notificationsClient: FakeLocalNotificationsClient(),
            alarmPlayer: FakeAlarmPlayer(),
            vibrationPlayer: FakeVibrationPlayer(),
          ),
        ) {
    debugSeed(
      config: createTestConfig(),
      permissionState: permissionState,
    );
  }
  final bool openPermissionSettingsResult;
  final bool alarmPreviewStartResult;
  final bool? reportPreviewPlaying;
  final bool? reportCanPreview;
  final MonitoringPermissionState permissionState;
  AppConfig? savedConfig;
  Object? updateConfigError;
  int updateConfigCalls = 0;
  int openPermissionSettingsCalls = 0;

  @override
  bool get isAlarmPreviewPlaying =>
      reportPreviewPlaying ?? super.isAlarmPreviewPlaying;

  @override
  bool get canPreviewAlarm => reportCanPreview ?? super.canPreviewAlarm;

  @override
  Future<bool> startAlarmPreview(double volume) async {
    if (!alarmPreviewStartResult) {
      return false;
    }
    return super.startAlarmPreview(volume);
  }

  @override
  Future<bool> openPermissionSettings() async {
    openPermissionSettingsCalls += 1;
    return openPermissionSettingsResult;
  }

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
