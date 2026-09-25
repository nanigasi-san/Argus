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

  @override
  Future<List<GarminDevice>> getDevices() async => const [
        GarminDevice(id: 'watch-1', name: 'ForeAthlete 55', connected: true),
      ];

  @override
  Future<GarminTransferResult> sendCourse(
      GarminDevice device, GarminCoursePayload payload) {
    sendCount += 1;
    return completion.future;
  }
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
  Future<void> show(int id, String? title, String? body,
      NotificationDetails details) async {
    throw PlatformException(code: 'notification_failed');
  }
}

Future<void> _startTransfer(
  WidgetTester tester,
  _PendingGarminClient client,
  FakeLocalNotificationsClient notifications, {
  bool notificationDenied = false,
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
  await tester.ensureVisible(find.text('GARMINに送信'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('GARMINに送信'));
  await tester.pump();
  expect(client.sendCount, 1);
}

void main() {
  testWidgets('shows a phone notification only after a successful storage ACK',
      (tester) async {
    final client = _PendingGarminClient();
    final notifications = FakeLocalNotificationsClient();
    await _startTransfer(tester, client, notifications);
    expect(notifications.shownIds, isEmpty);

    client.completion.complete(
      const GarminTransferResult(deviceName: 'ForeAthlete 55', elapsedMs: 50),
    );
    await tester.pumpAndSettle();

    expect(find.text('GARMINへ転送しました'), findsOneWidget);
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

  testWidgets('notification failure does not turn a successful transfer into an error',
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
