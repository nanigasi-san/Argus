import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
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

    test('stopAlarm suppresses an in-flight resumeAlarm', () async {
      final alarm = _BlockingAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      final resumeFuture = notifier.resumeAlarm();
      await alarm.startEntered.future;

      final stopFuture = notifier.stopAlarm();
      alarm.allowStart.complete();
      await resumeFuture;
      await stopFuture;

      expect(alarm.playCount, 1);
      expect(alarm.stopCount, greaterThanOrEqualTo(1));
      expect(vibration.startCount, 0);
      expect(vibration.stopCount, 1);

      await notifier.resumeAlarm();

      expect(alarm.playCount, 2);
      expect(vibration.startCount, 1);
    });

    test('dismissOuterAlert suppresses notifyOuter alarm resume', () async {
      final notifications = _BlockingLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      final notifyFuture = notifier.notifyOuter();
      await notifications.showEntered.future;

      final dismissFuture = notifier.dismissOuterAlert();
      notifications.allowShow.complete();
      await notifyFuture;
      await dismissFuture;

      expect(notifications.shownIds, [1001]);
      expect(notifications.cancelledIds, [1001]);
      expect(alarm.playCount, 0);
      expect(alarm.stopCount, 1);
      expect(vibration.startCount, 0);
      expect(vibration.stopCount, 1);
    });

    test('setAlarmVolume preserves platform client and clamps volume',
        () async {
      final platform = _RecordingAlarmPlatformClient();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: RingtoneAlarmPlayer(
          platformClient: platform,
          isAndroid: true,
        ),
        vibrationPlayer: FakeVibrationPlayer(),
      );

      notifier.setAlarmVolume(2);
      await notifier.resumeAlarm();

      expect(platform.playVolumes, [1.0]);
    });

    test('RingtoneAlarmPlayer uses injected Android platform client', () async {
      final platform = _RecordingAlarmPlatformClient();
      final player = RingtoneAlarmPlayer(
        volume: -1,
        platformClient: platform,
        isAndroid: true,
      );

      await player.start();
      await player.stop();

      expect(platform.playVolumes, [0.0]);
      expect(platform.stopCount, 1);
    });

    test('MethodChannelAlarmClient sends play and stop methods', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('argus/alarm'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('argus/alarm'), null);
      });

      const client = MethodChannelAlarmClient();
      await client.play(volume: 0.25);
      await client.stop();

      expect(calls.map((call) => call.method), ['play', 'stop']);
      expect(calls.first.arguments, {'volume': 0.25});
    });
  });
}

class _BlockingAlarmPlayer extends FakeAlarmPlayer {
  final Completer<void> startEntered = Completer<void>();
  final Completer<void> allowStart = Completer<void>();

  @override
  Future<void> start() async {
    playCount += 1;
    if (!startEntered.isCompleted) {
      startEntered.complete();
    }
    await allowStart.future;
  }
}

class _BlockingLocalNotificationsClient extends FakeLocalNotificationsClient {
  final Completer<void> showEntered = Completer<void>();
  final Completer<void> allowShow = Completer<void>();

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  ) async {
    shownIds.add(id);
    if (!showEntered.isCompleted) {
      showEntered.complete();
    }
    await allowShow.future;
  }
}

class _RecordingAlarmPlatformClient implements AlarmPlatformClient {
  final List<double> playVolumes = <double>[];
  int stopCount = 0;

  @override
  Future<void> play({required double volume}) async {
    playVolumes.add(volume);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}
