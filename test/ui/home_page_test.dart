import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/io/log_entry.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/ui/home_page.dart';
import 'package:permission_handler/permission_handler.dart';

import '../support/notifier_fakes.dart';
import '../support/platform_mocks.dart';
import '../support/test_doubles.dart';

Future<void> _pumpHome(
  WidgetTester tester,
  AppController controller, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: const HomePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapWaitStart(WidgetTester tester) async {
  final statusTapTarget = find.ancestor(
    of: find.text('スタート待機'),
    matching: find.byType(InkWell),
  );
  await tester.tap(statusTapTarget.first);
}

Future<void> _pumpMonitoringStart(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump();
  }
}

void main() {
  tearDown(() async {
    await clearUrlLauncherMock();
  });

  testWidgets('hides navigation details when not developer and not outer',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.textContaining('境界までの距離'), findsNothing);
  });

  testWidgets('shows navigation details in developer mode', (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      developerMode: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        distanceToBoundaryM: 12.3,
        bearingToBoundaryDeg: 45,
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.textContaining('境界までの距離'), findsWidgets);
    expect(find.textContaining('方角'), findsWidgets);
  });

  testWidgets('shows navigation details when state is OUTER', (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.outer,
        timestamp: DateTime.utc(2024, 1, 1),
        distanceToBoundaryM: 5,
        bearingToBoundaryDeg: 180,
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.textContaining('境界までの距離'), findsOneWidget);
    expect(find.text('方角: 180度 (南)'), findsOneWidget);
  });

  testWidgets('labels cached OUTER guidance when GPS accuracy is poor',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.outer,
        timestamp: DateTime.utc(2024, 1, 1),
        horizontalAccuracyM: 100,
        distanceToBoundaryM: 5,
        bearingToBoundaryDeg: 180,
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(
      find.byKey(const Key('low-accuracy-navigation-warning')),
      findsOneWidget,
    );
    expect(find.textContaining('最後に精度が良かった位置'), findsOneWidget);
    expect(find.text('方角: 180度 (南)'), findsOneWidget);
  });

  testWidgets('shows reconnecting lifecycle and force-close warning',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      monitoringLifecycle: MonitoringLifecycle.reconnecting,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.text('再接続中'), findsOneWidget);
    expect(find.text('RECONNECTING'), findsOneWidget);
    expect(find.byKey(const Key('force-close-warning')), findsOneWidget);
    expect(find.byKey(const Key('finish-race-button')), findsOneWidget);
    expect(find.text('ファイルを\n読み込む'), findsNothing);
  });

  testWidgets('shows stopping and failed lifecycle states', (tester) async {
    final stoppingController = buildTestController(
      hasGeoJson: true,
      monitoringLifecycle: MonitoringLifecycle.stopping,
    );

    await _pumpHome(tester, stoppingController);

    expect(find.text('停止中'), findsOneWidget);
    expect(find.text('STOPPING'), findsOneWidget);

    final failedController = buildTestController(
      hasGeoJson: true,
      monitoringLifecycle: MonitoringLifecycle.failed,
    );

    await _pumpHome(tester, failedController);

    expect(find.text('開始失敗'), findsOneWidget);
    expect(find.text('FAILED'), findsOneWidget);
  });

  testWidgets('shows snooze button only while OUTER', (tester) async {
    final outerController = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.outer,
        timestamp: DateTime.utc(2024, 1, 1),
        distanceToBoundaryM: 5,
        bearingToBoundaryDeg: 180,
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, outerController);
    expect(find.text('1分間音を停止する'), findsOneWidget);

    final innerController = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        distanceToBoundaryM: 5,
        bearingToBoundaryDeg: 180,
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, innerController);
    expect(find.text('1分間音を停止する'), findsNothing);
  });

  testWidgets('snooze button disables while keeping navigation visible',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.outer,
        timestamp: DateTime.utc(2024, 1, 1),
        distanceToBoundaryM: 5,
        bearingToBoundaryDeg: 180,
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    await tester.ensureVisible(find.text('1分間音を停止する'));
    await tester.tap(find.text('1分間音を停止する'));
    await tester.pump();

    expect(find.text('1分間ミュート中'), findsOneWidget);
    expect(find.textContaining('境界までの距離'), findsOneWidget);
    expect(find.textContaining('方角'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is FilledButton && widget.onPressed == null,
      ),
      findsOneWidget,
    );

    controller.dispose();
  });

  testWidgets('shows file name row above circle after loading via picker',
      (tester) async {
    final controller = buildTestController(hasGeoJson: false);
    await _pumpHome(tester, controller);

    // 初期は未ロードでファイル名は '-' 表示
    expect(find.textContaining('ファイル名:'), findsOneWidget);
    expect(find.textContaining('ファイル名: -'), findsOneWidget);

    // 画像のFakeFileManagerは test_square.geojson を返す
    await controller.reloadGeoJsonFromPicker();
    await tester.pumpAndSettle();

    // ファイル名行が更新され、Chipは使わない
    expect(find.textContaining('ファイル名:'), findsOneWidget);
    expect(find.textContaining('ファイル名: -'), findsNothing);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets(
      'bottom actions show file loader and QR camera buttons (no Start button)',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.text('ファイルを\n読み込む'), findsOneWidget);
    expect(find.text('QRコードを\n読み込む'), findsOneWidget);
    expect(find.text('Created by Kaito YAMADA'), findsOneWidget);
    expect(find.text('Special thanks for K.M, R.M'), findsOneWidget);
    expect(
      find.text('お問い合わせ: yamada.orien@gmail.com'),
      findsOneWidget,
    );
    expect(find.text('Start monitoring'), findsNothing);
    expect(find.text('長押しでレース終了'), findsNothing);
  });

  testWidgets('bottom actions show file loaders while waiting for GeoJSON',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: false,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitGeoJson,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.text('ファイルを\n読み込む'), findsOneWidget);
    expect(find.text('QRコードを\n読み込む'), findsOneWidget);
    expect(find.text('長押しでレース終了'), findsNothing);
  });

  testWidgets('bottom actions show only finish button while monitoring',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.text('ファイルを\n読み込む'), findsNothing);
    expect(find.text('QRコードを\n読み込む'), findsNothing);
    expect(find.text('長押しでレース終了'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('finish-race-button'))).dy,
      greaterThan(tester.getTopLeft(find.text('内側')).dy),
    );
  });

  testWidgets('finish button requires a full 5 second hold', (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );
    final locationService = controller.locationService as FakeLocationService;

    await _pumpHome(tester, controller);
    await tester.ensureVisible(find.text('長押しでレース終了'));
    final finishButton = find.byKey(const Key('finish-race-button'));

    final shortPress = await tester.startGesture(
      tester.getCenter(finishButton),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('finish-race-progress-fill')), findsOneWidget);
    await shortPress.up();
    await tester.pumpAndSettle();

    expect(locationService.hasStopped, isFalse);
    expect(find.text('長押しでレース終了'), findsOneWidget);

    final fullHold = await tester.startGesture(
      tester.getCenter(finishButton),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    await fullHold.up();
    await tester.pumpAndSettle();

    expect(locationService.hasStopped, isTrue);
    expect(find.text('スタート待機'), findsOneWidget);
    expect(find.text('ファイルを\n読み込む'), findsOneWidget);
    expect(find.text('QRコードを\n読み込む'), findsOneWidget);
  });

  testWidgets('contact link shows snackbar when mail app cannot open',
      (tester) async {
    await mockUrlLauncher(launchResult: false);
    final controller = buildTestController(hasGeoJson: true);

    await _pumpHome(tester, controller);
    await tester.ensureVisible(find.text('お問い合わせ: yamada.orien@gmail.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('お問い合わせ: yamada.orien@gmail.com'));
    await tester.pumpAndSettle();

    expect(find.text('メールアプリを開けませんでした。'), findsOneWidget);
  });

  testWidgets('file loader opens GeoJSON and QR image choices', (tester) async {
    final controller = buildTestController(hasGeoJson: true);

    await _pumpHome(tester, controller);

    await tester.ensureVisible(find.text('ファイルを\n読み込む'));
    await tester.tap(find.text('ファイルを\n読み込む'));
    await tester.pumpAndSettle();

    expect(find.text('GeoJSONファイルを読み込む'), findsOneWidget);
    expect(find.text('QRコード画像を読み込む'), findsOneWidget);
  });

  testWidgets('file loader GeoJSON choice loads selected file', (tester) async {
    final controller = buildTestController(hasGeoJson: false);

    await _pumpHome(tester, controller);
    expect(find.textContaining('ファイル名: -'), findsOneWidget);

    await tester.ensureVisible(find.text('ファイルを\n読み込む'));
    await tester.tap(find.text('ファイルを\n読み込む'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GeoJSONファイルを読み込む'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(controller.geoJsonLoaded, isTrue);
    expect(find.textContaining('ファイル名: test_square.geojson'), findsOneWidget);
  });

  testWidgets('file loader QR image choice decodes selected image',
      (tester) async {
    String? analyzedPath;
    final controller = buildTestController(
      hasGeoJson: false,
      qrImageAnalyzer: (path) async {
        analyzedPath = path;
        return 'invalid:qr';
      },
    );

    await _pumpHome(tester, controller);

    await tester.ensureVisible(find.text('ファイルを\n読み込む'));
    await tester.tap(find.text('ファイルを\n読み込む'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRコード画像を読み込む'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(analyzedPath, 'qr.png');
    expect(controller.geoJsonLoaded, isFalse);
  });

  testWidgets('overflow menu shows QR generation notice before generator',
      (tester) async {
    final controller = buildTestController(hasGeoJson: true);

    await _pumpHome(tester, controller);

    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRコードを生成'));
    await tester.pumpAndSettle();

    expect(find.text('大会でのご利用について'), findsOneWidget);
    expect(find.text('大会での利用の際はご相談ください。'), findsOneWidget);
    expect(find.text('このまま生成'), findsOneWidget);
    expect(find.text('お問い合わせ'), findsOneWidget);

    await tester.tap(find.text('このまま生成'));
    await tester.pumpAndSettle();

    expect(find.text('QRコードを生成'), findsOneWidget);
    expect(find.text('GeoJSONを選択'), findsOneWidget);
  });

  testWidgets('QR generation notice opens contact page', (tester) async {
    final calls = await mockUrlLauncher(launchResult: true);
    final controller = buildTestController(hasGeoJson: true);

    await _pumpHome(tester, controller);
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRコードを生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('お問い合わせ'));
    await tester.pumpAndSettle();

    expect(
      calls.any((call) => call.arguments
          .toString()
          .contains('https://argus-lp.vercel.app/contact')),
      isTrue,
    );
    expect(find.text('GeoJSONを選択'), findsNothing);
  });

  testWidgets('QR generation notice reports contact page launch failure',
      (tester) async {
    await mockUrlLauncher(launchResult: false);
    final controller = buildTestController(hasGeoJson: true);

    await _pumpHome(tester, controller);
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRコードを生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('お問い合わせ'));
    await tester.pumpAndSettle();

    expect(find.text('お問い合わせページを開けませんでした。'), findsOneWidget);
  });

  testWidgets(
      'tapping start opens background disclosure when always permission is missing',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        geoJsonLoaded: true,
      ),
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.granted,
        locationAlwaysStatus: PermissionStatus.denied,
        locationServicesEnabled: true,
      ),
    );

    await _pumpHome(tester, controller);

    await tester.tap(find.text('スタート待機'));
    await tester.pumpAndSettle();

    expect(find.text('バックグラウンド位置情報の開示'), findsOneWidget);
    expect(find.text('同意して位置情報の設定へ進む'), findsOneWidget);
    expect(
      find.textContaining('ARGUS はジオフェンス監視機能のために位置情報を使用します。'),
      findsOneWidget,
    );
  });

  testWidgets('does not show disclosure automatically on launch',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.granted,
        locationAlwaysStatus: PermissionStatus.denied,
        locationServicesEnabled: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.text('バックグラウンド位置情報の開示'), findsNothing);
  });

  testWidgets('permission card setup action opens disclosure', (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.denied,
        locationWhenInUseStatus: PermissionStatus.granted,
        locationAlwaysStatus: PermissionStatus.denied,
        locationServicesEnabled: true,
      ),
    );

    await _pumpHome(tester, controller);
    await tester.tap(find.text('監視開始前に設定する'));
    await tester.pumpAndSettle();

    expect(find.text('バックグラウンド位置情報の開示'), findsOneWidget);
  });

  testWidgets('iOS permission card opens settings only after user action',
      (tester) async {
    final coordinator = _SettingsPermissionCoordinator();
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: coordinator,
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.permanentlyDenied,
        locationAlwaysStatus: PermissionStatus.permanentlyDenied,
        locationServicesEnabled: true,
        shouldOfferSettings: true,
      ),
    );

    await _pumpHome(tester, controller, platform: TargetPlatform.iOS);
    expect(coordinator.openSettingsCount, 0);
    await tester.tap(find.text('アプリ設定を開く'));
    await tester.pumpAndSettle();

    expect(coordinator.openSettingsCount, 1);
  });

  testWidgets('iOS permission settings failure shows guidance', (tester) async {
    final coordinator = _SettingsPermissionCoordinator(result: false);
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: coordinator,
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.permanentlyDenied,
        locationAlwaysStatus: PermissionStatus.permanentlyDenied,
        locationServicesEnabled: true,
        shouldOfferSettings: true,
      ),
    );

    await _pumpHome(tester, controller, platform: TargetPlatform.iOS);
    await tester.tap(find.text('アプリ設定を開く'));
    await tester.pumpAndSettle();

    expect(find.text('アプリ設定を開けませんでした。'), findsOneWidget);
  });

  testWidgets('iOS hides settings before a permission request is denied',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.denied,
        locationAlwaysStatus: PermissionStatus.denied,
        locationServicesEnabled: true,
      ),
    );

    await _pumpHome(tester, controller, platform: TargetPlatform.iOS);

    expect(find.text('監視開始前に設定する'), findsOneWidget);
    expect(find.text('アプリ設定を開く'), findsNothing);
  });

  testWidgets('tapping wait-start status starts monitoring when permitted',
      (tester) async {
    final alarmVolumeClient = RecordingAlarmVolumeClient(
      states: const [
        AlarmVolumeState(current: 5, max: 10, percent: 0.5),
      ],
    );
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: _GrantedPermissionCoordinator(),
      alarmVolumeClient: alarmVolumeClient,
      isAndroid: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );
    final locationService = controller.locationService as FakeLocationService;

    await _pumpHome(tester, controller);
    final statusTapTarget = find.ancestor(
      of: find.text('スタート待機'),
      matching: find.byType(InkWell),
    );
    await tester.tap(statusTapTarget.first);
    await _pumpMonitoringStart(tester);

    expect(locationService.hasStarted, isTrue);
    expect(alarmVolumeClient.checkCount, 1);
    controller.dispose();
  });

  testWidgets('low Android alarm volume blocks monitoring and shows dialog',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: _GrantedPermissionCoordinator(),
      alarmVolumeClient: RecordingAlarmVolumeClient(
        states: const [
          AlarmVolumeState(current: 4, max: 10, percent: 0.4),
        ],
      ),
      isAndroid: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );
    final locationService = controller.locationService as FakeLocationService;

    await _pumpHome(tester, controller);
    await _tapWaitStart(tester);
    await tester.pumpAndSettle();

    expect(locationService.hasStarted, isFalse);
    expect(find.text('アラーム音量が低すぎます'), findsOneWidget);
    expect(
      find.text(
        '端末のアラーム音量が５０％未満です。警報音が聞こえない可能性があるため、５０％以上に上げてから開始してください。',
      ),
      findsOneWidget,
    );
    expect(find.text('音設定を開く'), findsOneWidget);
    expect(find.text('再確認'), findsOneWidget);
    expect(find.text('キャンセル'), findsOneWidget);
  });

  testWidgets('recheck starts monitoring after Android alarm volume is raised',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: _GrantedPermissionCoordinator(),
      alarmVolumeClient: RecordingAlarmVolumeClient(
        states: const [
          AlarmVolumeState(current: 1, max: 10, percent: 0.1),
          AlarmVolumeState(current: 5, max: 10, percent: 0.5),
        ],
      ),
      isAndroid: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );
    final locationService = controller.locationService as FakeLocationService;

    await _pumpHome(tester, controller);
    await _tapWaitStart(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('再確認'));
    await _pumpMonitoringStart(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(locationService.hasStarted, isTrue);
    expect(find.text('アラーム音量が低すぎます'), findsNothing);
    controller.dispose();
  });

  testWidgets('cancel keeps monitoring stopped after low alarm volume',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: _GrantedPermissionCoordinator(),
      alarmVolumeClient: RecordingAlarmVolumeClient(
        states: const [
          AlarmVolumeState(current: 0, max: 10, percent: 0),
        ],
      ),
      isAndroid: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );
    final locationService = controller.locationService as FakeLocationService;

    await _pumpHome(tester, controller);
    await _tapWaitStart(tester);
    await _pumpMonitoringStart(tester);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(locationService.hasStarted, isFalse);
    expect(find.text('アラーム音量が低すぎます'), findsNothing);
  });

  testWidgets('alarm volume check failure does not block monitoring',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: _GrantedPermissionCoordinator(),
      alarmVolumeClient: RecordingAlarmVolumeClient(throwOnCheck: true),
      isAndroid: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );
    final locationService = controller.locationService as FakeLocationService;

    await _pumpHome(tester, controller);
    await _tapWaitStart(tester);
    await _pumpMonitoringStart(tester);

    expect(locationService.hasStarted, isTrue);
    expect(
      controller.logs.any(
        (entry) => entry.message.startsWith('Failed to check alarm volume:'),
      ),
      isTrue,
    );
    controller.dispose();
  });

  testWidgets('non-Android start is not blocked by alarm volume check',
      (tester) async {
    final alarmVolumeClient = RecordingAlarmVolumeClient(
      states: const [
        AlarmVolumeState(current: 0, max: 10, percent: 0),
      ],
    );
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: _GrantedPermissionCoordinator(),
      alarmVolumeClient: alarmVolumeClient,
      isAndroid: false,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );
    final locationService = controller.locationService as FakeLocationService;

    await _pumpHome(tester, controller);
    await _tapWaitStart(tester);
    await tester.pumpAndSettle();

    expect(locationService.hasStarted, isTrue);
    expect(alarmVolumeClient.checkCount, 0);
    controller.dispose();
  });

  testWidgets('sound settings failure shows snackbar', (tester) async {
    final alarmVolumeClient = RecordingAlarmVolumeClient(
      states: const [
        AlarmVolumeState(current: 1, max: 10, percent: 0.1),
      ],
      openResult: false,
    );
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: _GrantedPermissionCoordinator(),
      alarmVolumeClient: alarmVolumeClient,
      isAndroid: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);
    await _tapWaitStart(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('音設定を開く'));
    await tester.pumpAndSettle();

    expect(alarmVolumeClient.openSettingsCount, 1);
    expect(find.text('音設定を開けませんでした。'), findsOneWidget);
  });

  testWidgets('QR action opens scanner page', (tester) async {
    final controller = buildTestController(hasGeoJson: true);

    await _pumpHome(tester, controller);
    await tester.ensureVisible(find.text('QRコードを\n読み込む'));
    await tester.tap(find.text('QRコードを\n読み込む'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('QRコードを読み込む'), findsOneWidget);
  });

  testWidgets('overflow menu opens settings page', (tester) async {
    final controller = buildTestController(hasGeoJson: true);

    await _pumpHome(tester, controller);
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('設定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('設定'), findsWidgets);
    expect(find.text('プライバシーポリシー'), findsOneWidget);
  });

  testWidgets('developer details render logs and nearest boundary point',
      (tester) async {
    final controller = _DisplayOnlyHomeController(
      logs: [
        AppLogEntry.warning(tag: 'WARN', message: 'warn'),
        AppLogEntry.error(tag: 'ERR', message: 'err'),
        AppLogEntry.debug(tag: 'DBG', message: ''),
      ],
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        distanceToBoundaryM: 12,
        horizontalAccuracyM: 3,
        bearingToBoundaryDeg: 45,
        nearestBoundaryPoint: const LatLng(35.123456, 139.654321),
        geoJsonLoaded: true,
        notes: 'note',
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.textContaining('35.12346, 139.65432'), findsOneWidget);
    expect(find.text('(no message)'), findsOneWidget);
    expect(find.text('WARN'), findsOneWidget);
    expect(find.text('ERR'), findsOneWidget);
    expect(find.text('DBG'), findsOneWidget);
  });

  testWidgets('developer details show and clear controller errors',
      (tester) async {
    final controller = _DisplayOnlyHomeController(
      logs: const [],
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
      lastErrorMessage: '監視を開始するには位置情報の使用中許可が必要です。',
      ignoreFirstClear: true,
    );

    await _pumpHome(tester, controller);

    expect(find.text('監視を開始するには位置情報の使用中許可が必要です。'), findsWidgets);

    final errorTile = find.ancestor(
      of: find.text('監視を開始するには位置情報の使用中許可が必要です。'),
      matching: find.byType(ListTile),
    );
    final closeButton = find.descendant(
      of: errorTile,
      matching: find.byType(IconButton),
    );
    expect(closeButton, findsOneWidget);
    await tester.ensureVisible(closeButton);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();

    expect(controller.lastErrorMessage, isNull);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('dismissing file loader sheet leaves controller unchanged',
      (tester) async {
    final controller = buildTestController(hasGeoJson: true);

    await _pumpHome(tester, controller);
    await tester.ensureVisible(find.text('ファイルを\n読み込む'));
    await tester.tap(find.text('ファイルを\n読み込む'));
    await tester.pumpAndSettle();

    expect(find.text('GeoJSONファイルを読み込む'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(controller.geoJsonFileName, isNull);
    expect(find.text('GeoJSONファイルを読み込む'), findsNothing);
  });

  testWidgets('renders remaining status display variants', (tester) async {
    for (final status in <LocationStateStatus>[
      LocationStateStatus.outerPending,
      LocationStateStatus.gpsBad,
      LocationStateStatus.waitGeoJson,
    ]) {
      final controller = buildTestController(
        hasGeoJson: status != LocationStateStatus.waitGeoJson,
        snapshot: StateSnapshot(
          status: status,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: status != LocationStateStatus.waitGeoJson,
        ),
      );

      await _pumpHome(tester, controller);
      expect(find.text(status.name), findsNothing);
    }
  });
}

class _DisplayOnlyHomeController extends AppController {
  _DisplayOnlyHomeController({
    required List<AppLogEntry> logs,
    required StateSnapshot snapshot,
    String? lastErrorMessage,
    bool ignoreFirstClear = false,
  })  : _logs = logs,
        _snapshot = snapshot,
        _lastErrorMessage = lastErrorMessage,
        _ignoreNextClear = ignoreFirstClear,
        super(
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
    debugSeed(config: createTestConfig(), geoJson: createSquareModel());
  }

  final List<AppLogEntry> _logs;
  final StateSnapshot _snapshot;
  String? _lastErrorMessage;
  bool _ignoreNextClear;

  @override
  StateSnapshot get snapshot => _snapshot;

  @override
  bool get developerMode => true;

  @override
  bool get navigationEnabled => true;

  @override
  bool get geoJsonLoaded => true;

  @override
  List<AppLogEntry> get logs => _logs;

  @override
  String? get lastErrorMessage => _lastErrorMessage;

  @override
  void clearError() {
    if (_ignoreNextClear) {
      _ignoreNextClear = false;
      return;
    }
    _lastErrorMessage = null;
    notifyListeners();
  }
}

class _GrantedPermissionCoordinator extends PermissionCoordinator {
  @override
  Future<MonitoringPermissionState> refreshMonitoringPermissionState() async {
    return const MonitoringPermissionState(
      notificationStatus: PermissionStatus.granted,
      locationWhenInUseStatus: PermissionStatus.granted,
      locationAlwaysStatus: PermissionStatus.granted,
      locationServicesEnabled: true,
    );
  }
}

class _SettingsPermissionCoordinator extends PermissionCoordinator {
  _SettingsPermissionCoordinator({this.result = true});

  final bool result;
  int openSettingsCount = 0;

  @override
  Future<bool> openSettings() async {
    openSettingsCount += 1;
    return result;
  }
}
