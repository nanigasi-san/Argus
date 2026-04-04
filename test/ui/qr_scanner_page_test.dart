import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/io/config.dart';
import 'package:argus/io/file_manager.dart';
import 'package:argus/io/logger.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/ui/qr_scanner_page.dart';
import 'package:permission_handler/permission_handler.dart';

import '../support/notifier_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QrScannerPage', () {
    testWidgets('displays scanner page with app bar',
        (WidgetTester tester) async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: _FakeLocationService(),
        fileManager: _FakeFileManager(config: config),
        logger: _FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
              value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerOverride: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // AppBarのタイトルを確認
      expect(find.text('Scan QR Code'), findsOneWidget);
    });

    testWidgets('can navigate back', (WidgetTester tester) async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: _FakeLocationService(),
        fileManager: _FakeFileManager(config: config),
        logger: _FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppController>.value(
              value: controller,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => QrScannerPage(
                          permissionCoordinator: _FakePermissionCoordinator(),
                          scannerOverride: const ColoredBox(color: Colors.black),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Scanner'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // スキャナーページを開く
      await tester.tap(find.text('Open Scanner'));
      await tester.pumpAndSettle();

      expect(find.text('Scan QR Code'), findsOneWidget);

      // 戻るボタンをタップ
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Open Scanner'), findsOneWidget);
    });

    testWidgets('shows permission error when camera is denied',
        (WidgetTester tester) async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: _FakeLocationService(),
        fileManager: _FakeFileManager(config: config),
        logger: _FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _DeniedCameraPermissionCoordinator(),
              scannerOverride: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('カメラ権限'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });
  });
}

AppConfig _testConfig() {
  return AppConfig(
    innerBufferM: 5,
    leaveConfirmSamples: 1,
    leaveConfirmSeconds: 1,
    gpsAccuracyBadMeters: 50,
    sampleIntervalS: {'fast': 1},
    sampleDistanceM: {'fast': 1},
    screenWakeOnLeave: false,
    alarmVolume: 1.0,
  );
}

class _FakeFileManager extends FileManager {
  _FakeFileManager({required this.config});

  final AppConfig config;

  @override
  Future<AppConfig> readConfig() async => config;
}

class _FakeEventLogger extends EventLogger {
  _FakeEventLogger() : super();
}

class _FakeLocationService implements LocationService {
  _FakeLocationService();

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    return const LocationServiceStartResult.started();
  }

  @override
  Future<void> stop() async {}

  @override
  Stream<LocationFix> get stream => const Stream.empty();
}

class _FakePermissionGateway implements PermissionGateway {
  @override
  Future<PermissionStatus> cameraStatus() async => PermissionStatus.granted;

  @override
  Future<PermissionStatus> locationAlwaysStatus() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> locationWhenInUseStatus() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> notificationStatus() async => PermissionStatus.granted;

  @override
  Future<PermissionStatus> requestCamera() async => PermissionStatus.granted;

  @override
  Future<PermissionStatus> requestLocationAlways() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> requestLocationWhenInUse() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> requestNotification() async => PermissionStatus.granted;
}

class _FakePermissionCoordinator extends PermissionCoordinator {
  _FakePermissionCoordinator()
      : super(
          gateway: _FakePermissionGateway(),
          openSettings: () async => true,
          openLocationSettings: () async => true,
          locationServicesEnabled: () async => true,
        );
}

class _DeniedCameraPermissionGateway extends _FakePermissionGateway {
  @override
  Future<PermissionStatus> cameraStatus() async => PermissionStatus.denied;

  @override
  Future<PermissionStatus> requestCamera() async => PermissionStatus.denied;
}

class _DeniedCameraPermissionCoordinator extends PermissionCoordinator {
  _DeniedCameraPermissionCoordinator()
      : super(
          gateway: _DeniedCameraPermissionGateway(),
          openSettings: () async => true,
          openLocationSettings: () async => true,
          locationServicesEnabled: () async => true,
        );
}
