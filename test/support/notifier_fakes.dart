import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:argus/platform/notifier.dart';

class FakeLocalNotificationsClient implements LocalNotificationsClient {
  final List<int> shownIds = <int>[];
  final List<int> cancelledIds = <int>[];
  bool initialized = false;
  int initializeCount = 0;
  InitializationSettings? lastInitializationSettings;
  AndroidNotificationChannel? lastChannel;
  int ensureChannelCount = 0;
  bool requestedPermissions = false;
  NotificationDetails? lastShownDetails;

  @override
  Future<void> initialize(InitializationSettings settings) async {
    initialized = true;
    initializeCount += 1;
    lastInitializationSettings = settings;
  }

  Future<void> requestPermissions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
    bool critical = true,
  }) async {
    requestedPermissions = true;
  }

  @override
  Future<void> ensureAndroidChannel(AndroidNotificationChannel channel) async {
    lastChannel = channel;
    ensureChannelCount += 1;
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  ) async {
    shownIds.add(id);
    lastShownDetails = details;
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }
}

class FakeAlarmPlayer implements AlarmPlayer {
  int playCount = 0;
  int stopCount = 0;

  @override
  Future<void> start() async {
    playCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

class FakeVibrationPlayer implements VibrationPlayer {
  int startCount = 0;
  int stopCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}
