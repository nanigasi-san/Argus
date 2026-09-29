import 'dart:async';
import 'dart:convert';

import 'package:argus/app_controller.dart';
import 'package:argus/garmin/garmin_course_payload.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/platform/garmin_transfer_client.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/ui/garmin_transfer_page.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../support/notifier_fakes.dart';
import '../support/test_doubles.dart';

class _PendingGarminClient extends GarminTransferClient {
  final Completer<GarminTransferResult> completion =
      Completer<GarminTransferResult>();
  final Completer<GarminTransferResult> resetCompletion =
      Completer<GarminTransferResult>();
  int sendCount = 0;
  int resetCount = 0;
  String? sentDeviceId;

  @override
  Future<List<GarminDevice>> getDevices() async => const [
        GarminDevice(id: 'watch-1', name: 'ForeAthlete 55', connected: true),
      ];

  @override
  Future<GarminTransferResult> sendCourse(
      GarminDevice device, GarminCoursePayload payload) {
    sendCount += 1;
    sentDeviceId = device.id;
    return completion.future;
  }

  @override
  Future<GarminTransferResult> resetMonitoring(GarminDevice device) {
    resetCount += 1;
    sentDeviceId = device.id;
    return resetCompletion.future;
  }
}

class _MultipleGarminClient extends _PendingGarminClient {
  bool secondVisible = true;

  @override
  Future<List<GarminDevice>> getDevices() async => [
        const GarminDevice(id: 'watch-1', name: 'Watch 1', connected: true),
        if (secondVisible)
          const GarminDevice(id: 'watch-2', name: 'Watch 2', connected: true),
      ];
}

class _UnsupportedGarminClient extends GarminTransferClient {
  const _UnsupportedGarminClient();

  @override
  Future<List<GarminDevice>> getDevices() async =>
      throw MissingPluginException();
}

const _deniedNotifications = MonitoringPermissionState(
  notificationStatus: PermissionStatus.denied,
  locationWhenInUseStatus: PermissionStatus.granted,
  locationAlwaysStatus: PermissionStatus.granted,
  locationServicesEnabled: true,
);

class _DeniedPermissionCoordinator extends PermissionCoordinator {
  @override
  Future<MonitoringPermissionState> requestNotificationPermission() async =>
      _deniedNotifications;
}

class _FailingNotifications extends FakeLocalNotificationsClient {
  @override
  Future<void> show(
      int id, String? title, String? body, NotificationDetails details) async {
    throw PlatformException(code: 'notification_failed');
  }
}

class _SelectableFileManager extends FakeFileManager {
  _SelectableFileManager({required super.config});

  XFile? selectedFile;

  @override
  Future<XFile?> pickGeoJsonFile() async => selectedFile;
}

class _GrantedPermissionCoordinator extends PermissionCoordinator {
  @override
  Future<MonitoringPermissionState> refreshMonitoringPermissionState() async =>
      const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.granted,
        locationAlwaysStatus: PermissionStatus.granted,
        locationServicesEnabled: true,
      );
}

const _phoneGeoJson = '''
{"type":"FeatureCollection","features":[{"type":"Feature","properties":{},
"geometry":{"type":"Polygon","coordinates":[[[139,35],[139.001,35],[139,35.001],[139,35]]]}}]}
''';
const _watchGeoJson = '''
{"type":"FeatureCollection","features":[{"type":"Feature","properties":{},
"geometry":{"type":"Polygon","coordinates":[[[140,36],[140.001,36],[140,36.001],[140,36]]]}}]}
''';

Future<
    ({
      AppController controller,
      FakeLocationService location,
      _SelectableFileManager files
    })> _monitoringController() async {
  final config = createTestConfig();
  final files = _SelectableFileManager(config: config);
  final location = FakeLocationService();
  final controller = AppController(
    stateMachine: StateMachine(config: config),
    locationService: location,
    fileManager: files,
    logger: FakeEventLogger(),
    notifier: Notifier(
      notificationsClient: FakeLocalNotificationsClient(),
      alarmPlayer: FakeAlarmPlayer(),
      vibrationPlayer: FakeVibrationPlayer(),
    ),
    permissionCoordinator: _GrantedPermissionCoordinator(),
    compassService: FakeCompassService(),
  );
  controller.debugSeed(
      config: config, geoJson: GeoModel.fromGeoJson(_phoneGeoJson));
  await controller.startMonitoring();
  return (controller: controller, location: location, files: files);
}

