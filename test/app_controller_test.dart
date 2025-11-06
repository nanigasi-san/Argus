import 'package:flutter_test/flutter_test.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/state_machine/state_machine.dart';

import 'support/notifier_fakes.dart';
import 'support/test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppController', () {
    test('loading new GeoJSON resets to init and stops alarm', () async {
      final config = createTestConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = FakeEventLogger();
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
      );

      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
      );

      await notifier.notifyOuter();
      expect(alarm.playCount, 1);

      await controller.reloadGeoJsonFromPicker();
      expect(controller.snapshot.status, LocationStateStatus.waitStart);

      expect(controller.snapshot.status, LocationStateStatus.waitStart);
      expect(controller.hasGeoJson, isTrue);
      expect(stateMachine.current, LocationStateStatus.waitStart);
      expect(alarm.stopCount, 1);
    });

    test('describeSnapshot hides navigation details before OUTER', () {
      final controller = _buildController();
      final snapshot = StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.now(),
        distanceToBoundaryM: 42.5,
        horizontalAccuracyM: 5,
        bearingToBoundaryDeg: 123,
        nearestBoundaryPoint: const LatLng(1, 2),
      );

      final description = controller.describeSnapshot(snapshot);

      expect(description, contains('status=inner'));
      expect(description, contains('dist=-'));
      expect(description, contains('bearing=-'));
      expect(description.contains('1.00000'), isFalse);
    });

    test('describeSnapshot reveals navigation details in developer mode', () {
      final controller = _buildController();
      controller.setDeveloperMode(true);
      final snapshot = StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.now(),
        distanceToBoundaryM: 42.5,
        horizontalAccuracyM: 5,
        bearingToBoundaryDeg: 123,
        nearestBoundaryPoint: const LatLng(1, 2),
      );

      final description = controller.describeSnapshot(snapshot);

      expect(description, contains('status=inner'));
      expect(description.contains('dist=-'), isFalse);
      expect(description.contains('bearing=-'), isFalse);
      expect(description, contains('42.50m'));
      expect(description, contains('123deg'));
      expect(description, contains('(1.00000,2.00000)'));
    });
  });
}

AppController _buildController() {
  final config = createTestConfig();
  final stateMachine = StateMachine(config: config);
  final fileManager = FakeFileManager(config: config);
  final notifier = Notifier(
    notificationsClient: FakeLocalNotificationsClient(),
    alarmPlayer: FakeAlarmPlayer(),
  );
  return AppController(
    stateMachine: stateMachine,
    locationService: FakeLocationService(),
    fileManager: fileManager,
    logger: FakeEventLogger(),
    notifier: notifier,
  );
}
