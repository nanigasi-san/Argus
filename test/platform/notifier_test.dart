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
    test('default constructor provides an initial badge state', () {
      final notifier = Notifier();

      expect(notifier.badgeState.value, LocationStateStatus.waitGeoJson);
    });

    test('alarm preview plays audio without notification or vibration',
        () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.startAlarmPreview();

      expect(notifier.isAlarmPreviewPlaying, isTrue);
      expect(alarm.playCount, 1);
      expect(vibration.startCount, 0);
      expect(notifications.shownIds, isEmpty);

      await notifier.stopAlarmPreview();

      expect(notifier.isAlarmPreviewPlaying, isFalse);
      expect(alarm.stopCount, greaterThanOrEqualTo(2));
      expect(vibration.startCount, 0);
    });

    test('real outer alert replaces an active alarm preview', () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.startAlarmPreview();
      await notifier.notifyOuter();

      expect(notifier.isAlarmPreviewPlaying, isFalse);
      expect(notifications.shownIds, [1001]);
      expect(alarm.playCount, 2);
      expect(vibration.startCount, 1);
    });

    test('failed alarm preview can be stopped and retried', () async {
      final alarm = _FailOnceAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );

      await expectLater(notifier.startAlarmPreview(), throwsStateError);
      expect(notifier.isAlarmPreviewPlaying, isFalse);

      await notifier.startAlarmPreview();

      expect(notifier.isAlarmPreviewPlaying, isTrue);
      expect(alarm.playCount, 2);
    });

    test('stopping an in-flight alarm preview suppresses playback', () async {
      final alarm = _BlockingAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );

      final previewFuture = notifier.startAlarmPreview();
      await alarm.startEntered.future;
      final stopFuture = notifier.stopAlarmPreview();
      alarm.allowStart.complete();
      await Future.wait([previewFuture, stopFuture]);

      expect(notifier.isAlarmPreviewPlaying, isFalse);
      expect(alarm.stopCount, greaterThanOrEqualTo(2));
    });

    test('resumeAlarm replaces an active alarm preview', () async {
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.startAlarmPreview();
      await notifier.resumeAlarm();

      expect(notifier.isAlarmPreviewPlaying, isFalse);
      expect(alarm.playCount, 2);
      expect(vibration.startCount, 1);
    });

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
      final showCall = notifications.showCalls.single;
      expect(showCall.title, 'ARGUS警告');
      expect(showCall.body, '競技エリアから離れています。');
      final androidDetails = showCall.details.android!;
      expect(androidDetails.channelId, 'argus_alerts_visual_v2');
      expect(androidDetails.channelName, 'ARGUS警告');
      expect(androidDetails.channelDescription, 'ジオフェンスの安全エリアから離れたときに通知します。');
      expect(androidDetails.importance, Importance.max);
      expect(androidDetails.priority, Priority.max);
      expect(androidDetails.playSound, isFalse);
      expect(androidDetails.enableVibration, isFalse);
      expect(androidDetails.category, AndroidNotificationCategory.alarm);
      expect(alarm.playCount, 1);
      expect(alarm.stopCount, 0);
      expect(vibration.startCount, 1);
      expect(vibration.stopCount, 0);

      await notifier.notifyRecover();
      expect(notifications.cancelledIds.single, 1001);
      expect(alarm.stopCount, greaterThanOrEqualTo(1));
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

    test('notification failure does not block alarm or vibration', () async {
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: _FailingShowNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      final report = await notifier.notifyOuter();

      expect(report.notificationError, isA<StateError>());
      expect(report.alarmError, isNull);
      expect(report.vibrationError, isNull);
      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);
    });

    test('delivery report summarizes every failed channel', () {
      final report = AlertDeliveryReport(
        notificationError: StateError('notification failed'),
        alarmError: StateError('alarm failed'),
        vibrationError: StateError('vibration failed'),
      );

      expect(report.hasFailures, isTrue);
      expect(report.failureSummary, contains('notification='));
      expect(report.failureSummary, contains('alarm='));
      expect(report.failureSummary, contains('vibration='));
    });

    test('vibration startup and cleanup failures are reported', () async {
      final vibration = _FailingVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: FakeAlarmPlayer(),
        vibrationPlayer: vibration,
      );

      final report = await notifier.notifyOuter();

      expect(report.vibrationError, isA<StateError>());
      expect(vibration.startCount, 1);
      expect(vibration.stopCount, 1);
      await expectLater(notifier.resumeAlarm(), throwsStateError);
    });

    test('alarm failure does not block notification or vibration', () async {
      final notifications = FakeLocalNotificationsClient();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: _FailOnceAlarmPlayer(),
        vibrationPlayer: vibration,
      );

      final report = await notifier.notifyOuter();

      expect(report.notificationError, isNull);
      expect(report.alarmError, isA<StateError>());
      expect(report.vibrationError, isNull);
      expect(notifications.shownIds, [1001]);
      expect(vibration.startCount, 1);

      await notifier.notifyMonitoringStale();

      expect(vibration.pulseCount, 0);
      expect(vibration.stopCount, 0);
    });

    test('monitoring stale notification uses a separate notification id',
        () async {
      final notifications = FakeLocalNotificationsClient();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: FakeAlarmPlayer(),
        vibrationPlayer: vibration,
        monitoringStaleVibrationDuration: const Duration(milliseconds: 350),
      );

      await notifier.notifyMonitoringStale();
      await notifier.clearMonitoringStale();

      expect(notifications.shownIds, [1002]);
      expect(notifications.cancelledIds, [1002]);
      expect(notifications.lastShownDetails?.android?.channelId,
          'argus_monitoring_health_v1');
      expect(notifications.lastShownDetails?.android?.enableVibration, isFalse);
      expect(vibration.pulseCount, 1);
      expect(vibration.pulseDurations, [const Duration(milliseconds: 350)]);
      expect(vibration.startCount, 0);
      expect(vibration.stopCount, 0);
    });

    test('monitoring stale vibration still runs when notification fails',
        () async {
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: _FailingShowNotificationsClient(),
        alarmPlayer: FakeAlarmPlayer(),
        vibrationPlayer: vibration,
        monitoringStaleVibrationDuration: const Duration(milliseconds: 350),
      );

      await expectLater(notifier.notifyMonitoringStale(), throwsStateError);
      expect(vibration.pulseCount, 1);
      expect(vibration.startCount, 0);
      expect(vibration.stopCount, 0);
    });

    test('monitoring health show and clear operations stay ordered', () async {
      final notifications = _BlockingLocalNotificationsClient();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: FakeAlarmPlayer(),
        vibrationPlayer: FakeVibrationPlayer(),
      );

      final showFuture = notifier.notifyMonitoringStale();
      await notifications.showEntered.future;
      final clearFuture = notifier.clearMonitoringStale();
      await Future<void>.delayed(Duration.zero);

      expect(notifications.cancelledIds, isEmpty);

      notifications.allowShow.complete();
      await Future.wait([showFuture, clearFuture]);

      expect(notifications.shownIds, [1002]);
      expect(notifications.cancelledIds, [1002]);
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
      expect(alarm.stopCount, greaterThanOrEqualTo(1));
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

    test('reassertAlarm restarts native playback while already alarming',
        () async {
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.notifyOuter();
      await notifier.reassertAlarm();

      expect(alarm.playCount, 2);
      expect(vibration.stopCount, 1);
      expect(vibration.startCount, 2);
    });

    test('reassertAlarm starts playback when alarm is not active', () async {
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.reassertAlarm();

      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);
    });

    test('stopAlarm suppresses an in-flight alarm reassertion', () async {
      final alarm = _BlockOnSecondStartAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );
      await notifier.notifyOuter();

      final reassertFuture = notifier.reassertAlarm();
      await alarm.secondStartEntered.future;
      final stopFuture = notifier.stopAlarm();
      alarm.allowSecondStart.complete();
      await Future.wait([reassertFuture, stopFuture]);

      expect(alarm.stopCount, greaterThanOrEqualTo(2));
    });

    test('failed reassertion allows a later retry', () async {
      final alarm = _FailSecondStartAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );
      await notifier.notifyOuter();

      await expectLater(notifier.reassertAlarm(), throwsStateError);
      await notifier.reassertAlarm();

      expect(alarm.playCount, 3);
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
      expect(notifications.ensureChannelCount, 2);
      expect(notifications.lastInitializationSettings?.iOS, isNotNull);
      expect(
        notifications.lastInitializationSettings?.iOS?.requestAlertPermission,
        isFalse,
      );
      expect(
        notifications.lastInitializationSettings?.iOS?.requestBadgePermission,
        isFalse,
      );
      expect(
        notifications.lastInitializationSettings?.iOS?.requestSoundPermission,
        isFalse,
      );
      final channel = notifications.channels.first;
      expect(channel.id, 'argus_alerts_visual_v2');
      expect(channel.name, 'ARGUS警告');
      expect(channel.description, 'ジオフェンスの安全エリアから離れたときに通知します。');
      expect(channel.importance, Importance.max);
      expect(channel.playSound, isFalse);
      expect(channel.enableVibration, isFalse);
      expect(channel.sound, isNull);
      final healthChannel = notifications.channels.last;
      expect(healthChannel.id, 'argus_monitoring_health_v1');
      expect(healthChannel.enableVibration, isFalse);
      expect(notifications.calls, [
        'initialize',
        'ensureAndroidChannel',
        'ensureAndroidChannel',
      ]);
      expect(notifier.badgeState.value, LocationStateStatus.near);
    });

    test('notifyOuter uses audible time-sensitive iOS notification', () async {
      final notifications = FakeLocalNotificationsClient();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: FakeAlarmPlayer(),
        vibrationPlayer: FakeVibrationPlayer(),
      );

      await notifier.notifyOuter();

      expect(notifications.lastShownDetails?.android?.playSound, isFalse);
      expect(notifications.lastShownDetails?.android?.sound, isNull);
      expect(notifications.lastShownDetails?.iOS?.presentSound, isFalse);
      expect(
        notifications.lastShownDetails?.iOS?.sound,
        'alarm.caf',
      );
      expect(
        notifications.lastShownDetails?.iOS?.interruptionLevel,
        InterruptionLevel.timeSensitive,
      );
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

    test('notification cancel failure still stops alarm and vibration',
        () async {
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: _FailingCancelNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await expectLater(notifier.dismissOuterAlert(), throwsStateError);

      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);
    });

    test('alarm stop failure still stops vibration', () async {
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: _FailingStopAlarmPlayer(),
        vibrationPlayer: vibration,
      );

      await expectLater(notifier.stopAlarm(), throwsStateError);

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
      expect(vibration.startCount, 1);
      expect(vibration.stopCount, greaterThanOrEqualTo(1));

      await notifier.resumeAlarm();

      expect(alarm.playCount, 2);
      expect(vibration.startCount, 2);
    });

    test('resumeAlarm can retry after playback start fails', () async {
      final alarm = _FailOnceAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await expectLater(notifier.resumeAlarm(), throwsStateError);
      expect(alarm.playCount, 1);
      expect(alarm.stopCount, 1);
      expect(vibration.startCount, 1);
      expect(vibration.stopCount, 0);

      await notifier.resumeAlarm();

      expect(alarm.playCount, 2);
      expect(vibration.startCount, 1);
      expect(vibration.stopCount, 0);
    });

    test('stopAlarm suppresses an in-flight vibration start', () async {
      final alarm = FakeAlarmPlayer();
      final vibration = _BlockingVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      final resumeFuture = notifier.resumeAlarm();
      await vibration.startEntered.future;

      final stopFuture = notifier.stopAlarm();
      vibration.allowStart.complete();
      await resumeFuture;
      await stopFuture;

      expect(alarm.stopCount, greaterThanOrEqualTo(1));
      expect(vibration.stopCount, greaterThanOrEqualTo(2));
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
      expect(notifications.cancelledIds, [1001, 1001]);
      expect(alarm.playCount, 1);
      expect(alarm.stopCount, greaterThanOrEqualTo(1));
      expect(vibration.startCount, 1);
      expect(vibration.stopCount, greaterThanOrEqualTo(1));
    });

    test('stopAlarm suppresses an in-flight resumeAlarm after vibration starts',
        () async {
      final alarm = FakeAlarmPlayer();
      final vibration = _BlockingVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      final resumeFuture = notifier.resumeAlarm();
      await vibration.startEntered.future;

      final stopFuture = notifier.stopAlarm();
      vibration.allowStart.complete();
      await resumeFuture;
      await stopFuture;

      expect(alarm.playCount, 1);
      expect(alarm.stopCount, greaterThanOrEqualTo(1));
      expect(vibration.startCount, 1);
      expect(vibration.stopCount, 2);
    });

    test('setAlarmVolume preserves platform client and clamps volume',
        () async {
      final platform = _RecordingAlarmPlatformClient();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: NativeAlarmPlayer(
          platformClient: platform,
          isAndroid: true,
        ),
        vibrationPlayer: FakeVibrationPlayer(),
      );

      notifier.setAlarmVolume(2);
      await notifier.resumeAlarm();

      expect(platform.playVolumes, [1.0]);
    });

    test('NativeAlarmPlayer uses injected Android platform client', () async {
      final platform = _RecordingAlarmPlatformClient();
      final player = NativeAlarmPlayer(
        volume: -1,
        platformClient: platform,
        isAndroid: true,
      );

      await player.start();
      await player.stop();

      expect(platform.playVolumes, [0.0]);
      expect(platform.stopCount, 1);
    });

    test('NativeAlarmPlayer uses injected iOS platform client', () async {
      final platform = _RecordingAlarmPlatformClient();
      final player = NativeAlarmPlayer(
        volume: 0.4,
        platformClient: platform,
        isAndroid: false,
        isIOS: true,
      );

      await player.start();
      await player.stop();

      expect(platform.playVolumes, [0.4]);
      expect(platform.stopCount, 1);
    });

    test('NativeAlarmPlayer copyWith keeps existing volume when omitted',
        () async {
      final platform = _RecordingAlarmPlatformClient();
      final player = NativeAlarmPlayer(
        volume: 0.4,
        platformClient: platform,
        isAndroid: true,
      ).copyWith();

      await player.start();

      expect(platform.playVolumes, [0.4]);
    });

    test('NativeAlarmPlayer rejects non-mobile playback fallback', () async {
      const player = NativeAlarmPlayer(
        isAndroid: false,
        isIOS: false,
      );

      await expectLater(player.start(), throwsA(isA<UnsupportedError>()));
      await player.stop();
    });

    test('MethodChannelAlarmClient sends alarm channel methods', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('argus/alarm'),
        (call) async {
          calls.add(call);
          if (call.method == 'getAlarmVolumeState') {
            return <String, Object?>{
              'current': 2,
              'max': 10,
              'percent': 0.2,
            };
          }
          if (call.method == 'openSoundSettings') {
            return true;
          }
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
      final volumeState = await client.getAlarmVolumeState();
      final opened = await client.openSoundSettings();

      expect(calls.map((call) => call.method), [
        'play',
        'stopAlarm',
        'getAlarmVolumeState',
        'openSoundSettings',
      ]);
      expect(calls.first.arguments, {'volume': 0.25});
      expect(volumeState.current, 2);
      expect(volumeState.max, 10);
      expect(volumeState.percent, 0.2);
      expect(opened, isTrue);
    });

    test('AlarmVolumeState validates MethodChannel maps', () {
      expect(
        AlarmVolumeState.fromMap(
          const <Object?, Object?>{
            'current': 3,
            'max': 6,
            'percent': 0.5,
          },
        ).percent,
        0.5,
      );
      expect(
        () => AlarmVolumeState.fromMap(
          const <Object?, Object?>{
            'current': 3,
            'max': 6,
          },
        ),
        throwsFormatException,
      );
      expect(
        () => AlarmVolumeState.fromMap(
          const <Object?, Object?>{
            'current': 3.0,
            'max': 6,
            'percent': 0.5,
          },
        ),
        throwsFormatException,
      );
    });

    test('MethodChannel alert diagnostics reports independent channel state',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('argus/alarm'),
        (call) async {
          expect(call.method, 'getAlertPlaybackState');
          return <String, Object?>{
            'alarmActive': false,
            'vibrationPatternActive': true,
          };
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('argus/alarm'), null);
      });

      final state =
          await const MethodChannelAlertDiagnosticsClient().getPlaybackState();

      expect(state.alarmActive, isFalse);
      expect(state.vibrationPatternActive, isTrue);
      expect(
        () => AlertPlaybackState.fromMap(
          const <Object?, Object?>{'alarmActive': true},
        ),
        throwsFormatException,
      );
    });

    test('MethodChannelAlarmClient rejects missing alarm volume state',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('argus/alarm'),
        (call) async {
          if (call.method == 'getAlarmVolumeState') {
            return null;
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('argus/alarm'), null);
      });

      const client = MethodChannelAlarmClient();

      expect(client.getAlarmVolumeState(), throwsFormatException);
    });

    test('MethodChannelAlarmClient returns false when sound settings is null',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('argus/alarm'),
        (call) async => null,
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('argus/alarm'), null);
      });

      const client = MethodChannelAlarmClient();

      expect(await client.openSoundSettings(), isFalse);
    });

    test('MethodChannelVibrationClient sends start, pulse, and stop methods',
        () async {
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

      const client = MethodChannelVibrationClient();
      await client.startPattern();
      await client.pulse(const Duration(milliseconds: 350));
      await client.stop();

      expect(calls.map((call) => call.method), [
        'startVibration',
        'pulseVibration',
        'stopVibration',
      ]);
      expect(calls[1].arguments, {'durationMs': 350});
    });

    test('NativeVibrationPlayer uses injected mobile platform client',
        () async {
      final platform = _RecordingVibrationPlatformClient();
      const nonMobilePlayer = NativeVibrationPlayer(
        isAndroid: false,
        isIOS: false,
      );
      final mobilePlayer = NativeVibrationPlayer(
        platformClient: platform,
        isAndroid: true,
      );

      await nonMobilePlayer.start();
      await nonMobilePlayer.pulse(const Duration(milliseconds: 350));
      await nonMobilePlayer.stop();
      await mobilePlayer.start();
      await mobilePlayer.pulse(const Duration(milliseconds: 350));
      await mobilePlayer.stop();

      expect(platform.startCount, 1);
      expect(platform.pulseCount, 1);
      expect(platform.pulseDurations, [const Duration(milliseconds: 350)]);
      expect(platform.stopCount, 1);
    });

    test('alert diagnostics client can be created at runtime', () {
      final clientFactory = MethodChannelAlertDiagnosticsClient.new;
      final client = clientFactory();

      expect(client, isA<MethodChannelAlertDiagnosticsClient>());
    });
  });

  test('concurrent initialize calls only initialize once', () async {
    // 回帰テスト: _initialized を最後に立てるだけだと、OUTER発報と
    // GPS途絶警告が同時に走ったとき両方が初期化を通過し、プラグイン初期化と
    // チャネル作成が二重に走る。
    final notifications = FakeLocalNotificationsClient();
    final notifier = Notifier(
      notificationsClient: notifications,
      alarmPlayer: FakeAlarmPlayer(),
      vibrationPlayer: FakeVibrationPlayer(),
    );

    await Future.wait<void>([
      notifier.initialize(),
      notifier.initialize(),
      notifier.initialize(),
    ]);

    expect(notifications.initializeCount, 1);
  });

  test('a failed initialize can be retried', () async {
    final notifications = _FailFirstInitializeClient();
    final notifier = Notifier(
      notificationsClient: notifications,
      alarmPlayer: FakeAlarmPlayer(),
      vibrationPlayer: FakeVibrationPlayer(),
    );

    await expectLater(notifier.initialize(), throwsA(isA<StateError>()));
    await notifier.initialize();

    expect(notifications.initializeCount, 2);
  });

  test('a failed stop forces the next alert to restart playback', () async {
    // 回帰テスト: 停止に失敗した経路は再生中フラグを倒さないため、次のOUTERで
    // 「すでに鳴っている」と判断して開始をスキップし、サイレンが鳴らないまま
    // 成功を返してしまう。
    final alarm = _FailStopOnceAlarmPlayer();
    final notifier = Notifier(
      notificationsClient: FakeLocalNotificationsClient(),
      alarmPlayer: alarm,
      vibrationPlayer: FakeVibrationPlayer(),
    );

    await notifier.notifyOuter();
    expect(alarm.playCount, 1);

    // 停止に失敗する。再生中フラグは倒れない。
    await expectLater(notifier.dismissOuterAlert(), throwsA(isA<StateError>()));
    expect(notifier.hasActiveAlertPlayback, isTrue);

    // 次のOUTERは近道を使わず開始し直す。
    final report = await notifier.notifyOuter();
    expect(alarm.playCount, 2);
    expect(report.alarmError, isNull);
  });

  test('formats the outage duration for the warning body', () {
    expect(formatOutageDuration(const Duration(seconds: 45)), '45秒');
    expect(formatOutageDuration(const Duration(minutes: 3)), '3分');
    expect(formatOutageDuration(const Duration(hours: 1)), '1時間');
    expect(
      formatOutageDuration(const Duration(hours: 1, minutes: 30)),
      '1時間30分',
    );
  });

  test('includes the outage duration in the stale warning body', () async {
    final notifications = FakeLocalNotificationsClient();
    final notifier = Notifier(
      notificationsClient: notifications,
      alarmPlayer: FakeAlarmPlayer(),
      vibrationPlayer: FakeVibrationPlayer(),
    );

    await notifier.notifyMonitoringStale();
    expect(notifications.showCalls.last.body, isNot(contains('経過')));

    await notifier.notifyMonitoringStale(outage: const Duration(minutes: 3));
    expect(notifications.showCalls.last.body, contains('3分経過'));
  });

  test('names every failed alert channel in Japanese', () {
    const report = AlertDeliveryReport(
      notificationError: 'a',
      alarmError: 'b',
      vibrationError: 'c',
    );

    expect(report.failedChannelsLabel, '通知・警報音・バイブ');
  });

  test('a failed vibration stop keeps the channel marked as playing', () async {
    final vibration = _FailStopVibrationPlayer();
    final notifier = Notifier(
      notificationsClient: FakeLocalNotificationsClient(),
      alarmPlayer: FakeAlarmPlayer(),
      vibrationPlayer: vibration,
    );

    await notifier.notifyOuter();
    await expectLater(notifier.stopAlarm(), throwsA(isA<StateError>()));

    expect(notifier.hasActiveAlertPlayback, isTrue);
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

class _BlockOnSecondStartAlarmPlayer extends FakeAlarmPlayer {
  final Completer<void> secondStartEntered = Completer<void>();
  final Completer<void> allowSecondStart = Completer<void>();

  @override
  Future<void> start() async {
    playCount += 1;
    if (playCount == 2) {
      secondStartEntered.complete();
      await allowSecondStart.future;
    }
  }
}

class _FailSecondStartAlarmPlayer extends FakeAlarmPlayer {
  @override
  Future<void> start() async {
    playCount += 1;
    if (playCount == 2) {
      throw StateError('reassert failed');
    }
  }
}

class _FailOnceAlarmPlayer extends FakeAlarmPlayer {
  bool _shouldFail = true;

  @override
  Future<void> start() async {
    playCount += 1;
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('playback failed');
    }
  }
}

class _BlockingVibrationPlayer extends FakeVibrationPlayer {
  final Completer<void> startEntered = Completer<void>();
  final Completer<void> allowStart = Completer<void>();

  @override
  Future<void> start() async {
    startCount += 1;
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

class _FailingShowNotificationsClient extends FakeLocalNotificationsClient {
  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  ) {
    throw StateError('notification failed');
  }
}

class _FailingCancelNotificationsClient extends FakeLocalNotificationsClient {
  @override
  Future<void> cancel(int id) {
    throw StateError('cancel failed');
  }
}

class _FailingStopAlarmPlayer extends FakeAlarmPlayer {
  @override
  Future<void> stop() {
    stopCount += 1;
    throw StateError('stop failed');
  }
}

class _FailingVibrationPlayer extends FakeVibrationPlayer {
  @override
  Future<void> start() async {
    startCount += 1;
    throw StateError('vibration start failed');
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    throw StateError('vibration stop failed');
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

class _RecordingVibrationPlatformClient implements VibrationPlatformClient {
  int startCount = 0;
  int pulseCount = 0;
  int stopCount = 0;
  final List<Duration> pulseDurations = <Duration>[];

  @override
  Future<void> startPattern() async {
    startCount += 1;
  }

  @override
  Future<void> pulse(Duration duration) async {
    pulseCount += 1;
    pulseDurations.add(duration);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

class _FailFirstInitializeClient extends FakeLocalNotificationsClient {
  @override
  Future<void> initialize(InitializationSettings settings) async {
    await super.initialize(settings);
    if (initializeCount == 1) {
      throw StateError('initialize failed');
    }
  }
}

class _FailStopOnceAlarmPlayer extends FakeAlarmPlayer {
  @override
  Future<void> stop() async {
    stopCount += 1;
    if (stopCount == 1) {
      throw StateError('alarm stop failed');
    }
  }
}

class _FailStopVibrationPlayer extends FakeVibrationPlayer {
  @override
  Future<void> stop() async {
    stopCount += 1;
    throw StateError('vibration stop failed');
  }
}
