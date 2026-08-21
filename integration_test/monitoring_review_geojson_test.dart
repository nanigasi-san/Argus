import 'dart:io';

import 'package:argus/geo/geo_model.dart';
import 'package:argus/io/config.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'review GeoJSON runs INNER -> OUTER -> bad-fix OUTER -> INNER on device',
      (tester) async {
    final raw = await rootBundle.loadString(
      'docs/app_store/review_test_area.geojson',
    );
    final model = GeoModel.fromGeoJson(raw);
    expect(model.polygons.single.name,
        'App Review background monitoring test area');

    final location = HarnessLocationService();
    final notifications = HarnessLocalNotificationsClient();
    final alarm = HarnessAlarmPlayer();
    final vibration = HarnessVibrationPlayer();
    final notifier = Notifier(
      notificationsClient: notifications,
      alarmPlayer: alarm,
      vibrationPlayer: vibration,
    );
    final controller = HarnessBuilder.buildController(
      hasGeoJson: true,
      geoModel: model,
      locationService: location,
      notifier: notifier,
      permissionCoordinator: HarnessPermissionCoordinator(),
      alarmVolumeClient: const HarnessAlarmVolumeClient(),
      isAndroid: Platform.isAndroid,
    );

    await tester.pumpWidget(HarnessBuilder.buildApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('スタート待機'));
    await _pumpAsyncWork(tester);

    expect(location.startCount, 1);
    expect(find.text('GPS取得中'), findsOneWidget);
    expect(find.byKey(const Key('force-close-warning')), findsOneWidget);

    location.add(
      _fix(
        latitude: 0,
        longitude: 0,
        elapsed: const Duration(seconds: 0),
      ),
    );
    await _pumpAsyncWork(tester);
    expect(find.text('内側'), findsOneWidget);

    location.add(
      _fix(
        latitude: 0.01,
        longitude: 0.01,
        elapsed: const Duration(seconds: 1),
      ),
    );
    await _pumpAsyncWork(tester);
    location.add(
      _fix(
        latitude: 0.01,
        longitude: 0.01,
        elapsed: const Duration(seconds: 3),
      ),
    );
    await _pumpAsyncWork(tester);

    expect(find.text('外側'), findsOneWidget);
    expect(notifications.shownIds, contains(1001));
    expect(alarm.startCount, 1);
    expect(vibration.startCount, 1);

    location.add(
      _fix(
        latitude: 0,
        longitude: 0,
        accuracy: 100,
        elapsed: const Duration(seconds: 4),
      ),
    );
    await _pumpAsyncWork(tester);
    expect(find.text('外側'), findsOneWidget);

    location.add(
      _fix(
        latitude: 0,
        longitude: 0,
        elapsed: const Duration(seconds: 5),
      ),
    );
    await _pumpAsyncWork(tester);
    expect(find.text('内側'), findsOneWidget);
    expect(notifications.cancelledIds, contains(1001));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-monitoring-lock')), findsOneWidget);

    controller.dispose();
  });

  testWidgets('native alarm and vibration channels remain independent',
      (tester) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    const alarm = MethodChannelAlarmClient();
    const vibration = MethodChannelVibrationClient();
    const diagnostics = MethodChannelAlertDiagnosticsClient();

    try {
      await alarm.stop();
      await vibration.stop();

      await vibration.startPattern();
      var state = await diagnostics.getPlaybackState();
      expect(state.vibrationPatternActive, isTrue);

      await alarm.stop();
      state = await diagnostics.getPlaybackState();
      expect(state.alarmActive, isFalse);
      expect(
        state.vibrationPatternActive,
        isTrue,
        reason: 'アラーム停止で連続振動を止めてはいけない',
      );

      await vibration.stop();
      await alarm.play(volume: 0.1);
      state = await diagnostics.getPlaybackState();
      expect(state.alarmActive, isTrue);
      expect(state.vibrationPatternActive, isFalse);

      await vibration.pulse(const Duration(milliseconds: 50));
      state = await diagnostics.getPlaybackState();
      expect(
        state.alarmActive,
        isTrue,
        reason: '単発振動でアラーム音を止めてはいけない',
      );
      expect(state.vibrationPatternActive, isFalse);
    } finally {
      await alarm.stop();
      await vibration.stop();
    }
  });

  testWidgets('native geolocator stream receives the simulated device fix',
      (tester) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    final service = GeolocatorLocationService();
    final config = await AppConfig.loadDefault();
    try {
      final fixFuture = service.stream.first.timeout(
        const Duration(seconds: 30),
      );
      final result = await service.start(config);
      expect(
        result.status,
        LocationServiceStartStatus.started,
        reason: result.message,
      );

      final fix = await fixFuture;
      expect(fix.latitude, closeTo(35.681236, 0.001));
      expect(fix.longitude, closeTo(139.767125, 0.001));
      expect(fix.accuracyMeters, isNotNull);
      expect(fix.monitoringElapsed, isNotNull);
    } finally {
      await service.stop();
    }
  });
}

LocationFix _fix({
  required double latitude,
  required double longitude,
  required Duration elapsed,
  double accuracy = 5,
}) {
  return LocationFix(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracy,
    timestamp: DateTime.utc(2026, 8, 20).add(elapsed),
    monitoringElapsed: elapsed,
  );
}

Future<void> _pumpAsyncWork(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}
