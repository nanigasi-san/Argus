import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:argus/platform/notifier.dart';
import '../support/notifier_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notifier', () {
    test('outer -> inner -> outer toggles alarm playback', () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.notifyOuter();
      expect(notifications.shownIds.single, 1001);
      expect(alarm.playCount, 1);
      expect(alarm.stopCount, 0);
      expect(vibration.startCount, 1);
      expect(vibration.stopCount, 0);

      await notifier.notifyRecover();
      expect(notifications.cancelledIds.single, 1001);
      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);

      await notifier.notifyOuter();
      expect(alarm.playCount, 2);
      expect(vibration.startCount, 2);
    });

    test('initializes with iOS settings without requesting permissions',
        () async {
      final notifications = FakeLocalNotificationsClient();
      final notifier = Notifier(
        notificationsClient: notifications,
        targetPlatform: TargetPlatform.iOS,
      );

      await notifier.initialize();

      expect(notifications.initialized, isTrue);
      expect(notifications.lastInitSettings, isNotNull);
      expect(notifications.lastInitSettings!.iOS, isNotNull);
      expect(
        notifications.lastInitSettings!.iOS!.requestAlertPermission,
        isFalse,
      );
      expect(
        notifications.lastInitSettings!.iOS!.requestBadgePermission,
        isFalse,
      );
      expect(
        notifications.lastInitSettings!.iOS!.requestSoundPermission,
        isFalse,
      );
      expect(
        notifications.lastInitSettings!.iOS!.requestCriticalPermission,
        isFalse,
      );
      expect(notifications.lastChannel, isNull);
    });

    test('creates Android channel only on Android', () async {
      final notifications = FakeLocalNotificationsClient();
      final notifier = Notifier(
        notificationsClient: notifications,
        targetPlatform: TargetPlatform.android,
      );

      await notifier.initialize();

      expect(notifications.lastChannel, isNotNull);
    });

    test('uses time-sensitive alerts on iOS unless critical alerts are enabled',
        () async {
      final notifications = FakeLocalNotificationsClient();
      final notifier = Notifier(
        notificationsClient: notifications,
        targetPlatform: TargetPlatform.iOS,
      );

      await notifier.notifyOuter();

      expect(
        notifications.lastNotificationDetails?.iOS?.interruptionLevel,
        InterruptionLevel.timeSensitive,
      );

      final criticalNotifications = FakeLocalNotificationsClient();
      final criticalNotifier = Notifier(
        notificationsClient: criticalNotifications,
        targetPlatform: TargetPlatform.iOS,
        enableCriticalAlerts: true,
      );

      await criticalNotifier.notifyOuter();

      expect(
        criticalNotifications.lastNotificationDetails?.iOS?.interruptionLevel,
        InterruptionLevel.critical,
      );
    });
  });
}
