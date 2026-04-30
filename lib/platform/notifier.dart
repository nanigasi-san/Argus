import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

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
  AlarmPlayer _alarmPlayer;
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
  int _generation = 0;

  /// アラーム音量を設定します（0.0～1.0）。
  void setAlarmVolume(double volume) {
    if (_alarmPlayer is RingtoneAlarmPlayer) {
      final player = _alarmPlayer as RingtoneAlarmPlayer;
      _alarmPlayer = player.copyWith(
        volume: volume.clamp(0.0, 1.0).toDouble(),
      );
    }
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notifications.initialize(initSettings);
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
    final generation = _generation;
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm'),
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      ticker: 'Argus警告',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      sound: 'alarm.mp3',
      interruptionLevel: InterruptionLevel.critical,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _notifications.show(
      _outerNotificationId,
      'Argus警告',
      '競技エリアから離れています。',
      notificationDetails,
    );
    if (generation != _generation) {
      return;
    }
    await _resumeAlarm(generation);
  }

  Future<void> notifyRecover() async {
    await dismissOuterAlert();
    debugPrint('Argus: re-entered safe zone');
  }

  Future<void> updateBadge(LocationStateStatus status) async {
    badgeState.value = status;
  }

  Future<void> stopAlarm() async {
    _generation += 1;
    _isAlarming = false;
    await _alarmPlayer.stop();
    await _vibrationPlayer.stop();
  }

  Future<void> resumeAlarm() async {
    await _resumeAlarm(_generation);
  }

  Future<void> _resumeAlarm(int generation) async {
    if (_isAlarming || generation != _generation) {
      return;
    }
    _isAlarming = true;
    await _alarmPlayer.start();
    if (generation != _generation) {
      await _alarmPlayer.stop();
      _isAlarming = false;
      return;
    }
    await _vibrationPlayer.start();
    if (generation != _generation) {
      await _alarmPlayer.stop();
      await _vibrationPlayer.stop();
      _isAlarming = false;
    }
  }

  Future<void> dismissOuterAlert() async {
    _generation += 1;
    _isAlarming = false;
    await initialize();
    await _notifications.cancel(_outerNotificationId);
    await _alarmPlayer.stop();
    await _vibrationPlayer.stop();
  }
}

abstract class LocalNotificationsClient {
  Future<void> initialize(InitializationSettings settings);
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

abstract class AlarmPlatformClient {
  Future<void> play({
    required double volume,
  });

  Future<void> stop();
}

class MethodChannelAlarmClient implements AlarmPlatformClient {
  const MethodChannelAlarmClient();

  static const MethodChannel _channel = MethodChannel('argus/alarm');

  @override
  Future<void> play({
    required double volume,
  }) {
    return _channel.invokeMethod<void>(
      'play',
      <String, Object?>{
        'volume': volume,
      },
    );
  }

  @override
  Future<void> stop() {
    return _channel.invokeMethod<void>('stop');
  }
}

class RingtoneAlarmPlayer implements AlarmPlayer {
  const RingtoneAlarmPlayer({
    this.volume = 1.0,
    AlarmPlatformClient? platformClient,
  }) : _platformClient = platformClient;

  final double volume;
  final AlarmPlatformClient? _platformClient;

  RingtoneAlarmPlayer copyWith({double? volume}) {
    return RingtoneAlarmPlayer(
      volume: volume ?? this.volume,
      platformClient: _platformClient,
    );
  }

  AlarmPlatformClient get _client =>
      _platformClient ?? const MethodChannelAlarmClient();

  @override
  Future<void> start() async {
    final clampedVolume = volume.clamp(0.0, 1.0).toDouble();
    if (!kIsWeb && Platform.isAndroid) {
      await _client.play(volume: clampedVolume);
      return;
    }

    // アセット音をループ再生（assets/sounds/alarm.mp3 を追加すること）
    await FlutterRingtonePlayer().play(
      fromAsset: 'assets/sounds/alarm.mp3',
      looping: true,
      volume: clampedVolume,
      asAlarm: true,
    );
  }

  @override
  Future<void> stop() async {
    if (!kIsWeb && Platform.isAndroid) {
      await _client.stop();
      return;
    }

    return FlutterRingtonePlayer().stop();
  }
}

abstract class VibrationPlayer {
  Future<void> start();
  Future<void> stop();
}

// coverage:ignore-start
/// 5秒振動→2秒休止を繰り返すバイブレーションパターンを提供します。
class RepeatingVibrationPlayer implements VibrationPlayer {
  RepeatingVibrationPlayer();

  static const _vibrationDurationSeconds = 5;
  static const _pauseDurationSeconds = 2;

  bool _shouldContinue = false;
  bool _isRunning = false;
  Future<void>? _loopFuture;

  @override
  Future<void> start() async {
    if (_isRunning) {
      return;
    }

    final bool hasVibrator;
    try {
      hasVibrator = await Vibration.hasVibrator() == true;
    } on MissingPluginException {
      return;
    }

    if (hasVibrator == true) {
      _shouldContinue = true;
      _isRunning = true;
      _loopFuture = _vibrationLoop();
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
      _loopFuture = null;
    }
  }

  @override
  Future<void> stop() async {
    _shouldContinue = false;
    try {
      await Vibration.cancel();
    } on MissingPluginException {
      return;
    }
    final loopFuture = _loopFuture;
    if (loopFuture != null) {
      await loopFuture.timeout(
        const Duration(milliseconds: 250),
        onTimeout: () {},
      );
    }
  }
}
// coverage:ignore-end
