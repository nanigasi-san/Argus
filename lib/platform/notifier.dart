import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import '../state_machine/state.dart';

class AlertDeliveryReport {
  const AlertDeliveryReport({
    this.notificationError,
    this.alarmError,
    this.vibrationError,
  });

  final Object? notificationError;
  final Object? alarmError;
  final Object? vibrationError;

  bool get hasFailures =>
      notificationError != null || alarmError != null || vibrationError != null;

  String get failureSummary {
    final failures = <String>[];
    if (notificationError != null) {
      failures.add('notification=$notificationError');
    }
    if (alarmError != null) {
      failures.add('alarm=$alarmError');
    }
    if (vibrationError != null) {
      failures.add('vibration=$vibrationError');
    }
    return failures.join(', ');
  }
}

class Notifier {
  Notifier({
    FlutterLocalNotificationsPlugin? plugin,
    LocalNotificationsClient? notificationsClient,
    AlarmPlayer? alarmPlayer,
    VibrationPlayer? vibrationPlayer,
    Duration monitoringStaleVibrationDuration =
        const Duration(milliseconds: 350),
  })  : _notifications = notificationsClient ??
            FlutterLocalNotificationsClient(
              plugin ?? FlutterLocalNotificationsPlugin(),
            ),
        _alarmPlayer = alarmPlayer ?? const NativeAlarmPlayer(),
        _vibrationPlayer = vibrationPlayer ?? const NativeVibrationPlayer(),
        _monitoringStaleVibrationDuration = monitoringStaleVibrationDuration {
    assert(!monitoringStaleVibrationDuration.isNegative);
  }

  final LocalNotificationsClient _notifications;
  AlarmPlayer _alarmPlayer;
  final VibrationPlayer _vibrationPlayer;
  final Duration _monitoringStaleVibrationDuration;

  final ValueNotifier<LocationStateStatus> badgeState =
      ValueNotifier<LocationStateStatus>(
    LocationStateStatus.waitGeoJson,
  );

  static const _channelId = 'argus_alerts_visual_v2';
  static const _channelName = 'ARGUS警告';
  static const _channelDescription = 'ジオフェンスの安全エリアから離れたときに通知します。';
  static const _healthChannelId = 'argus_monitoring_health_v1';
  static const _healthChannelName = 'ARGUS監視状態';
  static const int _outerNotificationId = 1001;
  static const int _monitoringStaleNotificationId = 1002;

  bool _initialized = false;
  bool _isAlarming = false;
  bool _isAlarmPreviewPlaying = false;
  int _generation = 0;
  Timer? _monitoringStaleVibrationTimer;

  bool get isAlarmPreviewPlaying => _isAlarmPreviewPlaying;

  /// アラーム音量を設定します（0.0～1.0）。
  void setAlarmVolume(double volume) {
    if (_alarmPlayer is NativeAlarmPlayer) {
      final player = _alarmPlayer as NativeAlarmPlayer;
      _alarmPlayer = player.copyWith(
        volume: volume.clamp(0.0, 1.0).toDouble(),
      );
    }
  }

  Future<void> startAlarmPreview() async {
    _cancelMonitoringStaleVibrationTimer();
    final generation = ++_generation;
    _isAlarmPreviewPlaying = false;
    _isAlarming = false;
    await _alarmPlayer.stop();
    await _vibrationPlayer.stop();
    if (generation != _generation) {
      return;
    }

    try {
      await _alarmPlayer.start();
      if (generation != _generation) {
        await _alarmPlayer.stop();
        return;
      }
      _isAlarmPreviewPlaying = true;
    } catch (_) {
      _isAlarmPreviewPlaying = false;
      await _alarmPlayer.stop();
      rethrow;
    }
  }

