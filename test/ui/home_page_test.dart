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
  AppController controller,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: const MaterialApp(home: HomePage()),
    ),
  );
  await tester.pumpAndSettle();
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

  testWidgets('overflow menu opens QR generator page', (tester) async {
    final controller = buildTestController(hasGeoJson: true);

    await _pumpHome(tester, controller);

    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRコードを生成'));
    await tester.pumpAndSettle();

    expect(find.text('QRコードを生成'), findsOneWidget);
    expect(find.text('GeoJSONを選択'), findsOneWidget);
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

  testWidgets('tapping wait-start status starts monitoring when permitted',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      permissionCoordinator: _GrantedPermissionCoordinator(),
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
    await tester.pumpAndSettle();

    expect(locationService.hasStarted, isTrue);
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
  })  : _logs = logs,
        _snapshot = snapshot,
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
