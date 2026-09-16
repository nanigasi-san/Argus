// ignore_for_file: prefer_const_constructors

import 'package:argus/theme/app_theme.dart';
import 'package:argus/ui/compass_navigation_card.dart';
import 'package:argus/platform/location_service.dart' show LocationFix;
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import '../support/test_doubles.dart';

void main() {
  setUpAll(() async {
    final regular = FontLoader('BIZ UDPGothic')
      ..addFont(rootBundle.load('assets/fonts/BIZUDPGothic-Regular.ttf'));
    final bold = FontLoader('BIZ UDPGothic')
      ..addFont(rootBundle.load('assets/fonts/BIZUDPGothic-Bold.ttf'));
    await Future.wait([regular.load(), bold.load()]);
  });

  test('calculates direction relative to the device heading', () {
    expect(
      relativeBearingDegrees(targetBearingDeg: 90, deviceHeadingDeg: 0),
      90,
    );
    expect(
      relativeBearingDegrees(targetBearingDeg: 10, deviceHeadingDeg: 350),
      20,
    );
    expect(
      relativeBearingDegrees(targetBearingDeg: 0, deviceHeadingDeg: 90),
      270,
    );
  });

  testWidgets('renders an active compass direction', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CompassNavigationCard(
            targetBearingDeg: 90,
            deviceHeadingDeg: 0,
            distanceToBoundaryM: 72,
            compassAvailable: true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('compassTargetArrow')), findsOneWidget);
    expect(find.text('72 m'), findsOneWidget);
    expect(find.text('端末を右へあと 90° 回してください'), findsOneWidget);
  });

  testWidgets('tells the user to move forward within 30 degrees',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CompassNavigationCard(
            targetBearingDeg: 30,
            deviceHeadingDeg: 0,
            distanceToBoundaryM: 100,
            compassAvailable: true,
          ),
        ),
      ),
    );

    expect(find.text('そのまま画面上方向へ進んでください'), findsOneWidget);
    expect(find.text('進行方向の範囲内（±30°）です'), findsOneWidget);
  });

  testWidgets('tells the user to turn left for a left-side target',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CompassNavigationCard(
            targetBearingDeg: 270,
            deviceHeadingDeg: 0,
            distanceToBoundaryM: 100,
            compassAvailable: true,
          ),
        ),
      ),
    );

    expect(find.text('端末を左へあと 90° 回してください'), findsOneWidget);
  });

  testWidgets('formats a long boundary distance in kilometers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CompassNavigationCard(
            targetBearingDeg: 0,
            deviceHeadingDeg: 0,
            distanceToBoundaryM: 1234,
            compassAvailable: true,
          ),
        ),
      ),
    );

    expect(find.text('1.23 km'), findsOneWidget);
  });

  testWidgets('explains when a compass reading is unavailable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CompassNavigationCard(
            targetBearingDeg: 90,
            deviceHeadingDeg: null,
            distanceToBoundaryM: 72,
            compassAvailable: false,
          ),
        ),
      ),
    );

    expect(find.text('端末コンパスを取得中です'), findsOneWidget);
  });

  test('uses simulated location and compass readings for navigation', () async {
    final compass = FakeCompassService();
    final controller = buildTestController(
      hasGeoJson: true,
      compassService: compass,
      permissionCoordinator: _GrantedPermissionCoordinator(),
    );
    final location = controller.locationService as FakeLocationService;

    await controller.startMonitoring();
    compass.add(450);
    final timestamp = DateTime.now();
    location.add(
      LocationFix(
        latitude: 2,
        longitude: 2,
        timestamp: timestamp,
        accuracyMeters: 4,
      ),
    );
    location.add(
      LocationFix(
        latitude: 2,
        longitude: 2,
        timestamp: timestamp.add(const Duration(seconds: 2)),
        accuracyMeters: 4,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.compassHeadingDeg, 90);
    expect(controller.compassAvailable, isTrue);
    expect(controller.snapshot.status, LocationStateStatus.outer);
    expect(controller.snapshot.bearingToBoundaryDeg, isNotNull);

    controller.dispose();
    await compass.dispose();
  });

  test('clears the navigation heading when the compass reports an error',
      () async {
    final compass = FakeCompassService();
    final controller = buildTestController(
      hasGeoJson: true,
      compassService: compass,
    );

    controller.setDeveloperMode(true);
    compass.add(90);
    await Future<void>.delayed(Duration.zero);
    compass.addError(StateError('sensor unavailable'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.compassHeadingDeg, isNull);
    expect(controller.compassAvailable, isFalse);

    controller.dispose();
    await compass.dispose();
  });
}

class _GrantedPermissionCoordinator extends PermissionCoordinator {
  @override
  Future<MonitoringPermissionState> refreshMonitoringPermissionState() async {
    return const MonitoringPermissionState(
      notificationStatus: PermissionStatus.granted,
      locationWhenInUseStatus: PermissionStatus.granted,
      locationAlwaysStatus: PermissionStatus.granted,
      locationServicesEnabled: true,
    );
  }
}
