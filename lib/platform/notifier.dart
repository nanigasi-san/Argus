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
  bool _isAlarmChannelActive = false;
  bool _isVibrationChannelActive = false;
  bool _isAlarmPreviewPlaying = false;
  int _generation = 0;
  Future<void> _monitoringHealthNotificationQueue = Future<void>.value();

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
    final generation = ++_generation;
    _isAlarmPreviewPlaying = false;
    _throwFirstError(
      await Future.wait<Object?>([
        _stopAlarmChannel(),
        _stopVibrationChannel(),
      ]),
    );
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
    _generation += 1;
    _isAlarmPreviewPlaying = false;
    final error = await _stopAlarmChannel();
    if (error != null) {
      throw error;
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
      _captureError(
        () => _enqueueMonitoringHealthNotification(() async {
          await initialize();
          await _notifications.show(
            _monitoringStaleNotificationId,
            'ARGUS監視警告',
            'GPSを受信できません。位置情報へ再接続しています。',
            details,
          );
        }),
      ),
      _captureError(_startMonitoringStaleVibration),
    ]);
    _throwFirstError(errors);
  }

  Future<void> clearMonitoringStale() async {
    await _enqueueMonitoringHealthNotification(() async {
      await initialize();
      await _notifications.cancel(_monitoringStaleNotificationId);
    });
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
    _isAlarmPreviewPlaying = false;
    final errors = await Future.wait<Object?>([
      _stopAlarmChannel(),
      _stopVibrationChannel(),
    ]);
    _throwFirstError(errors);
  }

  Future<void> resumeAlarm() async {
    final result = await _resumeAlarm(_generation);
    result.throwIfFailed();
  }

  Future<void> reassertAlarm() async {
    final generation = _generation;
    final results = await Future.wait<Object?>([
      _startAlarmChannel(generation, restart: true),
      _startVibrationChannel(generation, restart: true),
    ]);
    final alarmError = results[0];
    final vibrationError = results[1];
    _PlaybackStartResult(
      alarmError: alarmError,
      vibrationError: vibrationError,
    ).throwIfFailed();
  }

  Future<_PlaybackStartResult> _resumeAlarm(int generation) async {
    var activeGeneration = generation;
    if (_isAlarmPreviewPlaying) {
      await stopAlarmPreview();
      activeGeneration = _generation;
    }
    if (activeGeneration != _generation) {
      return const _PlaybackStartResult();
    }
    final results = await Future.wait<Object?>([
      _isAlarmChannelActive
          ? Future<Object?>.value()
          : _startAlarmChannel(activeGeneration),
      _isVibrationChannelActive
          ? Future<Object?>.value()
          : _startVibrationChannel(activeGeneration),
    ]);
    final alarmError = results[0];
    final vibrationError = results[1];
    if (activeGeneration != _generation) {
      return const _PlaybackStartResult();
    }
    return _PlaybackStartResult(
      alarmError: alarmError,
      vibrationError: vibrationError,
    );
  }

  Future<Object?> _startAlarmChannel(
    int generation, {
    bool restart = false,
  }) async {
    try {
      if (restart) {
        _isAlarmChannelActive = false;
      }
      await _alarmPlayer.start();
      if (generation != _generation) {
        await _alarmPlayer.stop();
        _isAlarmChannelActive = false;
      } else {
        _isAlarmChannelActive = true;
      }
      return null;
    } catch (error) {
      _isAlarmChannelActive = false;
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
        _isVibrationChannelActive = false;
        await _vibrationPlayer.stop();
      }
      await _vibrationPlayer.start();
      if (generation != _generation) {
        await _vibrationPlayer.stop();
        _isVibrationChannelActive = false;
      } else {
        _isVibrationChannelActive = true;
      }
      return null;
    } catch (error) {
      _isVibrationChannelActive = false;
      try {
        await _vibrationPlayer.stop();
      } catch (_) {}
      return error;
    }
  }

  Future<void> dismissOuterAlert() async {
    _generation += 1;
    _isAlarmPreviewPlaying = false;
    final errors = await Future.wait<Object?>([
      _captureError(() async {
        await initialize();
        await _notifications.cancel(_outerNotificationId);
      }),
      _stopAlarmChannel(),
      _stopVibrationChannel(),
    ]);
    _throwFirstError(errors);
  }

  /// 停止できずに鳴り続けている可能性のある発報経路があるか。
  ///
  /// 停止に失敗した経路のフラグは倒さないため、`stopAlarm()` や
  /// `dismissOuterAlert()` のあとに true ならネイティブ側で警報が
  /// 継続している可能性がある。
  bool get hasActiveAlertPlayback =>
      _isAlarmChannelActive || _isVibrationChannelActive;

  /// 警報音を停止する。成功した場合だけ再生中フラグを倒す。
  ///
  /// フラグを先に倒すと、停止が失敗して実際には鳴り続けているのに
  /// アプリ側は「停止済み」と認識してしまい、再試行も検知もできなくなる。
  Future<Object?> _stopAlarmChannel() async {
    final error = await _captureError(_alarmPlayer.stop);
    if (error == null) {
      _isAlarmChannelActive = false;
    }
    return error;
  }

  /// 連続バイブを停止する。成功した場合だけ再生中フラグを倒す。
  Future<Object?> _stopVibrationChannel() async {
    final error = await _captureError(_vibrationPlayer.stop);
    if (error == null) {
      _isVibrationChannelActive = false;
    }
    return error;
  }

  Future<void> _startMonitoringStaleVibration() async {
    if (_isVibrationChannelActive) {
      return;
    }
    await _vibrationPlayer.pulse(_monitoringStaleVibrationDuration);
  }

  Future<void> _enqueueMonitoringHealthNotification(
    Future<void> Function() operation,
  ) {
    final result = _monitoringHealthNotificationQueue.then(
      (_) => operation(),
    );
    _monitoringHealthNotificationQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
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

class AlertPlaybackState {
  const AlertPlaybackState({
    required this.alarmActive,
    required this.vibrationPatternActive,
  });

  factory AlertPlaybackState.fromMap(Map<Object?, Object?> map) {
    final alarmActive = map['alarmActive'];
    final vibrationPatternActive = map['vibrationPatternActive'];
    if (alarmActive is! bool || vibrationPatternActive is! bool) {
      throw const FormatException('Invalid alert playback state.');
    }
    return AlertPlaybackState(
      alarmActive: alarmActive,
      vibrationPatternActive: vibrationPatternActive,
    );
  }

  final bool alarmActive;
  final bool vibrationPatternActive;
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
    return _channel.invokeMethod<void>('stopAlarm');
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

class MethodChannelAlertDiagnosticsClient {
  const MethodChannelAlertDiagnosticsClient();

  static const MethodChannel _channel = MethodChannel('argus/alarm');

  Future<AlertPlaybackState> getPlaybackState() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getAlertPlaybackState',
    );
    if (result == null) {
      throw const FormatException('Missing alert playback state.');
    }
    return AlertPlaybackState.fromMap(result);
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
  Future<void> pulse(Duration duration);
  Future<void> stop();
}

abstract class VibrationPlatformClient {
  Future<void> startPattern();
  Future<void> pulse(Duration duration);
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
  Future<void> pulse(Duration duration) {
    return _channel.invokeMethod<void>(
      'pulseVibration',
      <String, Object?>{
        'durationMs': duration.inMilliseconds,
      },
    );
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
  Future<void> pulse(Duration duration) async {
    if (_usesNativePlatformClient) {
      await _client.pulse(duration);
    }
  }

  @override
  Future<void> stop() async {
    if (_usesNativePlatformClient) {
      await _client.stop();
    }
  }
}
