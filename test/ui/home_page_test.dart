import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/ui/home_page.dart';
import 'package:permission_handler/permission_handler.dart';

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

    expect(find.textContaining('境界までの距離'), findsOneWidget);
    expect(find.textContaining('方角'), findsOneWidget);
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
    expect(find.textContaining('方角'), findsOneWidget);
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
      'bottom actions show Load GeoJSON and Read QR code (no Start button)',
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

    expect(find.text('Load GeoJSON'), findsOneWidget);
    expect(find.text('Read QR code'), findsOneWidget);
    expect(find.text('Start monitoring'), findsNothing);
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
      find.textContaining('ARGUS は geofence 監視機能のために location data を使用します。'),
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
}