Future<void> _startTransfer(
  WidgetTester tester,
  _PendingGarminClient client,
  FakeLocalNotificationsClient notifications, {
  bool notificationDenied = false,
  bool startSending = true,
}) async {
  final controller = buildTestController(
    hasGeoJson: true,
    permissionState: notificationDenied ? _deniedNotifications : null,
    permissionCoordinator:
        notificationDenied ? _DeniedPermissionCoordinator() : null,
    notifier: Notifier(
      notificationsClient: notifications,
      alarmPlayer: FakeAlarmPlayer(),
      vibrationPlayer: FakeVibrationPlayer(),
    ),
  );
  controller.debugSeed(
    geoJson: GeoModel([
      GeoPolygon(points: const [
        LatLng(35, 139),
        LatLng(35, 139.001),
        LatLng(35.001, 139),
      ]),
    ]),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(home: GarminTransferPage(client: client)),
    ),
  );
  await tester.pumpAndSettle();
  if (!startSending) return;
  await tester.ensureVisible(find.text('GARMINに送信'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('GARMINに送信'));
  await tester.pump();
  expect(client.sendCount, 1);
}

Future<void> _selectSecondWatch(WidgetTester tester) async {
  await tester.ensureVisible(find.text('時計を変更'));
  await tester.tap(find.text('時計を変更'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Watch 2 · 接続済み').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancelled Garmin file selection keeps phone monitoring active',
      (tester) async {
    final setup = await _monitoringController();
    addTearDown(setup.controller.dispose);
    expect(setup.controller.isMonitoring, isTrue);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: setup.controller,
      child:
          MaterialApp(home: GarminTransferPage(client: _PendingGarminClient())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ファイルを選ぶ'));
    await tester.pumpAndSettle();
    expect(setup.controller.isMonitoring, isTrue);
    expect(setup.location.hasStopped, isFalse);
    expect(
        setup.controller.geoModel.polygons.single.points.first.longitude, 139);
  });

  testWidgets(
      'invalid Garmin file keeps the previous course and phone monitoring',
      (tester) async {
    final setup = await _monitoringController();
    addTearDown(setup.controller.dispose);
    setup.files.selectedFile = XFile.fromData(
      utf8.encode('{invalid'),
      name: 'bad.geojson',
      mimeType: 'application/geo+json',
    );
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: setup.controller,
      child:
          MaterialApp(home: GarminTransferPage(client: _PendingGarminClient())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ファイルを選ぶ'));
    await tester.pumpAndSettle();
    expect(setup.controller.isMonitoring, isTrue);
    expect(setup.location.hasStopped, isFalse);
    expect(find.text('argus.geojson'), findsOneWidget);
  });

  testWidgets(
      'different Garmin course requires confirmation and leaves phone monitoring unchanged',
      (tester) async {
    final setup = await _monitoringController();
    addTearDown(setup.controller.dispose);
    final client = _PendingGarminClient();
    setup.files.selectedFile = XFile.fromData(
      utf8.encode(_watchGeoJson),
      name: 'watch.geojson',
      path: 'watch.geojson',
      mimeType: 'application/geo+json',
    );
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: setup.controller,
      child: MaterialApp(home: GarminTransferPage(client: client)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ファイルを選ぶ'));
    await tester.pumpAndSettle();
    expect(find.text('watch.geojson'), findsOneWidget);
    await tester.ensureVisible(find.text('GARMINに送信'));
    await tester.tap(find.text('GARMINに送信'));
    await tester.pumpAndSettle();
    expect(find.text('スマホと異なる範囲を送りますか？'), findsOneWidget);
    expect(client.sendCount, 0);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(client.sendCount, 0);
    expect(setup.controller.isMonitoring, isTrue);
    await tester.tap(find.text('GARMINに送信'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'GARMINへ送信'));
    await tester.pump();
    expect(client.sendCount, 1);
    expect(setup.controller.isMonitoring, isTrue);
    expect(setup.location.hasStopped, isFalse);
    expect(
        setup.controller.geoModel.polygons.single.points.first.longitude, 139);
    client.completion.complete(
      const GarminTransferResult(deviceName: 'ForeAthlete 55', elapsedMs: 50),
    );
    await tester.pumpAndSettle();
    expect(find.text('GARMINへ転送しました'), findsOneWidget);
  });

  testWidgets('keeps the selected watch after refresh and app resume',
      (tester) async {
    final client = _MultipleGarminClient();
    await _startTransfer(tester, client, FakeLocalNotificationsClient(),
        startSending: false);
    await _selectSecondWatch(tester);

    await tester.tap(find.text('再検索'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('GARMINに送信'));
    await tester.tap(find.text('GARMINに送信'));
    await tester.pump();
    expect(client.sentDeviceId, 'watch-2');
    client.completion.complete(
      const GarminTransferResult(deviceName: 'Watch 2', elapsedMs: 50),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('does not switch to another watch when selection disappears',
      (tester) async {
    final client = _MultipleGarminClient();
    await _startTransfer(tester, client, FakeLocalNotificationsClient(),
        startSending: false);
    await _selectSecondWatch(tester);

    client.secondVisible = false;
    await tester.tap(find.text('再検索'));
    await tester.pumpAndSettle();
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'GARMINに送信'),
    );
    expect(sendButton.onPressed, isNull);
    expect(find.text('選択したGARMINが見つかりません。送信先を選び直してください。'), findsOneWidget);
    expect(client.sendCount, 0);

    client.secondVisible = true;
    await tester.tap(find.text('再検索'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('GARMINに送信'));
    await tester.tap(find.text('GARMINに送信'));
    await tester.pump();
    expect(client.sentDeviceId, 'watch-2');
    client.completion.complete(
      const GarminTransferResult(deviceName: 'Watch 2', elapsedMs: 50),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('explains when Garmin transfer is unavailable on this platform',
      (tester) async {
    final controller = buildTestController(hasGeoJson: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: GarminTransferPage(client: _UnsupportedGarminClient()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('この端末ではGARMINへの送信を利用できません。'), findsOneWidget);
  });

  testWidgets('shows a phone notification only after a successful storage ACK',
      (tester) async {
    final client = _PendingGarminClient();
    final notifications = FakeLocalNotificationsClient();
    await _startTransfer(tester, client, notifications);
    expect(notifications.shownIds, isEmpty);
    expect(find.text('GARMINのACKを待機中'), findsOneWidget);
    expect(find.byKey(const Key('garmin-ack-progress')), findsOneWidget);
    expect(find.text('保存・照合の確認中です。通信開始から最大60秒待ちます。'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('GARMINのACKを待機中'), findsOneWidget);
    expect(notifications.shownIds, isEmpty);

    client.completion.complete(
      const GarminTransferResult(deviceName: 'ForeAthlete 55', elapsedMs: 50),
    );
    await tester.pumpAndSettle();

    expect(find.text('GARMINへ転送しました'), findsOneWidget);
    expect(find.text('GARMINのACKを待機中'), findsNothing);
    expect(find.byKey(const Key('garmin-ack-progress')), findsNothing);
    expect(notifications.shownIds, [1002]);
    expect(notifications.showCalls.single.body,
        'ForeAthlete 55にargus.geojsonを保存しました。');
  });

  testWidgets('does not notify when GARMIN transfer fails', (tester) async {
    final client = _PendingGarminClient();
    final notifications = FakeLocalNotificationsClient();
    await _startTransfer(tester, client, notifications);

    client.completion.completeError(
      PlatformException(code: 'ack_timeout', message: 'ACKを受信できませんでした。'),
    );
    await tester.pumpAndSettle();

    expect(notifications.shownIds, isEmpty);
    expect(find.text('ACKを受信できませんでした。'), findsOneWidget);
    expect(find.text('GARMINのACKを待機中'), findsNothing);
    expect(find.byKey(const Key('garmin-ack-progress')), findsNothing);
  });

  testWidgets('stops monitoring only after confirmation and watch ACK',
      (tester) async {
    final client = _PendingGarminClient();
    await _startTransfer(tester, client, FakeLocalNotificationsClient(),
        startSending: false);
    await tester.scrollUntilVisible(find.text('GARMINの監視を停止'), 200);
    await tester.tap(find.text('GARMINの監視を停止'));
    await tester.pumpAndSettle();
    expect(client.resetCount, 0);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(client.resetCount, 0);

    await tester.tap(find.text('GARMINの監視を停止'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('監視を停止'));
    await tester.pump();
    expect(client.resetCount, 1);
    expect(find.text('GARMINのACKを待機中'), findsOneWidget);
    client.resetCompletion.complete(const GarminTransferResult(
        deviceName: 'ForeAthlete 55', elapsedMs: 50));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('GARMINの監視を停止しました'), -200);
    expect(find.text('GARMINの監視を停止しました'), findsOneWidget);
    expect(find.text('時計の範囲データを削除しました。再開には再送信してください。'), findsOneWidget);
  });

  testWidgets('allows reset without loading a GeoJSON file', (tester) async {
    final client = _PendingGarminClient();
    final controller = buildTestController(hasGeoJson: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(home: GarminTransferPage(client: client)),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('GARMINの監視を停止'), 200);
    await tester.tap(find.text('GARMINの監視を停止'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('監視を停止'));
    await tester.pump();
    expect(client.resetCount, 1);
    client.resetCompletion.complete(const GarminTransferResult(
        deviceName: 'ForeAthlete 55', elapsedMs: 50));
    await tester.pumpAndSettle();
    expect(find.text('GARMINの監視を停止しました'), findsOneWidget);
  });

  testWidgets('can stop monitoring directly from the transfer success screen',
      (tester) async {
    final client = _PendingGarminClient();
    await _startTransfer(tester, client, FakeLocalNotificationsClient());
    client.completion.complete(const GarminTransferResult(
        deviceName: 'ForeAthlete 55', elapsedMs: 50));
    await tester.pumpAndSettle();
    expect(find.text('GARMINへ転送しました'), findsOneWidget);
    await tester.tap(find.text('GARMINの監視を停止'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('監視を停止'));
    await tester.pump();
    expect(client.resetCount, 1);
    client.resetCompletion.complete(const GarminTransferResult(
        deviceName: 'ForeAthlete 55', elapsedMs: 50));
    await tester.pumpAndSettle();
    expect(find.text('GARMINの監視を停止しました'), findsOneWidget);
    expect(find.text('GARMINへ転送しました'), findsNothing);
  });

  testWidgets(
      'transfer succeeds without a notification when permission is denied',
      (tester) async {
    final client = _PendingGarminClient();
    final notifications = FakeLocalNotificationsClient();
    await _startTransfer(tester, client, notifications,
        notificationDenied: true);

    client.completion.complete(
      const GarminTransferResult(deviceName: 'ForeAthlete 55', elapsedMs: 50),
    );
    await tester.pumpAndSettle();

    expect(find.text('GARMINへ転送しました'), findsOneWidget);
    expect(notifications.shownIds, isEmpty);
    expect(find.text('通知権限がないため、スマホの送信完了通知は表示されません。'), findsOneWidget);
  });

  testWidgets(
      'notification failure does not turn a successful transfer into an error',
      (tester) async {
    final client = _PendingGarminClient();
    final notifications = _FailingNotifications();
    await _startTransfer(tester, client, notifications);

    client.completion.complete(
      const GarminTransferResult(deviceName: 'ForeAthlete 55', elapsedMs: 50),
    );
    await tester.pumpAndSettle();

    expect(find.text('GARMINへ転送しました'), findsOneWidget);
    expect(find.text('転送は完了しましたが、スマホ通知を表示できませんでした。'), findsOneWidget);
  });
}
