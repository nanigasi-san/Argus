import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';

import '../state_machine/state.dart';

class Notifier {
  Notifier({
    FlutterLocalNotificationsPlugin? plugin,
    LocalNotificationsClient? notificationsClient,
    AlarmPlayer? alarmPlayer,
    VibrationPlayer? vibrationPlayer,
  })  : _notifications = notificationsClient ??
            FlutterLocalNotificationsClient(
              plugin ?? FlutterLocalNotificationsPlugin(),
            ),
        _alarmPlayer = alarmPlayer ?? const RingtoneAlarmPlayer(),
        _vibrationPlayer = vibrationPlayer ?? RepeatingVibrationPlayer();

  final LocalNotificationsClient _notifications;
  final AlarmPlayer _alarmPlayer;
  final VibrationPlayer _vibrationPlayer;

  final ValueNotifier<LocationStateStatus> badgeState =
      ValueNotifier<LocationStateStatus>(
    LocationStateStatus.waitGeoJson,
  );

  static const _channelId = 'argus_alerts';
  static const _channelName = 'Argus警告';
  static const _channelDescription = 'ジオフェンスの安全エリアから離れたときに通知します。';
  static const int _outerNotificationId = 1001;

  bool _initialized = false;
  bool _isAlarming = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notifications.initialize(initSettings);
    await _notifications.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
      critical: true,
    );
    await _notifications.ensureAndroidChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    _initialized = true;
  }

  Future<void> notifyOuter() async {
    await initialize();
    final androidDetails = const AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      ticker: 'Argus警告',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );
    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _notifications.show(
      _outerNotificationId,
      'Argus警告',
      '競技エリアから離れています。',
      notificationDetails,
    );
    if (!_isAlarming) {
      await _alarmPlayer.start();
      await _vibrationPlayer.start();
      _isAlarming = true;
    }
  }

  Future<void> notifyRecover() async {
    await initialize();
    await _notifications.cancel(_outerNotificationId);
    await stopAlarm();
    debugPrint('Argus: re-entered safe zone');
  }

  Future<void> updateBadge(LocationStateStatus status) async {
    badgeState.value = status;
  }

  Future<void> stopAlarm() async {
    if (_isAlarming) {
      await _alarmPlayer.stop();
      await _vibrationPlayer.stop();
      _isAlarming = false;
    }
  }
}

abstract class LocalNotificationsClient {
  Future<void> initialize(InitializationSettings settings);
  Future<void> requestPermissions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
    bool critical = true,
  });
  Future<void> ensureAndroidChannel(AndroidNotificationChannel channel);
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  );
  Future<void> cancel(int id);
}

class FlutterLocalNotificationsClient implements LocalNotificationsClient {
  FlutterLocalNotificationsClient(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize(InitializationSettings settings) async {
    await _plugin.initialize(settings);
  }

  @override
  Future<void> requestPermissions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
    bool critical = true,
  }) async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      try {
        await (androidPlugin as dynamic).requestPermission();
      } catch (_) {
        // Older Android plugin versions might not expose requestPermission.
      }
    }

    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: alert,
      badge: badge,
      sound: sound,
      critical: critical,
    );
  }

  @override
  Future<void> ensureAndroidChannel(
    AndroidNotificationChannel channel,
  ) async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
    }
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  ) {
    return _plugin.show(
      id,
      title,
      body,
      details,
    );
  }

  @override
  Future<void> cancel(int id) {
    return _plugin.cancel(id);
  }
}

abstract class AlarmPlayer {
  Future<void> start();
  Future<void> stop();
}

class RingtoneAlarmPlayer implements AlarmPlayer {
  const RingtoneAlarmPlayer();

  @override
  Future<void> start() {
    return FlutterRingtonePlayer().playAlarm(
      looping: true,
      volume: 1.0,
      asAlarm: true,
    );
  }

  @override
  Future<void> stop() {
    return FlutterRingtonePlayer().stop();
  }
}

abstract class VibrationPlayer {
  Future<void> start();
  Future<void> stop();
}

/// 5秒振動→2秒休止を繰り返すバイブレーションパターンを提供します。
class RepeatingVibrationPlayer implements VibrationPlayer {
  RepeatingVibrationPlayer();

  static const _vibrationDurationSeconds = 5;
  static const _pauseDurationSeconds = 2;

  bool _shouldContinue = false;
  bool _isRunning = false;

  @override
  Future<void> start() async {
    if (_isRunning) {
      return;
    }

    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      _shouldContinue = true;
      _isRunning = true;
      _vibrationLoop();
    }
  }

  /// 5秒振動→2秒休止のパターンを繰り返すループを実行します。
  Future<void> _vibrationLoop() async {
    try {
      while (_shouldContinue) {
        // 5秒振動
        await Vibration.vibrate(
          duration: _vibrationDurationSeconds * 1000,
        );

        if (!_shouldContinue) break;

        // 2秒休止
        await Future.delayed(
          const Duration(seconds: _pauseDurationSeconds),
        );
      }
    } finally {
      _isRunning = false;
    }
  }

  @override
  Future<void> stop() async {
    _shouldContinue = false;
    await Vibration.cancel();
    // _isRunningは_vibrationLoop()のfinallyブロックでリセットされる
  }
}
