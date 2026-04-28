import 'package:flutter_test/flutter_test.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/state_machine/state.dart';
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

    test('notifyOuter is idempotent and initialize requested once', () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      // 初回の外出通知
      await notifier.notifyOuter();
      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);

      // 連続で呼んでも2重に開始されない（冪等）
      await notifier.notifyOuter();
      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);

      // 通知権限は PermissionCoordinator 側の責務に移したため、Notifier は要求しない
      expect(notifications.initialized, true);
      expect(notifications.requestedPermissions, false);

      // 復帰→再度外出で再開する
      await notifier.notifyRecover();
      await notifier.notifyOuter();
      expect(alarm.playCount, 2);
      expect(vibration.startCount, 2);
    });

    test('resumeAlarm restarts playback without showing another notification',
        () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.notifyOuter();
      expect(notifications.shownIds, [1001]);
      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);

      await notifier.stopAlarm();
      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);

      await notifier.resumeAlarm();
      expect(notifications.shownIds, [1001]);
      expect(alarm.playCount, 2);
      expect(vibration.startCount, 2);
    });

    test('resumeAlarm is idempotent while already alarming', () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.resumeAlarm();
      await notifier.resumeAlarm();

      expect(notifications.shownIds, isEmpty);
      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);
    });

    test('dismissOuterAlert cancels notification and stops alarm', () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.notifyOuter();
      await notifier.dismissOuterAlert();

      expect(notifications.cancelledIds, [1001]);
      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);
    });

    test('initialize is idempotent and updates badge state', () async {
      final notifications = FakeLocalNotificationsClient();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: FakeAlarmPlayer(),
        vibrationPlayer: FakeVibrationPlayer(),
      );

      await notifier.initialize();
      await notifier.initialize();
      await notifier.updateBadge(LocationStateStatus.near);

      expect(notifications.initializeCount, 1);
      expect(notifications.ensureChannelCount, 1);
      expect(notifier.badgeState.value, LocationStateStatus.near);
    });

    test('stopAlarm always asks native players to stop', () async {
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.stopAlarm();

      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);
    });

    test('dismissOuterAlert stops native players even when not marked alarming',
        () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.dismissOuterAlert();

      expect(notifications.cancelledIds, [1001]);
      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);
    });
  });
}