  Future<void> stopAlarmPreview() async {
    _cancelMonitoringStaleVibrationTimer();
    _generation += 1;
    _isAlarmPreviewPlaying = false;
    await _alarmPlayer.stop();
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
    await _notifications.ensureAndroidChannel(
      const AndroidNotificationChannel(
        _healthChannelId,
        _healthChannelName,
        description: 'GPS監視の停止や再接続を通知します。',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
    );

    _initialized = true;
  }

  Future<AlertDeliveryReport> notifyOuter() async {
    if (_isAlarmPreviewPlaying) {
      await stopAlarmPreview();
    }
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
      // Foreground playback uses AVAudioPlayer. The bundled notification
      // sound remains set so iOS can alert while the screen is locked.
      presentSound: false,
      sound: 'alarm.caf',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    final notificationFuture = () async {
      try {
        await initialize();
        await _notifications.show(
          _outerNotificationId,
          'ARGUS警告',
          '競技エリアから離れています。',
          notificationDetails,
        );
        if (generation != _generation) {
          await _notifications.cancel(_outerNotificationId);
        }
        return null;
      } catch (error) {
        return error;
      }
    }();
    final playbackFuture = _resumeAlarm(generation);
    final playback = await playbackFuture;
    final notificationError = await notificationFuture;
    return AlertDeliveryReport(
      notificationError: notificationError,
      alarmError: playback.alarmError,
      vibrationError: playback.vibrationError,
    );
  }

  Future<void> notifyMonitoringStale() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _healthChannelId,
        _healthChannelName,
        channelDescription: 'GPS監視の停止や再接続を通知します。',
        importance: Importance.high,
        priority: Priority.high,
        playSound: false,
        enableVibration: false,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: false,
      ),
    );
    final errors = await Future.wait<Object?>([
      _captureError(() async {
        await initialize();
        await _notifications.show(
          _monitoringStaleNotificationId,
          'ARGUS監視警告',
          'GPSを受信できません。位置情報へ再接続しています。',
          details,
        );
      }),
      _captureError(_startMonitoringStaleVibration),
    ]);
    _throwFirstError(errors);
  }

  Future<void> clearMonitoringStale() async {
    await initialize();
    await _notifications.cancel(_monitoringStaleNotificationId);
  }

  Future<void> notifyRecover() async {
    await dismissOuterAlert();
    debugPrint('Argus: re-entered safe zone');
  }

  Future<void> updateBadge(LocationStateStatus status) async {
    badgeState.value = status;
  }

  Future<void> stopAlarm() async {
    _cancelMonitoringStaleVibrationTimer();
    _generation += 1;
    _isAlarming = false;
    _isAlarmPreviewPlaying = false;
    final errors = await Future.wait<Object?>([
      _captureError(_alarmPlayer.stop),
      _captureError(_vibrationPlayer.stop),
    ]);
    _throwFirstError(errors);
  }

  Future<void> resumeAlarm() async {
    final result = await _resumeAlarm(_generation);
    result.throwIfFailed();
  }

  Future<void> reassertAlarm() async {
    _cancelMonitoringStaleVibrationTimer();
    if (!_isAlarming) {
      final result = await _resumeAlarm(_generation);
      result.throwIfFailed();
      return;
    }

    final generation = _generation;
    final results = await Future.wait<Object?>([
      _startAlarmChannel(generation),
      _startVibrationChannel(generation, restart: true),
    ]);
    final alarmError = results[0];
    final vibrationError = results[1];
    if (alarmError != null || vibrationError != null) {
      _isAlarming = false;
    }
    _PlaybackStartResult(
      alarmError: alarmError,
      vibrationError: vibrationError,
    ).throwIfFailed();
  }

  Future<_PlaybackStartResult> _resumeAlarm(int generation) async {
    _cancelMonitoringStaleVibrationTimer();
    var activeGeneration = generation;
    if (_isAlarmPreviewPlaying) {
      await stopAlarmPreview();
      activeGeneration = _generation;
    }
    if (_isAlarming || activeGeneration != _generation) {
      return const _PlaybackStartResult();
    }
    _isAlarming = true;
    final results = await Future.wait<Object?>([
      _startAlarmChannel(activeGeneration),
      _startVibrationChannel(activeGeneration),
    ]);
    final alarmError = results[0];
    final vibrationError = results[1];
    if (activeGeneration != _generation) {
      _isAlarming = false;
      return const _PlaybackStartResult();
    }
    if (alarmError != null || vibrationError != null) {
      _isAlarming = false;
    }
    return _PlaybackStartResult(
      alarmError: alarmError,
      vibrationError: vibrationError,
    );
  }

  Future<Object?> _startAlarmChannel(int generation) async {
    try {
      await _alarmPlayer.start();
      if (generation != _generation) {
        await _alarmPlayer.stop();
      }
      return null;
    } catch (error) {
      try {
        await _alarmPlayer.stop();
      } catch (_) {}
      return error;
    }
  }

  Future<Object?> _startVibrationChannel(
    int generation, {
    bool restart = false,
  }) async {
    try {
      if (restart) {
        await _vibrationPlayer.stop();
      }
      await _vibrationPlayer.start();
      if (generation != _generation) {
        await _vibrationPlayer.stop();
      }
      return null;
    } catch (error) {
      try {
        await _vibrationPlayer.stop();
      } catch (_) {}
      return error;
    }
  }

  Future<void> dismissOuterAlert() async {
    _cancelMonitoringStaleVibrationTimer();
    _generation += 1;
    _isAlarming = false;
    _isAlarmPreviewPlaying = false;
    final errors = await Future.wait<Object?>([
      _captureError(() async {
        await initialize();
        await _notifications.cancel(_outerNotificationId);
      }),
      _captureError(_alarmPlayer.stop),
      _captureError(_vibrationPlayer.stop),
    ]);
    _throwFirstError(errors);
  }

  Future<void> _startMonitoringStaleVibration() async {
    if (_isAlarming) {
      return;
    }
    _cancelMonitoringStaleVibrationTimer();
    await _vibrationPlayer.start();
    if (_isAlarming) {
      return;
    }
    _monitoringStaleVibrationTimer = Timer(
      _monitoringStaleVibrationDuration,
      () {
        _monitoringStaleVibrationTimer = null;
        if (!_isAlarming) {
          unawaited(_stopMonitoringStaleVibrationIgnoringErrors());
        }
      },
    );
  }

  void _cancelMonitoringStaleVibrationTimer() {
    _monitoringStaleVibrationTimer?.cancel();
    _monitoringStaleVibrationTimer = null;
  }

  Future<void> _stopMonitoringStaleVibrationIgnoringErrors() async {
    try {
      await _vibrationPlayer.stop();
    } catch (_) {
      // The short health pulse is best effort after it has already started.
    }
  }

  Future<Object?> _captureError(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (error) {
      return error;
    }
  }

  void _throwFirstError(List<Object?> errors) {
    for (final error in errors) {
      if (error != null) {
        throw error;
      }
    }
  }
}

class _PlaybackStartResult {
  const _PlaybackStartResult({this.alarmError, this.vibrationError});

  final Object? alarmError;
  final Object? vibrationError;

  void throwIfFailed() {
    if (alarmError != null) {
      throw alarmError!;
    }
    if (vibrationError != null) {
      throw vibrationError!;
    }
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
