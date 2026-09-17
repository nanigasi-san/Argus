import 'package:argus/geo/geo_model.dart';
import 'package:argus/main.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/core_e2e_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late CoreE2eHarness harness;

  void scenario(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      CoreE2eHarness? currentHarness;
      try {
        // Keep setup and cleanup inside runTest so flutter drive reports
        // their failures too (test_api setUp failures can be missed).
        await binding.convertFlutterSurfaceToImage();
        harness = await CoreE2eHarness.create();
        currentHarness = harness;
        await body(tester);
        await binding.takeScreenshot('core-$name');
      } catch (_) {
        // Preserve the screen before cleanup when an assertion fails.
        try {
          await binding.takeScreenshot('core-$name-failure');
        } catch (error) {
          debugPrint('Could not capture failure screenshot: $error');
        }
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await currentHarness?.dispose();
      }
    });
  }

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(ArgusApp(controller: harness.controller));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(harness.controller.snapshot.status, LocationStateStatus.waitGeoJson);
    expect(find.text('WAIT GEOJSON'), findsOneWidget);
    expect(await harness.loadGeoJson(), isTrue,
        reason: harness.controller.lastErrorMessage);
    await tester.pumpAndSettle();
    expect(harness.controller.geoJsonLoaded, isTrue);
    expect(harness.controller.snapshot.status, LocationStateStatus.waitStart);
    expect(find.text('WAIT START'), findsOneWidget);
    expect(harness.controller.geoJsonFileName, 'core_square.geojson');
    expect(harness.controller.config!.leaveConfirmSamples, 3);
    expect(harness.controller.config!.leaveConfirmSeconds, 10);
  }

  Future<void> start(WidgetTester tester) async {
    final starts = harness.location.startCount;
    final button = find.byKey(const Key('monitoringStatusButton'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(harness.location.startCount, starts + 1);
    expect(harness.location.running, isTrue);
    expect(harness.location.activeSubscriptions, 1);
  }

  Future<void> emit(WidgetTester tester, LatLng point, int seconds,
      LocationStateStatus expected,
      {double accuracy = 5}) async {
    final fix = harness.fix(point, seconds, accuracy: accuracy);
    final previousFixCount = harness.logger.fixes.length;
    harness.location.emit(fix);
    await tester.pumpAndSettle();
    expect(harness.logger.fixes.length, previousFixCount + 1);
    expect(harness.controller.snapshot.timestamp, fix.timestamp);
    expect(harness.controller.snapshot.status, expected);
    expect(harness.controller.notifier.badgeState.value, expected);
    const labels = {
      LocationStateStatus.inner: 'INNER',
      LocationStateStatus.near: 'NEAR',
      LocationStateStatus.outerPending: 'OUTER PENDING',
      LocationStateStatus.outer: 'OUTER',
      LocationStateStatus.gpsBad: 'GPS BAD',
    };
    final text =
        tester.widget<Text>(find.byKey(const Key('monitoringStatusText')));
    expect(text.data, labels[expected]);
  }

  void expectAlert(bool playing) {
    expect(harness.alarm.playing, playing);
    expect(harness.vibration.playing, playing);
    expect(harness.notifications.activeIds, playing ? isNotEmpty : isEmpty);
  }

  Future<void> exitArea(WidgetTester tester) async {
    await emit(tester, inside, 0, LocationStateStatus.inner);
    await emit(tester, outside, 1, LocationStateStatus.outerPending);
    expectAlert(false);
    await emit(tester, outside, 5, LocationStateStatus.outerPending);
    expectAlert(false);
    await emit(tester, outside, 11, LocationStateStatus.outer);
    expectAlert(true);
    expect(harness.notifications.showCount, 1);
    expect(harness.alarm.startCount, 1);
  }

  Future<void> stop(WidgetTester tester) async {
    final stopCount = harness.location.stopCount;
    final button = find.byKey(const Key('finish-race-button'));
    await tester.ensureVisible(button);
    final gesture = await tester.startGesture(tester.getCenter(button));
    // This duration is the actual UI hold gesture, not GPS hysteresis.
    await tester.pump(const Duration(seconds: 5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.location.stopCount, stopCount + 1);
    expect(harness.location.running, isFalse);
    expect(harness.location.activeSubscriptions, 0);
    expect(harness.controller.snapshot.status, LocationStateStatus.waitStart);
    expect(find.text('WAIT START'), findsOneWidget);
    expectAlert(false);
    final fixes = harness.logger.fixes.length;
    harness.location.emit(harness.fix(outside, 100));
    await tester.pumpAndSettle();
    expect(harness.logger.fixes.length, fixes);
    expect(harness.controller.snapshot.status, LocationStateStatus.waitStart);
  }

  scenario('monitor-exit-recover', (tester) async {
    await boot(tester);
    await start(tester);
    await exitArea(tester);
    await binding.takeScreenshot('core-confirmed-outer');
    final alarmStops = harness.alarm.stopCount;
    final cancellations = harness.notifications.cancelCount;
    await emit(tester, inside, 12, LocationStateStatus.inner);
    expectAlert(false);
    expect(harness.alarm.stopCount, alarmStops + 1);
    expect(harness.notifications.cancelCount, cancellations + 1);
  });

  scenario('gps-bad-recover', (tester) async {
    await boot(tester);
    await start(tester);
    await emit(tester, inside, 0, LocationStateStatus.inner);
    await emit(tester, outside, 1, LocationStateStatus.gpsBad, accuracy: 100);
    expectAlert(false);
    expect(harness.notifications.showCount, 0);
    await emit(tester, inside, 2, LocationStateStatus.inner);
    expectAlert(false);
    expect(harness.alarm.startCount, 0);
  });

  scenario('outer-survives-low-accuracy', (tester) async {
    await boot(tester);
    await start(tester);
    await exitArea(tester);
    final stops = harness.alarm.stopCount;
    final cancellations = harness.notifications.cancelCount;
    await emit(tester, outside, 12, LocationStateStatus.outer, accuracy: 100);
    expectAlert(true);
    expect(harness.alarm.stopCount, stops);
    expect(harness.notifications.cancelCount, cancellations);
    expect(harness.notifications.showCount, 1);
    await emit(tester, inside, 13, LocationStateStatus.inner, accuracy: 100);
    expectAlert(false);
  });

  scenario('stop-restart-clears-pending', (tester) async {
    await boot(tester);
    await start(tester);
    await emit(tester, inside, 0, LocationStateStatus.inner);
    await emit(tester, outside, 1, LocationStateStatus.outerPending);
    await emit(tester, outside, 5, LocationStateStatus.outerPending);
    await stop(tester);
    await start(tester);
    // A far later first fix must not inherit the prior run's two samples.
    await emit(tester, outside, 50, LocationStateStatus.outerPending);
    expect(harness.controller.stateMachine.pendingSampleCount, 1);
    expectAlert(false);
    await emit(tester, inside, 51, LocationStateStatus.inner);
    expect(harness.location.startCount, 2);
    expect(harness.location.deliveredFixCount, harness.logger.fixes.length);
  });

  scenario('stop-restart-clears-alarm', (tester) async {
    await boot(tester);
    await start(tester);
    await exitArea(tester);
    await stop(tester);
    await start(tester);
    await emit(tester, outside, 50, LocationStateStatus.outerPending);
    expectAlert(false);
    await emit(tester, inside, 51, LocationStateStatus.inner);
    expectAlert(false);
    expect(harness.location.startCount, 2);
    expect(harness.notifications.showCount, 1);
    expect(harness.location.deliveredFixCount, harness.logger.fixes.length);
  });

  scenario('permission-setup-refresh-start', (tester) async {
    harness.permissions.granted = false;
    await harness.controller.refreshMonitoringPermissionState();
    await boot(tester);
    expect(harness.controller.canStartMonitoring, isFalse);
    expect(find.text('監視開始前に位置情報の設定が必要です'), findsOneWidget);
    await tester.tap(find.text('監視開始前に設定する'));
    await tester.pumpAndSettle();
    expect(find.text('バックグラウンド位置情報の開示'), findsOneWidget);
    // OS still denies permission: disclosure alone must not permit START.
    await tester.tap(find.text(defaultTargetPlatform == TargetPlatform.iOS
        ? '続ける'
        : '同意して位置情報の設定へ進む'));
    await tester.pumpAndSettle();
    expect(harness.controller.canStartMonitoring, isFalse);
    expect(harness.location.startCount, 0);
    harness.permissions.granted = true;
    await tester.tap(find.text('状態を更新'));
    await tester.pumpAndSettle();
    expect(harness.controller.canStartMonitoring, isTrue);
    expect(find.text('監視開始前に位置情報の設定が必要です'), findsNothing);
    await start(tester);
    await emit(tester, inside, 0, LocationStateStatus.inner);
    expectAlert(false);
  });

  scenario('settings-update-monitoring-buffer', (tester) async {
    await boot(tester);
    await start(tester);
    await emit(tester, bufferProbe, 0, LocationStateStatus.inner);
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('innerBufferField')), '50');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('saveSettingsButton'));
    await tester.scrollUntilVisible(save, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(save.hitTestable());
    await tester.pumpAndSettle();
    expect(harness.controller.config!.innerBufferM, 50);
    expect(harness.location.lastStartConfig!.innerBufferM, 50);
    expect(harness.location.startCount, 2);
    expect(harness.location.activeSubscriptions, 1);
    expect(
        (await harness.controller.fileManager.readConfig()).innerBufferM, 50);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await emit(tester, bufferProbe, 0, LocationStateStatus.near);
    expectAlert(false);
  });

  scenario('outer-snooze-keeps-state', (tester) async {
    await boot(tester);
    await start(tester);
    await exitArea(tester);
    final button = find.text('1分間音を停止する');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(harness.controller.snapshot.status, LocationStateStatus.outer);
    expect(harness.controller.isAlarmSnoozed, isTrue);
    expect(harness.alarm.playing, isFalse);
    expect(harness.vibration.playing, isFalse);
    expect(find.text('OUTER'), findsOneWidget);
    await emit(tester, outside, 12, LocationStateStatus.outer);
    expect(harness.alarm.playing, isFalse);
    expect(harness.notifications.showCount, 1);
    await emit(tester, inside, 13, LocationStateStatus.inner);
    expect(harness.controller.isAlarmSnoozed, isFalse);
    expectAlert(false);
  });
}
