import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import '../state_machine/state.dart';

class Notifier {
  Notifier({
    FlutterLocalNotificationsPlugin? plugin,
    LocalNotificationsClient? notificationsClient,
    AlarmPlayer? alarmPlayer,
  })  : _notifications =
            notificationsClient ??
                FlutterLocalNotificationsClient(
                  plugin ?? FlutterLocalNotificationsPlugin(),
                ),
        _alarmPlayer = alarmPlayer ?? const RingtoneAlarmPlayer();

  final LocalNotificationsClient _notifications;
  final AlarmPlayer _alarmPlayer;

  final ValueNotifier<LocationStateStatus> badgeState =
      ValueNotifier<LocationStateStatus>(
    LocationStateStatus.waitGeoJson,
  );

  static const _channelId = 'argus_alerts';
  static const _channelName = 'Argus警告';
  static const _channelDescription =
      'ジオフェンスの安全エリアから離れたときに通知します。';
  static const int _outerNotificationId = 1001;

  bool _initialized = false;
  bool _isRinging = false;

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
    if (!_isRinging) {
      await _alarmPlayer.start();
      _isRinging = true;
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
    if (_isRinging) {
      await _alarmPlayer.stop();
      _isRinging = false;
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
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
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
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
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
