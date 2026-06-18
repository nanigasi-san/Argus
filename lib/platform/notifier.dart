import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

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
        _alarmPlayer = alarmPlayer ?? const NativeAlarmPlayer(),
        _vibrationPlayer = vibrationPlayer ?? const NativeVibrationPlayer();

  final LocalNotificationsClient _notifications;
  AlarmPlayer _alarmPlayer;
  final VibrationPlayer _vibrationPlayer;

  final ValueNotifier<LocationStateStatus> badgeState =
      ValueNotifier<LocationStateStatus>(
    LocationStateStatus.waitGeoJson,
  );

  static const _channelId = 'argus_alerts_visual_v2';
  static const _channelName = 'ARGUS警告';
  static const _channelDescription = 'ジオフェンスの安全エリアから離れたときに通知します。';
  static const int _outerNotificationId = 1001;

  bool _initialized = false;
  bool _isAlarming = false;
  int _generation = 0;

  /// アラーム音量を設定します（0.0～1.0）。
  void setAlarmVolume(double volume) {
    if (_alarmPlayer is NativeAlarmPlayer) {
      final player = _alarmPlayer as NativeAlarmPlayer;
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
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _notifications.initialize(initSettings);
    await _notifications.ensureAndroidChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: false,
        enableVibration: false,
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
      playSound: false,
      enableVibration: false,
      category: AndroidNotificationCategory.alarm,
      ticker: 'ARGUS警告',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: false,
      sound: 'alarm.caf',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _notifications.show(
      _outerNotificationId,
      'ARGUS警告',
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

  Future<void> reassertAlarm() async {
    if (!_isAlarming) {
      await _resumeAlarm(_generation);
      return;
    }

    final generation = _generation;
    try {
      await _alarmPlayer.start();
      if (generation != _generation) {
        await _alarmPlayer.stop();
        return;
      }
      await _vibrationPlayer.stop();
      await _vibrationPlayer.start();
    } catch (_) {
      _isAlarming = false;
      rethrow;
    }
  }

  Future<void> _resumeAlarm(int generation) async {
    if (_isAlarming || generation != _generation) {
      return;
    }
    _isAlarming = true;
    try {
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
    } catch (_) {
      _isAlarming = false;
      try {
        await _alarmPlayer.stop();
      } catch (_) {}
      try {
        await _vibrationPlayer.stop();
      } catch (_) {}
      rethrow;
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

// coverage:ignore-start
// Thin wrapper around the Flutter plugin. Behavior is covered through
// LocalNotificationsClient fakes; plugin integration is verified by builds.
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
// coverage:ignore-end

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

class AlarmVolumeState {
  const AlarmVolumeState({
    required this.current,
    required this.max,
    required this.percent,
  });

  factory AlarmVolumeState.fromMap(Map<Object?, Object?> map) {
    final current = map['current'];
    final max = map['max'];
    final percent = map['percent'];
    if (current is! int || max is! int || percent is! num) {
      throw const FormatException('Invalid alarm volume state.');
    }
    return AlarmVolumeState(
      current: current,
      max: max,
      percent: percent.toDouble(),
    );
  }

  final int current;
  final int max;
  final double percent;
}

abstract class AlarmVolumeClient {
  Future<AlarmVolumeState> getAlarmVolumeState();
  Future<bool> openSoundSettings();
}

class MethodChannelAlarmClient
    implements AlarmPlatformClient, AlarmVolumeClient {
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

  @override
  Future<AlarmVolumeState> getAlarmVolumeState() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getAlarmVolumeState',
    );
    if (result == null) {
      throw const FormatException('Missing alarm volume state.');
    }
    return AlarmVolumeState.fromMap(result);
  }

  @override
  Future<bool> openSoundSettings() async {
    return await _channel.invokeMethod<bool>('openSoundSettings') ?? false;
  }
}

class NativeAlarmPlayer implements AlarmPlayer {
  const NativeAlarmPlayer({
    this.volume = 1.0,
    AlarmPlatformClient? platformClient,
    bool? isAndroid,
    bool? isIOS,
  })  : _platformClient = platformClient,
        _isAndroidOverride = isAndroid,
        _isIOSOverride = isIOS;

  final double volume;
  final AlarmPlatformClient? _platformClient;
  final bool? _isAndroidOverride;
  final bool? _isIOSOverride;

  NativeAlarmPlayer copyWith({double? volume}) {
    return NativeAlarmPlayer(
      volume: volume ?? this.volume,
      platformClient: _platformClient,
      isAndroid: _isAndroidOverride,
      isIOS: _isIOSOverride,
    );
  }

  AlarmPlatformClient get _client =>
      _platformClient ?? const MethodChannelAlarmClient();
  bool get _isAndroid => _isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);
  bool get _isIOS => _isIOSOverride ?? (!kIsWeb && Platform.isIOS);
  bool get _usesNativePlatformClient => _isAndroid || _isIOS;

  @override
  Future<void> start() async {
    final clampedVolume = volume.clamp(0.0, 1.0).toDouble();
    if (_usesNativePlatformClient) {
      await _client.play(volume: clampedVolume);
      return;
    }

    throw UnsupportedError(
      'Native alarm playback is only supported on Android and iOS.',
    );
  }

  @override
  Future<void> stop() async {
    if (_usesNativePlatformClient) {
      await _client.stop();
    }
  }
}

abstract class VibrationPlayer {
  Future<void> start();
  Future<void> stop();
}

abstract class VibrationPlatformClient {
  Future<void> startPattern();
  Future<void> stop();
}

class MethodChannelVibrationClient implements VibrationPlatformClient {
  const MethodChannelVibrationClient();

  static const MethodChannel _channel = MethodChannel('argus/alarm');

  @override
  Future<void> startPattern() {
    return _channel.invokeMethod<void>('startVibration');
  }

  @override
  Future<void> stop() {
    return _channel.invokeMethod<void>('stopVibration');
  }
}

class NativeVibrationPlayer implements VibrationPlayer {
  const NativeVibrationPlayer({
    VibrationPlatformClient? platformClient,
    bool? isAndroid,
    bool? isIOS,
  })  : _platformClient = platformClient,
        _isAndroidOverride = isAndroid,
        _isIOSOverride = isIOS;

  final VibrationPlatformClient? _platformClient;
  final bool? _isAndroidOverride;
  final bool? _isIOSOverride;

  VibrationPlatformClient get _client =>
      _platformClient ?? const MethodChannelVibrationClient();
  bool get _isAndroid => _isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);
  bool get _isIOS => _isIOSOverride ?? (!kIsWeb && Platform.isIOS);
  bool get _usesNativePlatformClient => _isAndroid || _isIOS;

  @override
  Future<void> start() async {
    if (_usesNativePlatformClient) {
      await _client.startPattern();
    }
  }

  @override
  Future<void> stop() async {
    if (_usesNativePlatformClient) {
      await _client.stop();
    }
  }
}
