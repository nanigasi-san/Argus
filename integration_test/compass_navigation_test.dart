import 'package:argus/platform/location_service.dart';
import 'package:argus/state_machine/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/test_doubles.dart' as doubles;
import 'support/app_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('outside navigation follows location and device heading',
      (tester) async {
    final location = doubles.FakeLocationService();
    final compass = doubles.FakeCompassService();
    final controller = HarnessBuilder.buildController(
      hasGeoJson: true,
      locationService: location,
      compassService: compass,
      permissionCoordinator: HarnessPermissionCoordinator(),
    );
    addTearDown(() async {
      await controller.stopMonitoring();
      controller.dispose();
      await compass.dispose();
    });
    await tester.pumpWidget(HarnessBuilder.buildApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('タップで開始'));
    await tester.pumpAndSettle();
    expect(location.hasStarted, isTrue);

    Future<void> fix(double longitude, int seconds) async {
      location.add(LocationFix(
        latitude: 0.5,
        longitude: longitude,
        accuracyMeters: 5,
        timestamp: DateTime.utc(2026, 9, 16).add(Duration(seconds: seconds)),
        monitoringElapsed: Duration(seconds: seconds),
      ));
      await tester.pumpAndSettle();
    }

    await fix(0.5, 0);
    expect(controller.snapshot.status, LocationStateStatus.inner);
    expect(find.byKey(const Key('compassStatusPointer')), findsNothing);
    await fix(1.001, 1);
    await fix(1.001, 3);
    expect(controller.snapshot.status, LocationStateStatus.outer);
    expect(find.text('方角を確認中'), findsOneWidget);
    final target = controller.snapshot.bearingToBoundaryDeg!;
    expect(target, closeTo(270, 1));
    expect(controller.snapshot.distanceToBoundaryM, closeTo(111, 2));

    Future<void> heading(double? value, String guidance) async {
      compass.add(value);
      await tester.pumpAndSettle();
      expect(find.text(guidance), findsOneWidget);
    }

    await heading(target - 90, '90度左を向いてください');
    expect(find.byKey(const Key('compassStatusPointer')), findsOneWidget);
    for (final label in ['北', '東', '南', '西']) {
      expect(find.text(label), findsOneWidget);
    }
    await binding.takeScreenshot('compass-right');
    await heading(target + 90, '90度右を向いてください');
    await heading(target - 29, '前へ');
    await binding.takeScreenshot('compass-forward');
    await heading(target - 31, '31度左を向いてください');
    await heading(null, '方角を確認中');
    expect(find.byKey(const Key('compassStatusPointer')), findsNothing);
    await heading(target, '前へ');
    await fix(1.0005, 4);
    expect(controller.snapshot.distanceToBoundaryM, closeTo(56, 2));
    await fix(0.5, 5);
    expect(controller.snapshot.status, LocationStateStatus.inner);
    expect(find.text('前へ'), findsNothing);
    expect(find.byKey(const Key('compassStatusPointer')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('finish-race-button')));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('finish-race-button'))),
    );
    await tester.pump(const Duration(seconds: 6));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(location.hasStopped, isTrue);
    expect(controller.snapshot.status, LocationStateStatus.waitStart);
  });

  if (const bool.fromEnvironment('SIMULATOR_GPS')) {
    testWidgets('iOS native virtual GPS enters and leaves navigation',
        (tester) async {
      expect(defaultTargetPlatform, TargetPlatform.iOS,
          reason: 'SIMULATOR_GPS is only supported by the iOS simulator');
      final controller = HarnessBuilder.buildController(
        hasGeoJson: true,
        locationService: GeolocatorLocationService(),
        permissionCoordinator: HarnessPermissionCoordinator(),
      );
      addTearDown(() async {
        await controller.stopMonitoring();
        controller.dispose();
      });
      await tester.pumpWidget(HarnessBuilder.buildApp(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('タップで開始'));

      Future<void> waitFor(LocationStateStatus status) async {
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(seconds: 1));
          expect(controller.lastErrorMessage, isNull,
              reason: 'Native location monitoring could not start');
          if (controller.snapshot.status == status) return;
        }
        fail('Expected $status, got ${controller.snapshot.status}: '
            '${controller.lastErrorMessage}');
      }

      await waitFor(LocationStateStatus.outer);
      expect(controller.snapshot.distanceToBoundaryM, greaterThan(50));
      expect(find.text('方角を確認中'), findsOneWidget);
      await binding.takeScreenshot('compass-native-outside');
      await waitFor(LocationStateStatus.inner);
      expect(find.byKey(const Key('compassStatusPointer')), findsNothing);
      expect(find.text('方角を確認中'), findsNothing);
      await binding.takeScreenshot('compass-native-inside');
    });
  }
}
