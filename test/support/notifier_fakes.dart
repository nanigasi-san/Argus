import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:argus/platform/notifier.dart';

class NotificationShowCall {
  const NotificationShowCall({
    required this.id,
    required this.title,
    required this.body,
    required this.details,
  });

  final int id;
  final String? title;
  final String? body;
  final NotificationDetails details;
}

class FakeLocalNotificationsClient implements LocalNotificationsClient {
  final List<int> shownIds = <int>[];
  final List<int> cancelledIds = <int>[];
  final List<String> calls = <String>[];
  final List<NotificationShowCall> showCalls = <NotificationShowCall>[];
  bool initialized = false;
  int initializeCount = 0;
  InitializationSettings? lastInitializationSettings;
  AndroidNotificationChannel? lastChannel;
  int ensureChannelCount = 0;
  bool requestedPermissions = false;
  NotificationDetails? lastShownDetails;

  @override
  Future<void> initialize(InitializationSettings settings) async {
    calls.add('initialize');
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
    calls.add('requestPermissions');
    requestedPermissions = true;
  }

  @override
  Future<void> ensureAndroidChannel(AndroidNotificationChannel channel) async {
    calls.add('ensureAndroidChannel');
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
    calls.add('show');
    shownIds.add(id);
    lastShownDetails = details;
    showCalls.add(
      NotificationShowCall(
        id: id,
        title: title,
        body: body,
        details: details,
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel');
    cancelledIds.add(id);
  }
}

class FakeAlarmPlayer implements AlarmPlayer {
  int playCount = 0;
  int stopCount = 0;
  final List<String> calls = <String>[];

  @override
  Future<void> start() async {
    calls.add('start');
    playCount += 1;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    stopCount += 1;
  }
}

class FakeVibrationPlayer implements VibrationPlayer {
  int startCount = 0;
  int stopCount = 0;
  final List<String> calls = <String>[];

  @override
  Future<void> start() async {
    calls.add('start');
    startCount += 1;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    stopCount += 1;
  }
}
