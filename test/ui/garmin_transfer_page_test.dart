import 'dart:async';

import 'package:argus/garmin/garmin_course_payload.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/platform/garmin_transfer_client.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/ui/garmin_transfer_page.dart';
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
  int sendCount = 0;
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
  await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Watch 2 · 接続済み').last);
  await tester.pumpAndSettle();
}

void main() {
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
