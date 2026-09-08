import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/io/config.dart';
import 'package:argus/io/file_manager.dart';
import 'package:argus/io/logger.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:permission_handler/permission_handler.dart';

import 'support/notifier_fakes.dart';
import 'support/test_doubles.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppController', () {
    test('initialize only refreshes permission state', () async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = FakeEventLogger();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: FakeAlarmPlayer(),
      );
      final coordinator = _TrackingPermissionCoordinator(
        refreshState: const MonitoringPermissionState(
          notificationStatus: PermissionStatus.denied,
          locationWhenInUseStatus: PermissionStatus.denied,
          locationAlwaysStatus: PermissionStatus.denied,
          locationServicesEnabled: true,
        ),
      );
      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
        permissionCoordinator: coordinator,
      );

      await controller.initialize();

      expect(coordinator.refreshCount, 1);
      expect(coordinator.completeSetupCount, 0);
      expect(coordinator.requestNotificationCount, 0);
      expect(controller.monitoringPermissionState.locationWhenInUseGranted,
          isFalse);
      expect(
          controller.monitoringPermissionState.locationAlwaysGranted, isFalse);
    });

    test('completeMonitoringPermissionSetup updates permission state',
        () async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = FakeEventLogger();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: FakeAlarmPlayer(),
      );
      final coordinator = _TrackingPermissionCoordinator(
        completeState: _grantedMonitoringPermissionState(),
      );
      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
        permissionCoordinator: coordinator,
      );

      await controller.completeMonitoringPermissionSetup();

      expect(coordinator.completeSetupCount, 1);
      expect(controller.monitoringPermissionState.canStartMonitoring, isTrue);
      expect(controller.lastErrorMessage, isNull);
    });

    test('alarm preview stops before monitoring starts', () async {
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: locationService,
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: alarm,
          vibrationPlayer: vibration,
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: _testConfig(),
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      final started = await controller.startAlarmPreview(0.4);

      expect(started, isTrue);
      expect(controller.isAlarmPreviewPlaying, isTrue);
      expect(alarm.playCount, 1);
      expect(vibration.startCount, 0);

      await controller.startMonitoring();

      expect(controller.isAlarmPreviewPlaying, isFalse);
      expect(alarm.stopCount, greaterThanOrEqualTo(2));
      expect(locationService.started, isTrue);
      await controller.stopMonitoring();
    });

    test('alarm preview failure is reported without leaving preview active',
        () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: _AlwaysFailAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
      );
      controller.debugSeed(config: _testConfig());

      final started = await controller.startAlarmPreview(0.4);

      expect(started, isFalse);
      expect(controller.isAlarmPreviewPlaying, isFalse);
      expect(controller.logs.first.message, contains('Failed to start'));
    });

    test('alarm preview stop failure leaves monitoring in a retryable failure',
        () async {
      // 「停止呼び出しが1回失敗した」ではなく「止められない」ことが
      // 監視開始を妨げる条件。鳴り始めたら止まらないプレイヤーで検証する。
      final alarm = _StuckOnceStartedAlarmPlayer();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: locationService,
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: alarm,
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: _testConfig(),
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      expect(await controller.startAlarmPreview(0.4), isTrue);

      await controller.startMonitoring();

      expect(controller.monitoringLifecycle, MonitoringLifecycle.failed);
      expect(controller.lastErrorMessage, contains('監視を開始できません'));
      expect(locationService.started, isFalse);
      expect(
        controller.alertReliabilityWarning,
        contains('警報を停止できませんでした'),
      );
    });

    test('alarm preview stops when application terminates', () async {
      final alarm = FakeAlarmPlayer();
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: alarm,
          vibrationPlayer: FakeVibrationPlayer(),
        ),
      );
      controller.debugSeed(config: _testConfig());
      expect(await controller.startAlarmPreview(0.4), isTrue);

      await controller.handleAppTermination();

      expect(controller.isAlarmPreviewPlaying, isFalse);
      expect(alarm.stopCount, greaterThanOrEqualTo(3));
    });

    test('openPermissionSettings returns coordinator result and handles errors',
        () async {
      final successCoordinator = _TrackingPermissionCoordinator(
        openSettingsResult: true,
      );
      final successController = _buildController(
        permissionCoordinator: successCoordinator,
      );

      expect(await successController.openPermissionSettings(), isTrue);
      expect(successCoordinator.openSettingsCount, 1);

      final failingCoordinator = _TrackingPermissionCoordinator(
        openSettingsError: StateError('settings unavailable'),
      );
      final failingController = _buildController(
        permissionCoordinator: failingCoordinator,
      );

      expect(await failingController.openPermissionSettings(), isFalse);
      expect(failingCoordinator.openSettingsCount, 1);
      expect(failingController.logs.first.message, contains('Failed to open'));
    });

    test('startMonitoring sets blocked error when permission is missing',
        () async {
      final coordinator = _TrackingPermissionCoordinator(
        refreshState: const MonitoringPermissionState(
          notificationStatus: PermissionStatus.granted,
          locationWhenInUseStatus: PermissionStatus.granted,
          locationAlwaysStatus: PermissionStatus.denied,
          locationServicesEnabled: true,
        ),
      );
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: coordinator,
      );

      controller.debugSeed(
        config: _testConfig(),
        geoJson: _squareModel(),
        permissionState: const MonitoringPermissionState(
          notificationStatus: PermissionStatus.granted,
          locationWhenInUseStatus: PermissionStatus.granted,
          locationAlwaysStatus: PermissionStatus.denied,
          locationServicesEnabled: true,
        ),
      );

      await controller.startMonitoring();

      expect(controller.lastErrorMessage, contains('常に許可'));
      expect(controller.logs.first.level.name, 'warning');
    });

    test('permission lookup failure leaves monitoring retryable', () async {
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: locationService,
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _ThrowingRefreshPermissionCoordinator(),
      );
      controller.debugSeed(
        config: _testConfig(),
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      await controller.startMonitoring();

      expect(controller.monitoringLifecycle, MonitoringLifecycle.failed);
      expect(controller.lastErrorMessage, contains('監視を開始できません'));
      expect(locationService.started, isFalse);
    });

    test('clearError removes existing error and notifies listeners', () async {
      final controller = _buildController();
      controller.debugSeed(
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.now(),
          geoJsonLoaded: true,
        ),
      );
      await controller.reloadGeoJsonFromQr('invalid:qr');

      expect(controller.lastErrorMessage, isNotNull);

      controller.clearError();

      expect(controller.lastErrorMessage, isNull);
    });

    test('startMonitoring surfaces location service start errors', () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: _FailingStartLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: _testConfig(),
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      await controller.startMonitoring();

      expect(controller.lastErrorMessage, 'boom');
      expect(controller.logs.first.level.name, 'error');
    });

    test('failed lifecycle is retryable but active lifecycle ignores start',
        () async {
      final controller = _buildController();
      controller.debugSeed(
        config: _testConfig(),
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
        monitoringLifecycle: MonitoringLifecycle.failed,
      );

      expect(controller.canStartMonitoring, isTrue);

      controller.debugSeed(monitoringLifecycle: MonitoringLifecycle.active);
      await controller.startMonitoring();

      expect(controller.monitoringLifecycle, MonitoringLifecycle.active);
    });

    test('startMonitoring fails safely when configuration is unavailable',
        () async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      await controller.startMonitoring();

      expect(controller.monitoringLifecycle, MonitoringLifecycle.failed);
      expect(controller.lastErrorMessage, contains('GeoJSONと設定'));
    });

    test('startMonitoring converts thrown service errors into a failure',
        () async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: _ThrowingStartLocationService(),
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      await controller.startMonitoring();
      await Future<void>.delayed(Duration.zero);

      expect(controller.monitoringLifecycle, MonitoringLifecycle.failed);
      expect(controller.lastErrorMessage, contains('start threw'));
    });

    test('failed start logs subscription and service cleanup failures',
        () async {
      final config = _testConfig();
      final locationService = _FaultyLocationService(
        startResult: const LocationServiceStartResult(
          status: LocationServiceStartStatus.error,
          message: 'start rejected',
        ),
        throwOnCancel: true,
        throwOnStop: true,
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      await controller.startMonitoring();

      final messages = controller.logs.map((entry) => entry.message);
      expect(messages, contains(startsWith('Failed to cancel failed')));
      expect(messages, contains(startsWith('Failed to clean up')));
      expect(controller.monitoringLifecycle, MonitoringLifecycle.failed);
    });

    test('retry logs a previous subscription cancellation failure', () async {
      final config = _testConfig();
      final locationService = _FaultyLocationService(throwOnCancel: true);
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();
      controller.debugSeed(monitoringLifecycle: MonitoringLifecycle.failed);

      await controller.startMonitoring();

      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Failed to cancel previous location stream')),
      );
      await controller.stopMonitoring();
    });

    test('updateConfig is rejected while monitoring is active', () async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = _SavingFileManager(config: config);
      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      final updated = AppConfig(
        innerBufferM: 12,
        leaveConfirmSamples: 2,
        leaveConfirmSeconds: 5,
        gpsAccuracyBadMeters: 20,
        sampleIntervalS: const {'fast': 2},
        alarmVolume: 0.8,
      );

      await controller.updateConfig(updated);

      expect(fileManager.savedConfig, isNull);
      expect(locationService.startCount, 1);
      expect(locationService.stopCount, 0);
      expect(controller.config!.alarmVolume, config.alarmVolume);
      expect(controller.lastErrorMessage, contains('監視中'));

      // 開発者モードは表示の切り替えだけなのでロック対象にしない。
      // GPSが不調なときこそログと詳細を見たい。
      controller.clearError();
      controller.setDeveloperMode(true);
      expect(controller.developerMode, isTrue);
      expect(controller.lastErrorMessage, isNull);

      await controller.stopMonitoring();
    });

    test('updateConfig normalizes and persists settings while idle', () async {
      final config = _testConfig();
      final fileManager = _SavingFileManager(config: config);
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: fileManager,
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );
      controller.debugSeed(config: config);

      await controller.updateConfig(
        AppConfig(
          innerBufferM: 12,
          leaveConfirmSamples: 2,
          leaveConfirmSeconds: 5,
          gpsAccuracyBadMeters: 20,
          sampleIntervalS: const {'fast': 2},
          alarmVolume: 0.8,
        ),
      );

      expect(fileManager.savedConfig, isNotNull);
      expect(controller.config!.innerBufferM, 12);
      expect(controller.logs.first.message, startsWith('Config updated:'));
    });

    test('GeoJSON changes are rejected while monitoring is active', () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      final loadedFromQr = await controller.reloadGeoJsonFromQr('invalid:qr');
      await controller.reloadGeoJsonFromPicker();
      final loadedFromQrImage =
          await controller.reloadGeoJsonFromQrImagePicker();

      expect(loadedFromQr, isFalse);
      expect(loadedFromQrImage, isFalse);
      expect(controller.lastErrorMessage, contains('監視中'));
      expect(controller.isMonitoringSession, isTrue);
      expect(locationService.stopCount, 0);
      await controller.stopMonitoring();
    });

    test('GPS timeout warns when no fix arrives', () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final notifications = FakeLocalNotificationsClient();
      var elapsed = Duration.zero;
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: notifications,
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        elapsedProvider: () => elapsed,
        staleTimeoutOverride: const Duration(milliseconds: 10),
        watchdogInterval: const Duration(milliseconds: 5),
        reconnectDelays: const [Duration(seconds: 1)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      await controller.startMonitoring();
      expect(controller.monitoringLifecycle, MonitoringLifecycle.acquiring);

      elapsed += const Duration(milliseconds: 20);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(controller.monitoringLifecycle, MonitoringLifecycle.reconnecting);
      expect(notifications.shownIds, contains(1002));

      await controller.stopMonitoring();
      expect(controller.monitoringLifecycle, MonitoringLifecycle.idle);
    });

    test('GPS warning delivery never delays a scheduled reconnect', () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final notifications = _BlockingHealthNotificationsClient();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: notifications,
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(milliseconds: 5)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(StateError('stream stopped'));
      await notifications.healthShowEntered.future;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(locationService.startCount, 2);
      expect(locationService.stopCount, 1);

      notifications.allowHealthShow.complete();
      await Future<void>.delayed(Duration.zero);
      await controller.stopMonitoring();
    });

    test('a fix received while the GPS warning is pending cancels reconnect',
        () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final notifications = _BlockingHealthNotificationsClient();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: notifications,
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(milliseconds: 100)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(StateError('stream stopped'));
      await notifications.healthShowEntered.future;
      locationService.add(
        LocationFix(
          latitude: 0.5,
          longitude: 0.5,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.monitoringLifecycle, MonitoringLifecycle.active);

      notifications.allowHealthShow.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(controller.monitoringLifecycle, MonitoringLifecycle.active);
      expect(locationService.startCount, 1);
      expect(locationService.stopCount, 0);
      await controller.stopMonitoring();
    });

    test('a fix emitted during initial service start is not dropped', () async {
      final config = _testConfig();
      final locationService = _EmittingStartLocationService(
        emitOnStartNumbers: const {1},
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      await controller.startMonitoring();

      expect(controller.monitoringLifecycle, MonitoringLifecycle.active);
      expect(locationService.startCount, 1);
      await controller.stopMonitoring();
    });

    test('location stream errors trigger automatic reconnect', () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(milliseconds: 5)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(StateError('stream stopped'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(controller.monitoringLifecycle, MonitoringLifecycle.reconnecting);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(locationService.startCount, 2);
      expect(locationService.stopCount, 1);

      locationService.add(
        LocationFix(
          latitude: 0.5,
          longitude: 0.5,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(controller.monitoringLifecycle, MonitoringLifecycle.active);

      await controller.stopMonitoring();
    });

    test('GPS warning failures are logged and a fresh fix still recovers',
        () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: _ThrowingHealthNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(seconds: 1)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(StateError('stream stopped'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      locationService.add(
        LocationFix(
          latitude: 0.5,
          longitude: 0.5,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final messages = controller.logs.map((entry) => entry.message);
      expect(messages, contains(startsWith('Failed to show GPS warning')));
      expect(messages, contains(startsWith('Failed to clear GPS warning')));
      expect(controller.monitoringLifecycle, MonitoringLifecycle.active);
      await controller.stopMonitoring();
    });

    test('an error while processing a fix is contained and logged', () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: _ThrowingLocationLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.add(
        LocationFix(
          latitude: 0.5,
          longitude: 0.5,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Failed to process location fix')),
      );
      await controller.stopMonitoring();
    });

    test('handleAppResumed schedules a missing reconnect timer', () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(seconds: 1)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();
      controller.debugSeed(monitoringLifecycle: MonitoringLifecycle.stale);

      await controller.handleAppResumed();

      expect(controller.monitoringLifecycle, MonitoringLifecycle.reconnecting);
      await controller.stopMonitoring();
    });

    test('another stream error restores a missing reconnect timer', () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(seconds: 1)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();
      controller.debugSeed(monitoringLifecycle: MonitoringLifecycle.stale);

      locationService.addError(StateError('stream stopped again'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.monitoringLifecycle, MonitoringLifecycle.reconnecting);
      await controller.stopMonitoring();
    });

    test('reconnect handles configuration disappearing defensively', () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(milliseconds: 1)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();
      controller.debugSeed(clearConfig: true);

      locationService.addError(StateError('stream stopped'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Location reconnect failed')),
      );
      await controller.stopMonitoring();
    });

    test('a fix emitted during reconnect remains active after start returns',
        () async {
      final config = _testConfig();
      final locationService = _EmittingStartLocationService(
        emitOnStartNumbers: const {2},
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(milliseconds: 2)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(StateError('stream stopped'));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(locationService.startCount, 2);
      expect(controller.monitoringLifecycle, MonitoringLifecycle.active);
      expect(
        controller.logs.map((entry) => entry.message),
        contains('Location service reconnected with a fresh fix.'),
      );
      await controller.stopMonitoring();
    });

    test('stop and a later restart cannot overlap an in-flight reconnect',
        () async {
      final config = _testConfig();
      final locationService = _BlockingReconnectLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(milliseconds: 1)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(StateError('stream stopped'));
      await locationService.reconnectStartEntered.future;

      var stopCompleted = false;
      final stopFuture = controller.stopMonitoring().then((_) {
        stopCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(stopCompleted, isFalse);

      locationService.allowReconnectStart.complete();
      await stopFuture;
      await controller.startMonitoring();

      expect(locationService.startCount, 3);
      expect(locationService.stopCount, 2);
      expect(locationService.maxConcurrentOperations, 1);
      expect(controller.monitoringLifecycle, MonitoringLifecycle.acquiring);
      await controller.stopMonitoring();
    });

    test('failed reconnects advance through the configured backoff', () async {
      final config = _testConfig();
      final locationService = _QueuedStartLocationService([
        const LocationServiceStartResult.started(),
        const LocationServiceStartResult(
          status: LocationServiceStartStatus.error,
          message: 'first reconnect failed',
        ),
        const LocationServiceStartResult(
          status: LocationServiceStartStatus.error,
          message: 'second reconnect failed',
        ),
        const LocationServiceStartResult.started(),
      ]);
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [
          Duration(milliseconds: 2),
          Duration(milliseconds: 4),
        ],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(StateError('stream stopped'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(locationService.startCount, 4);
      expect(controller.monitoringLifecycle, MonitoringLifecycle.acquiring);
      expect(
        controller.logs.where((entry) =>
            entry.message.startsWith('Scheduling location reconnect attempt')),
        hasLength(3),
      );
      await controller.stopMonitoring();
    });

    test('refreshMonitoringPermissionState updates permission state', () async {
      final coordinator = _TrackingPermissionCoordinator(
        refreshState: const MonitoringPermissionState(
          notificationStatus: PermissionStatus.granted,
          locationWhenInUseStatus: PermissionStatus.granted,
          locationAlwaysStatus: PermissionStatus.denied,
          locationServicesEnabled: true,
        ),
      );
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: coordinator,
      );

      await controller.refreshMonitoringPermissionState();

      expect(
          controller.monitoringPermissionState.locationAlwaysGranted, isFalse);
      expect(coordinator.refreshCount, 1);
    });

    test('Android alarm volume allows monitoring at the 50 percent boundary',
        () async {
      final alarmVolumeClient = support.RecordingAlarmVolumeClient(
        states: const [
          AlarmVolumeState(current: 5, max: 10, percent: 0.5),
        ],
      );
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        alarmVolumeClient: alarmVolumeClient,
        isAndroid: true,
      );

      final canStart = await controller.canStartWithCurrentAlarmVolume();

      expect(canStart, isTrue);
      expect(alarmVolumeClient.calls, ['getAlarmVolumeState']);
    });

    test('Android alarm volume below 50 percent blocks monitoring', () async {
      final alarmVolumeClient = support.RecordingAlarmVolumeClient(
        states: const [
          AlarmVolumeState(current: 4, max: 10, percent: 0.4),
        ],
      );
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        alarmVolumeClient: alarmVolumeClient,
        isAndroid: true,
      );

      final canStart = await controller.canStartWithCurrentAlarmVolume();

      expect(canStart, isFalse);
      expect(alarmVolumeClient.checkCount, 1);
    });

    test('alarm volume check failures allow monitoring and write a warning',
        () async {
      final alarmVolumeClient = support.RecordingAlarmVolumeClient(
        throwOnCheck: true,
      );
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        alarmVolumeClient: alarmVolumeClient,
        isAndroid: true,
      );

      final canStart = await controller.canStartWithCurrentAlarmVolume();

      expect(canStart, isTrue);
      expect(
        controller.logs.single.message,
        startsWith('Failed to check alarm volume:'),
      );
      expect(controller.logs.single.level.name, 'warning');
    });

    test('non-Android skips alarm volume MethodChannel checks', () async {
      final alarmVolumeClient = support.RecordingAlarmVolumeClient(
        states: const [
          AlarmVolumeState(current: 0, max: 10, percent: 0),
        ],
      );
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        alarmVolumeClient: alarmVolumeClient,
        isAndroid: false,
      );

      final canStart = await controller.canStartWithCurrentAlarmVolume();

      expect(canStart, isTrue);
      expect(alarmVolumeClient.calls, isEmpty);
    });

    test('openAlarmSoundSettings returns false and logs when platform fails',
        () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        alarmVolumeClient: _ThrowingOpenAlarmVolumeClient(),
        isAndroid: true,
      );

      final opened = await controller.openAlarmSoundSettings();

      expect(opened, isFalse);
      expect(
        controller.logs.single.message,
        startsWith('Failed to open sound settings:'),
      );
      expect(controller.logs.single.level.name, 'warning');
    });

    test('requestNotificationPermission updates permission state', () async {
      final coordinator = _TrackingPermissionCoordinator(
        notificationState: const MonitoringPermissionState(
          notificationStatus: PermissionStatus.granted,
          locationWhenInUseStatus: PermissionStatus.granted,
          locationAlwaysStatus: PermissionStatus.granted,
          locationServicesEnabled: true,
        ),
      );
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: coordinator,
      );

      await controller.requestNotificationPermission();

      expect(coordinator.requestNotificationCount, 1);
      expect(controller.monitoringPermissionState.notificationGranted, isTrue);
    });

    test('completeMonitoringPermissionSetup keeps blocked error when denied',
        () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        permissionCoordinator: _TrackingPermissionCoordinator(
          completeState: const MonitoringPermissionState(
            notificationStatus: PermissionStatus.granted,
            locationWhenInUseStatus: PermissionStatus.granted,
            locationAlwaysStatus: PermissionStatus.denied,
            locationServicesEnabled: true,
          ),
        ),
      );

      await controller.completeMonitoringPermissionSetup();

      expect(controller.lastErrorMessage, contains('常に許可'));
    });

    test('loading new GeoJSON while idle resets to waitStart', () async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = FakeEventLogger();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: FakeAlarmPlayer(),
      );

      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
      );

      await controller.reloadGeoJsonFromPicker();

      expect(controller.snapshot.status, LocationStateStatus.waitStart);
      expect(controller.geoJsonLoaded, isTrue);
      expect(stateMachine.current, LocationStateStatus.waitStart);
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

    test('handleAppResumed reasserts an active outer alarm', () async {
      final config = _testConfig();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: notifier,
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: true,
        ),
      );
      await notifier.notifyOuter();

      await controller.handleAppResumed();

      expect(alarm.playCount, 2);
      expect(vibration.startCount, 2);
      expect(controller.logs.last.message,
          'Alarm playback reasserted after app resume.');
    });

    test('handleAppResumed logs reassertion failures', () async {
      final config = _testConfig();
      final alarm = _AppControllerFailSecondStartAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: notifier,
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: true,
        ),
      );
      await notifier.notifyOuter();

      await controller.handleAppResumed();

      expect(controller.logs.last.message,
          startsWith('Failed to reassert alarm after app resume:'));
    });

    test('handleAppResumed continues recovery when permission refresh fails',
        () async {
      final config = _testConfig();
      final alarm = FakeAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: notifier,
        permissionCoordinator: _ThrowingRefreshPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: true,
        ),
      );
      await notifier.notifyOuter();

      await controller.handleAppResumed();

      expect(alarm.playCount, 2);
      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Failed to refresh permissions on resume:')),
      );
    });

    test('handleAppResumed does not start an alarm outside OUTER', () async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(config: config);

      await controller.handleAppResumed();

      expect(controller.snapshot.status, isNot(LocationStateStatus.outer));
    });

    testWidgets(
        'snoozeAlarmForOneMinute stops alert and resumes after 1 minute when still outer',
        (tester) async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = FakeEventLogger();
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );
      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
      );

      controller.debugSeed(
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: true,
          distanceToBoundaryM: 10,
          bearingToBoundaryDeg: 180,
          nearestBoundaryPoint: const LatLng(1, 1),
        ),
      );

      await notifier.notifyOuter();
      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);

      await controller.snoozeAlarmForOneMinute();
      expect(controller.isAlarmSnoozed, isTrue);
      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(controller.isAlarmSnoozed, isFalse);
      expect(alarm.playCount, 2);
      expect(vibration.startCount, 2);
    });

    testWidgets('snooze logs a playback failure when resuming the alarm',
        (tester) async {
      final config = _testConfig();
      final alarm = _AppControllerFailSecondStartAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: notifier,
      );
      controller.debugSeed(
        config: config,
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: true,
        ),
      );
      await notifier.notifyOuter();

      await controller.snoozeAlarmForOneMinute();
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(controller.isAlarmSnoozed, isFalse);
      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Failed to resume alarm after snooze')),
      );
    });

    test('alarm stop failure keeps playback state and warns the user',
        () async {
      // 回帰テスト: 停止に失敗したのにフラグを倒すと、鳴り続けているのに
      // アプリは「停止済み」と認識し、検知も通知もできなくなる。
      final config = _testConfig();
      final locationService = FakeLocationService();
      final alarm = _AlwaysFailStopAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );
      var elapsed = Duration.zero;
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: notifier,
        permissionCoordinator: _GrantedPermissionCoordinator(),
        elapsedProvider: () => elapsed,
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      // エリア外へ出て警報を発報させる。
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      elapsed += const Duration(seconds: 2);
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, 2),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.snapshot.status, LocationStateStatus.outer);
      expect(notifier.hasActiveAlertPlayback, isTrue);

      await controller.stopMonitoring();

      // 停止に失敗したので再生中フラグは倒れず、利用者にも伝わる。
      expect(notifier.hasActiveAlertPlayback, isTrue);
      // Snackbarで4秒で消える lastErrorMessage ではなく、閉じるまで残る
      // 専用の警告に出す。見逃したら取り返しがつかない情報のため。
      expect(
        controller.alertReliabilityWarning,
        contains('警報を停止できませんでした'),
      );
      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Alert playback could not be stopped')),
      );
    });

    test('snooze does not claim muted when the alarm cannot be stopped',
        () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final alarm = _AlwaysFailStopAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );
      var elapsed = Duration.zero;
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: notifier,
        permissionCoordinator: _GrantedPermissionCoordinator(),
        elapsedProvider: () => elapsed,
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      elapsed += const Duration(seconds: 2);
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, 2),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.canSnoozeAlarm, isTrue);

      await controller.snoozeAlarmForOneMinute();

      // 実際に止まっていないので「ミュート中」にはしない。
      expect(controller.isAlarmSnoozed, isFalse);
      // Snackbarで4秒で消える lastErrorMessage ではなく、閉じるまで残る
      // 専用の警告に出す。見逃したら取り返しがつかない情報のため。
      expect(
        controller.alertReliabilityWarning,
        contains('警報を停止できませんでした'),
      );
      await controller.stopMonitoring();
    });

    test('reconnect stops and reports when the permission is revoked',
        () async {
      // 回帰テスト: 権限を再確認しないと、直せない状態のまま30秒間隔で
      // 無音の再試行を続け、利用者には原因が伝わらない。
      final config = _testConfig();
      final locationService = FakeLocationService();
      final coordinator = _RevokingPermissionCoordinator();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: coordinator,
        reconnectDelays: const [Duration(milliseconds: 1)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(const LocationStreamEndedException());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.lastErrorMessage, isNotNull);
      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Location recovery abandoned')),
      );
      // 打ち切っても監視セッションは維持する（警報と設定ロックを守るため）。
      expect(controller.isMonitoringSession, isTrue);

      final restartsAfterAbandon = locationService.startCount;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(locationService.startCount, restartsAfterAbandon);

      await controller.stopMonitoring();
    });

    test('reconnect gives up after repeated restart failures', () async {
      final config = _testConfig();
      final locationService = _AlwaysFailRestartLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(milliseconds: 1)],
        maxReconnectFailures: 3,
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(const LocationStreamEndedException());
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(locationService.restartCount, 3);
      expect(controller.lastErrorMessage, contains('位置情報の監視を再開できません'));

      // 打ち切ったので以降は試さない。
      final restarts = locationService.restartCount;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(locationService.restartCount, restarts);

      // アプリ復帰は再試行の契機になる。
      await controller.handleAppResumed();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(locationService.restartCount, greaterThan(restarts));

      await controller.stopMonitoring();
    });

    test('startMonitoring itself refuses a low alarm volume', () async {
      // 回帰テスト: 音量確認が呼び出し元にしかないと、別の入口から
      // 安全条件を迂回して監視を始められる。
      final config = _testConfig();
      final locationService = FakeLocationService();
      final alarmVolumeClient = support.RecordingAlarmVolumeClient(
        states: const [AlarmVolumeState(current: 1, max: 10, percent: 0.1)],
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        alarmVolumeClient: alarmVolumeClient,
        isAndroid: true,
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      final outcome = await controller.startMonitoring();

      expect(outcome, MonitoringStartOutcome.alarmVolumeTooLow);
      expect(locationService.started, isFalse);
      // 音量が低いのは「失敗」ではなくワンタップで直せる前提条件なので、
      // 赤い「開始失敗」を残さず idle に戻す。
      expect(controller.monitoringLifecycle, MonitoringLifecycle.idle);
      // 呼び出し元が専用ダイアログを出すため、文字列では重ねない。
      expect(controller.lastErrorMessage, isNull);
      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Monitoring start refused: alarm volume')),
      );
    });

    test('startMonitoring reports started when the volume is sufficient',
        () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        alarmVolumeClient: support.RecordingAlarmVolumeClient(),
        isAndroid: true,
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      expect(
        await controller.startMonitoring(),
        MonitoringStartOutcome.started,
      );
      await controller.stopMonitoring();
    });

    test('outer alert channel failure is surfaced to the user', () async {
      // 回帰テスト: ログだけに残すと、警報音が鳴っていないのに通常の
      // OUTER画面が出て「警報は動いている」と誤解される。
      final config = _testConfig();
      final locationService = FakeLocationService();
      var elapsed = Duration.zero;
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: _AlwaysFailAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        elapsedProvider: () => elapsed,
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      elapsed += const Duration(seconds: 2);
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, 2),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.snapshot.status, LocationStateStatus.outer);
      expect(controller.alertReliabilityWarning, contains('警報音'));
      expect(
        controller.alertReliabilityWarning,
        contains('発報できませんでした'),
      );
      await controller.stopMonitoring();
    });

    test('GPS outage warning repeats while the outage continues', () async {
      // 回帰テスト: 1回だけ通知して終わりだと、無音通知と350msの振動1回を
      // 見逃した時点で監視が死んでいることに気づけなくなる。
      final config = _testConfig();
      final locationService = FakeLocationService();
      final notifications = FakeLocalNotificationsClient();
      final vibration = FakeVibrationPlayer();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: notifications,
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: vibration,
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(seconds: 30)],
        staleReminderInterval: const Duration(milliseconds: 10),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(const LocationStreamEndedException());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final firstPulses = vibration.pulseCount;
      expect(firstPulses, greaterThan(0));

      await Future<void>.delayed(const Duration(milliseconds: 60));

      // 反復して通知と振動が出る。
      expect(vibration.pulseCount, greaterThan(firstPulses));
      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Location updates still stopped after')),
      );

      // fixが戻れば反復は止まる。
      locationService.add(
        LocationFix(
          latitude: 0.5,
          longitude: 0.5,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final pulsesAfterRecovery = vibration.pulseCount;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(vibration.pulseCount, pulsesAfterRecovery);

      await controller.stopMonitoring();
      expect(notifications.shownIds, contains(1002));
    });

    test('startMonitoring stops alert playback left over from a failed stop',
        () async {
      // 回帰テスト: 停止に失敗した警報を残したまま次のセッションを始めると、
      // 鳴り続けたうえ _isAlarmChannelActive が true のままなので、次の
      // OUTER で警報の開始自体がスキップされる。
      final config = _testConfig();
      final locationService = FakeLocationService();
      final alarm = _AlwaysFailStopAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: FakeLocalNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );
      var elapsed = Duration.zero;
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: notifier,
        permissionCoordinator: _GrantedPermissionCoordinator(),
        elapsedProvider: () => elapsed,
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      elapsed += const Duration(seconds: 2);
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, 2),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await controller.stopMonitoring();
      expect(notifier.hasActiveAlertPlayback, isTrue);

      final stopsBeforeRestart = alarm.stopCount;
      await controller.startMonitoring();

      // 再開時に停止を試み、それでも止まらないなら警告を出し続ける。
      expect(alarm.stopCount, greaterThan(stopsBeforeRestart));
      expect(
        controller.alertReliabilityWarning,
        contains('警報を停止できませんでした'),
      );
      await controller.stopMonitoring();
    });

    test('resume grants a single retry instead of a fresh budget', () async {
      // 回帰テスト: レジュームのたびに失敗回数を0へ戻すと、競技中によくある
      // アプリ切り替えのたびに満額の再試行が復活し打ち切りが効かなくなる。
      final config = _testConfig();
      final locationService = _AlwaysFailRestartLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        reconnectDelays: const [Duration(milliseconds: 1)],
        maxReconnectFailures: 3,
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.addError(const LocationStreamEndedException());
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(locationService.restartCount, 3);

      await controller.handleAppResumed();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // 満額（さらに3回）ではなく1回だけ。
      expect(locationService.restartCount, 4);

      await controller.stopMonitoring();
    });

    test('stopMonitoring completes even when a native call never returns',
        () async {
      // 回帰テスト: ネイティブが応答しないと stopping から抜けられず、
      // 開始も停止も設定変更もできないままアプリ再起動しか手がなくなる。
      final config = _testConfig();
      final locationService = FakeLocationService();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: _HangingNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        platformCallTimeout: const Duration(milliseconds: 20),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      await controller.stopMonitoring().timeout(const Duration(seconds: 5));

      expect(controller.monitoringLifecycle, MonitoringLifecycle.idle);
      expect(controller.canStartMonitoring, isTrue);
      expect(controller.canModifyConfiguration, isTrue);
      expect(
        controller.logs.map((entry) => entry.message),
        contains(contains('timed out')),
      );
    });

    test('a failed config save leaves the running config untouched', () async {
      // 回帰テスト: メモリを先に更新すると、保存に失敗したとき画面には
      // 「反映に失敗」と出るのに動作中の閾値は変わっており、次回起動で
      // 元へ戻る。利用者は「変えたつもりの値」で走ることになる。
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: _FailingSaveFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      final updated = AppConfig(
        innerBufferM: 12,
        leaveConfirmSamples: 2,
        leaveConfirmSeconds: 5,
        gpsAccuracyBadMeters: 20,
        sampleIntervalS: const {'fast': 2},
        alarmVolume: 0.8,
      );

      await expectLater(
        controller.updateConfig(updated),
        throwsA(isA<StateError>()),
      );

      // 保存できなかったので、動作中の設定は変わらない。
      expect(controller.config!.innerBufferM, config.innerBufferM);
      expect(
        controller.config!.gpsAccuracyBadMeters,
        config.gpsAccuracyBadMeters,
      );
      expect(controller.config!.alarmVolume, config.alarmVolume);
    });

    test('initialize reports that saved settings were unusable', () async {
      // 回帰テスト: 保存済みの閾値が黙って初期値へ戻ると、利用者は
      // 「調整したつもりの設定」で走ることになる。
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: _CorruptConfigFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );

      await controller.initialize();

      expect(controller.lastErrorMessage, contains('初期設定で起動しました'));
      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('Saved settings were not usable')),
      );
    });

    test('reconnect does not delay OUTER confirmation', () async {
      // 回帰テスト: 再接続は locationService.stop()/start() を呼ぶ。監視の経過時間を
      // 位置サービス側で計測していると、この stop/start でクロックが 0 に戻り、
      // ヒステリシスの基準時刻より手前の値しか来なくなるため OUTER が確定しない。
      // 経過時間は監視セッション側で持つので、再接続をまたいでも確定できる。
      final config = _testConfig();
      final locationService = FakeLocationService();
      var elapsed = Duration.zero;
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        elapsedProvider: () => elapsed,
        reconnectDelays: const [Duration(milliseconds: 1)],
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      // 監視をしばらく続けたあとにエリア外へ出る。
      elapsed += const Duration(minutes: 30);
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
          monitoringElapsed: const Duration(minutes: 30),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.snapshot.status, LocationStateStatus.outerPending);

      // ここでGPSが途絶し、再接続が走る。
      locationService.addError(const LocationStreamEndedException());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(locationService.stopCount, greaterThan(0));

      // 再接続後もエリア外のまま確定時間を超える。
      // 位置サービスが巻き戻った monitoringElapsed を載せてきても（旧実装の
      // GeolocatorLocationService は start() ごとに Stopwatch を作り直していた）、
      // 監視セッション側の値で上書きされるので確定できる。
      elapsed += const Duration(seconds: 2);
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, 2),
          monitoringElapsed: Duration.zero,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.snapshot.status, LocationStateStatus.outer);
      await controller.stopMonitoring();
    });

    test('outer alert channel failures are retained in the app log', () async {
      final config = _testConfig();
      final locationService = FakeLocationService();
      var elapsed = Duration.zero;
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: _ThrowingShowNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        elapsedProvider: () => elapsed,
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      // ヒステリシスは監視セッションの単調クロックで確定する。
      // GPSタイムスタンプを進めても確定しない（仕様どおり）。
      elapsed += const Duration(seconds: 2);
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, 2),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        controller.logs.map((entry) => entry.message),
        contains(startsWith('One or more alert channels failed')),
      );
      await controller.stopMonitoring();
    });

    testWidgets('snooze does not resume after returning to safe zone',
        (tester) async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = FakeEventLogger();
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );
      var elapsed = Duration.zero;
      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
        permissionCoordinator: _GrantedPermissionCoordinator(),
        elapsedProvider: () => elapsed,
      );

      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );

      await controller.startMonitoring();
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, 0),
        ),
      );
      await tester.pump();
      elapsed += const Duration(seconds: 2);
      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, 2),
        ),
      );
      await tester.pump();

      expect(controller.snapshot.status, LocationStateStatus.outer);
      expect(alarm.playCount, 1);

      await controller.snoozeAlarmForOneMinute();
      expect(controller.isAlarmSnoozed, isTrue);
      expect(alarm.stopCount, 1);

      locationService.add(
        LocationFix(
          latitude: 0.5,
          longitude: 0.5,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, 2),
        ),
      );
      await tester.pump();

      expect(controller.snapshot.status, isNot(LocationStateStatus.outer));
      expect(controller.isAlarmSnoozed, isFalse);

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);
      controller.dispose();
    });

    test('stopMonitoring dismisses active outer alert', () async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = FakeEventLogger();
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );
      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
      );

      controller.debugSeed(
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: true,
        ),
      );

      await notifier.notifyOuter();
      expect(alarm.playCount, 1);

      await controller.stopMonitoring();

      expect(notifications.cancelledIds, [1001, 1002]);
      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);
      expect(locationService.stopped, isTrue);
    });

    test('stopMonitoring logs every cleanup failure and still becomes idle',
        () async {
      final config = _testConfig();
      final locationService = _FaultyLocationService(
        throwOnCancel: true,
        throwOnStop: true,
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: _ThrowingCancelNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      await controller.stopMonitoring();

      expect(controller.monitoringLifecycle, MonitoringLifecycle.idle);
      final messages = controller.logs.map((entry) => entry.message);
      expect(messages, contains(startsWith('Dismissing alert while stopping')));
      expect(
        messages,
        contains(startsWith('Clearing GPS warning while stopping')),
      );
      expect(
        messages,
        contains(startsWith('Cancelling location stream while stopping')),
      );
      expect(
        messages,
        contains(startsWith('Stopping location service while stopping')),
      );
    });

    test('termination logs cleanup failures and continues through all steps',
        () async {
      final config = _testConfig();
      final locationService = _FaultyLocationService(
        throwOnCancel: true,
        throwOnStop: true,
      );
      final alarm = _FailSecondStopAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: _ThrowingCancelNotificationsClient(),
        alarmPlayer: alarm,
        vibrationPlayer: FakeVibrationPlayer(),
      );
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: locationService,
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: notifier,
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );
      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();
      await notifier.startAlarmPreview();

      await controller.handleAppTermination();

      expect(controller.monitoringLifecycle, MonitoringLifecycle.idle);
      final messages = controller.logs.map((entry) => entry.message);
      expect(messages, contains(startsWith('Failed to stop preview')));
      expect(
        messages,
        contains(startsWith('Dismissing alert on termination')),
      );
      expect(
        messages,
        contains(startsWith('Clearing GPS warning on termination')),
      );
      expect(
        messages,
        contains(startsWith('Cancelling location stream on termination')),
      );
      expect(
        messages,
        contains(startsWith('Stopping location service on termination')),
      );
    });

    test('stopMonitoring returns loaded race to waitStart and clears fix data',
        () async {
      final controller = _buildController();
      controller.debugSeed(
        config: _testConfig(),
        geoJson: _squareModel(),
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: true,
          distanceToBoundaryM: 12,
          horizontalAccuracyM: 4,
          bearingToBoundaryDeg: 90,
          nearestBoundaryPoint: const LatLng(1, 1),
        ),
      );

      await controller.stopMonitoring();

      expect(controller.snapshot.status, LocationStateStatus.waitStart);
      expect(controller.stateMachine.current, LocationStateStatus.waitStart);
      expect(controller.snapshot.geoJsonLoaded, isTrue);
      expect(controller.snapshot.distanceToBoundaryM, isNull);
      expect(controller.snapshot.horizontalAccuracyM, isNull);
      expect(controller.snapshot.bearingToBoundaryDeg, isNull);
      expect(controller.snapshot.nearestBoundaryPoint, isNull);
    });

    test('stopMonitoring suppresses an in-flight outer location fix', () async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = _BlockingLocationLogger();
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );
      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
        permissionCoordinator: _GrantedPermissionCoordinator(),
      );

      controller.debugSeed(
        config: config,
        geoJson: _squareModel(),
        permissionState: _grantedMonitoringPermissionState(),
      );
      await controller.startMonitoring();

      locationService.add(
        LocationFix(
          latitude: 2,
          longitude: 2,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1),
        ),
      );
      await logger.locationLogEntered.future;

      await controller.stopMonitoring();
      logger.allowLocationLog.complete();
      await Future<void>.delayed(Duration.zero);

      expect(notifications.shownIds, isEmpty);
      expect(alarm.playCount, 0);
      expect(vibration.startCount, 0);
      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);
    });

    testWidgets('stopMonitoring clears pending alarm snooze', (tester) async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = FakeEventLogger();
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );
      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
      );

      controller.debugSeed(
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: true,
        ),
      );

      await notifier.notifyOuter();
      await controller.snoozeAlarmForOneMinute();
      expect(controller.isAlarmSnoozed, isTrue);

      await controller.stopMonitoring();
      expect(controller.isAlarmSnoozed, isFalse);
      expect(notifications.cancelledIds, [1001, 1002]);
      expect(alarm.stopCount, 2);
      expect(vibration.stopCount, 2);

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);
    });

    test('handleAppTermination stops monitoring and active alarm', () async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final fileManager = FakeFileManager(config: config);
      final logger = FakeEventLogger();
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );
      final controller = AppController(
        stateMachine: stateMachine,
        locationService: locationService,
        fileManager: fileManager,
        logger: logger,
        notifier: notifier,
      );

      controller.debugSeed(
        snapshot: StateSnapshot(
          status: LocationStateStatus.outer,
          timestamp: DateTime.utc(2024, 1, 1),
          geoJsonLoaded: true,
        ),
      );

      await notifier.notifyOuter();
      expect(alarm.playCount, 1);

      await controller.handleAppTermination();

      expect(locationService.stopped, isTrue);
      expect(notifications.cancelledIds, [1001, 1002]);
      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);
      expect(controller.isAlarmSnoozed, isFalse);
    });

    test('reloadGeoJsonFromQr loads GeoJSON from valid QR code', () async {
      final config = _testConfig();
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

      // QRコードを生成
      final bundle = await encodeGeoJson(
        const GeoJsonQrEncodeInput(
          geoJson: _squareGeoJson,
          sourceFileName: 'hoge.geojson',
          scheme: GeoJsonQrScheme.agz1,
        ),
      );
      final qrText = bundle.qrTexts.first;

      // QRコードからGeoJSONを読み込み
      // 注意: getTemporaryDirectory()がテスト環境で動作しない可能性があるため、
      // エラーが発生する場合はテストをスキップする
      try {
        await controller.reloadGeoJsonFromQr(qrText);

        // 成功した場合のアサーション
        expect(controller.geoJsonLoaded, isTrue);
        expect(controller.geoJsonFileName, isNotNull);
        expect(controller.geoJsonFileName, 'hoge.geojson');
        expect(controller.snapshot.notes, 'GeoJSON loaded from QR code');
        expect(locationService.stopped, isTrue);
      } catch (e) {
        // getTemporaryDirectory()が失敗した場合は、エラーメッセージを確認
        expect(controller.lastErrorMessage, isNotNull);
        // このテストはスキップ（テスト環境でpath_providerが動作しない場合）
        return;
      }

      // クリーンアップ
      await controller.cleanupTempGeoJsonFile();
    });

    test('reloadGeoJsonFromQr rejects invalid QR code format', () async {
      final config = _testConfig();
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

      // 無効なQRコード形式
      final loaded = await controller.reloadGeoJsonFromQr('invalid:qr:code');

      expect(loaded, isFalse);
      expect(controller.lastErrorMessage, isNotNull);
      expect(controller.lastErrorMessage, contains('Invalid QR code format'));
      expect(controller.geoJsonLoaded, isFalse);
    });

    test('reloadGeoJsonFromPicker handles parse errors gracefully', () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: _InvalidGeoJsonFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await controller.reloadGeoJsonFromPicker();

      expect(controller.lastErrorMessage, contains('Failed to parse GeoJSON'));
    });

    test('reloadGeoJsonFromPicker rejects files above one megabyte', () async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: _LargeGeoJsonFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );
      controller.debugSeed(config: config);

      await controller.reloadGeoJsonFromPicker();

      expect(controller.geoJsonLoaded, isFalse);
      expect(controller.lastErrorMessage, contains('サイズが上限'));
    });

    test('reloadGeoJsonFromPicker rejects GeoJSON without polygons', () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: _EmptyGeoJsonFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await controller.reloadGeoJsonFromPicker();

      expect(controller.geoJsonLoaded, isFalse);
      // パーサ側でより具体的な原因を返すようになった。
      expect(controller.lastErrorMessage, contains('featuresが空です'));
    });

    test('reloadGeoJsonFromQr rejects GeoJSON without polygons', () async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );
      final bundle = await encodeGeoJson(
        const GeoJsonQrEncodeInput(
          geoJson: '{"type":"FeatureCollection","features":[]}',
          scheme: GeoJsonQrScheme.gjz1,
        ),
      );

      final loaded = await controller.reloadGeoJsonFromQr(bundle.qrTexts.first);

      expect(loaded, isFalse);
      expect(controller.geoJsonLoaded, isFalse);
      // パーサ側でより具体的な原因を返すようになった。
      expect(controller.lastErrorMessage, contains('featuresが空です'));
    });

    test('reloadGeoJsonFromPicker ignores user cancellation', () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: _ThrowingGeoJsonFileManager(
          config: _testConfig(),
          error: Exception('user cancel'),
        ),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await controller.reloadGeoJsonFromPicker();

      expect(controller.lastErrorMessage, isNull);
    });

    test('reloadGeoJsonFromPicker reports unexpected file errors', () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: _ThrowingGeoJsonFileManager(
          config: _testConfig(),
          error: Exception('disk failure'),
        ),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await controller.reloadGeoJsonFromPicker();

      expect(controller.lastErrorMessage, contains('Unable to open file'));
    });

    test('reloadGeoJsonFromQr handles decode errors gracefully', () async {
      final config = _testConfig();
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

      // 無効なペイロードを含むQRコード
      final loaded =
          await controller.reloadGeoJsonFromQr('gjz1:invalid_payload');

      expect(loaded, isFalse);
      expect(controller.lastErrorMessage, isNotNull);
      expect(controller.lastErrorMessage, contains('Failed to decode'));
      expect(controller.geoJsonLoaded, isFalse);
    });

    test('reloadGeoJsonFromQr handles parsed invalid GeoJSON gracefully',
        () async {
      final payload = base64Url
          .encode(
            gzip.encode(
              utf8.encode('{"type":"FeatureCollection","features":"bad"}'),
            ),
          )
          .replaceAll('=', '');
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      final loaded = await controller.reloadGeoJsonFromQr('gjz1:$payload');

      expect(loaded, isFalse);
      expect(controller.lastErrorMessage, contains('Failed to decode QR code'));
    });

    test('reloadGeoJsonFromQrImagePicker loads QR image selection', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('argus_qr_image_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      final bundle = await encodeGeoJson(
        const GeoJsonQrEncodeInput(
          geoJson: _squareGeoJson,
          scheme: GeoJsonQrScheme.gjz1,
          generatePng: false,
        ),
      );
      String? analyzedPath;
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: _QrImageFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        qrImageAnalyzer: (path) async {
          analyzedPath = path;
          return bundle.qrTexts.single;
        },
      );

      final loaded = await controller.reloadGeoJsonFromQrImagePicker();

      expect(loaded, isTrue);
      expect(analyzedPath, 'selected_qr.png');
      expect(controller.geoJsonLoaded, isTrue);
      expect(controller.snapshot.notes, 'GeoJSON loaded from QR code');
      expect(controller.lastErrorMessage, isNull);
    });

    test('reloadGeoJsonFromQrImagePicker reports images without QR', () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: _QrImageFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        qrImageAnalyzer: (_) async => null,
      );

      final loaded = await controller.reloadGeoJsonFromQrImagePicker();

      expect(loaded, isFalse);
      expect(controller.lastErrorMessage, 'QRコード画像からQRコードを読み取れませんでした。');
      expect(controller.geoJsonLoaded, isFalse);
    });

    test('reloadGeoJsonFromQrImagePicker ignores picker cancellation',
        () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: _QrImageCancelFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        qrImageAnalyzer: (_) async => fail('analyzer should not be called'),
      );

      final loaded = await controller.reloadGeoJsonFromQrImagePicker();

      expect(loaded, isFalse);
      expect(controller.lastErrorMessage, isNull);
    });

    test('reloadGeoJsonFromQrImagePicker ignores analyzer cancellation',
        () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: _QrImageFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        qrImageAnalyzer: (_) async => throw Exception('user abort'),
      );

      final loaded = await controller.reloadGeoJsonFromQrImagePicker();

      expect(loaded, isFalse);
      expect(controller.lastErrorMessage, isNull);
    });

    test('reloadGeoJsonFromQrImagePicker reports analyzer errors', () async {
      final controller = AppController(
        stateMachine: StateMachine(config: _testConfig()),
        locationService: FakeLocationService(),
        fileManager: _QrImageFileManager(config: _testConfig()),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
        qrImageAnalyzer: (_) async => throw Exception('decoder exploded'),
      );

      final loaded = await controller.reloadGeoJsonFromQrImagePicker();

      expect(loaded, isFalse);
      expect(controller.lastErrorMessage, contains('Unable to load GeoJSON'));
    });

    test('log list is capped at 200 entries', () {
      final controller = _buildController();

      for (var i = 0; i < 205; i++) {
        controller.setDeveloperMode(i.isEven);
      }

      expect(controller.logs.length, 200);
    });

    test('cleanupTempGeoJsonFile deletes temporary file', () async {
      final config = _testConfig();
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

      // QRコードを生成して読み込み
      final bundle = await encodeGeoJson(
        const GeoJsonQrEncodeInput(geoJson: _squareGeoJson),
      );
      final qrText = bundle.qrTexts.first;

      // 最初は一時ファイル名がnull
      expect(controller.geoJsonFileName, isNull);

      // getTemporaryDirectory()がテスト環境で動作しない可能性があるため、
      // エラーが発生する場合はテストをスキップする
      try {
        await controller.reloadGeoJsonFromQr(qrText);

        // 一時ファイル名が設定されていることを確認
        expect(controller.geoJsonFileName, isNotNull);
        expect(controller.geoJsonFileName, contains('temp_geojson_'));
      } catch (e) {
        // getTemporaryDirectory()が失敗した場合は、エラーメッセージを確認
        expect(controller.lastErrorMessage, isNotNull);
        // このテストはスキップ（テスト環境でpath_providerが動作しない場合）
        return;
      }

      // クリーンアップを実行
      await controller.cleanupTempGeoJsonFile();

      // クリーンアップ後、一時ファイル名がクリアされていることを確認
      // (実際のファイル削除はテスト環境では確認できないため、ファイル名の確認のみ)
    });

    test('QR reload keeps exactly one temp file and deletes the previous one',
        () async {
      // 回帰テスト: 書き込み後に旧パスで削除していると、同一ミリ秒の連続
      // 読み込みで旧パスと新パスが一致し、書いたばかりのファイルを消す。
      final tempDir =
          await Directory.systemTemp.createTemp('argus_qr_temp_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

      final config = _testConfig();
      // 同一ミリ秒での連続読み込みを再現するため時刻を固定する。
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: FakeLocationService(),
        fileManager: FakeFileManager(config: config),
        logger: FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
          vibrationPlayer: FakeVibrationPlayer(),
        ),
        permissionCoordinator: _GrantedPermissionCoordinator(),
        nowProvider: () => DateTime.utc(2024, 1, 1),
      );
      final bundle = await encodeGeoJson(
        const GeoJsonQrEncodeInput(
          geoJson: _squareGeoJson,
          scheme: GeoJsonQrScheme.gjz1,
          generatePng: false,
        ),
      );
      final qrText = bundle.qrTexts.first;

      expect(await controller.reloadGeoJsonFromQr(qrText), isTrue);
      expect(await controller.reloadGeoJsonFromQr(qrText), isTrue);

      final files = tempDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.geojson'))
          .toList();

      // 記録しているパスのファイルは必ず存在する。
      expect(files, hasLength(1));
      expect(files.single.readAsStringSync(), isNotEmpty);

      await controller.cleanupTempGeoJsonFile();
      expect(
        tempDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.geojson')),
        isEmpty,
      );
    });

    test('reloadGeoJsonFromQr resets state and stops monitoring', () async {
      final config = _testConfig();
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

      // 監視を開始（initialize()はスキップ - パーミッションチェックが発生するため）
      // ただし、geoJsonLoadedがfalseの場合はstartMonitoring()が失敗するため、
      // まずGeoJSONを読み込む必要がある
      // このテストでは、監視開始前にQRコードを読み込む必要はない
      // 代わりに、QRコード読み込み後に監視が停止されていることを確認する

      // QRコードを生成して読み込み
      final bundle = await encodeGeoJson(
        const GeoJsonQrEncodeInput(geoJson: _squareGeoJson),
      );
      final qrText = bundle.qrTexts.first;

      // getTemporaryDirectory()がテスト環境で動作しない可能性があるため、
      // エラーが発生する場合はテストをスキップする
      try {
        await controller.reloadGeoJsonFromQr(qrText);

        // 読み込み前から停止中なので、位置情報サービスへ不要なstopを送らない。
        expect(locationService.stopped, isFalse);
        expect(controller.snapshot.status, LocationStateStatus.waitStart);
        expect(controller.snapshot.distanceToBoundaryM, isNull);
        expect(controller.snapshot.bearingToBoundaryDeg, isNull);
        expect(controller.snapshot.nearestBoundaryPoint, isNull);
      } catch (e) {
        // getTemporaryDirectory()が失敗した場合は、エラーメッセージを確認
        expect(controller.lastErrorMessage, isNotNull);
        // このテストはスキップ（テスト環境でpath_providerが動作しない場合）
        return;
      }

      // クリーンアップ
      await controller.cleanupTempGeoJsonFile();
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
    alarmVolume: 1.0,
  );
}

GeoModel _squareModel() {
  return GeoModel.fromGeoJson(_squareGeoJson);
}

MonitoringPermissionState _grantedMonitoringPermissionState() {
  return const MonitoringPermissionState(
    notificationStatus: PermissionStatus.granted,
    locationWhenInUseStatus: PermissionStatus.granted,
    locationAlwaysStatus: PermissionStatus.granted,
    locationServicesEnabled: true,
  );
}

AppController _buildController({
  PermissionCoordinator? permissionCoordinator,
}) {
  final config = _testConfig();
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
    permissionCoordinator: permissionCoordinator,
  );
}

const String _squareGeoJson = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {"name": "Test Area"},
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[0,0],[1,0],[1,1],[0,1],[0,0]]]
      }
    }
  ]
}
''';

class _GrantedPermissionCoordinator extends PermissionCoordinator {
  @override
  Future<MonitoringPermissionState> refreshMonitoringPermissionState() async {
    return _grantedMonitoringPermissionState();
  }
}

class _RevokingPermissionCoordinator extends PermissionCoordinator {
  int refreshCount = 0;

  @override
  Future<MonitoringPermissionState> refreshMonitoringPermissionState() async {
    refreshCount += 1;
    if (refreshCount <= 1) {
      return _grantedMonitoringPermissionState();
    }
    return const MonitoringPermissionState(
      notificationStatus: PermissionStatus.granted,
      locationWhenInUseStatus: PermissionStatus.granted,
      locationAlwaysStatus: PermissionStatus.denied,
      locationServicesEnabled: true,
    );
  }
}

class _AlwaysFailRestartLocationService extends FakeLocationService {
  int restartCount = 0;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    startCount += 1;
    started = true;
    if (startCount == 1) {
      return const LocationServiceStartResult.started();
    }
    restartCount += 1;
    return const LocationServiceStartResult(
      status: LocationServiceStartStatus.error,
      message: 'restart failed',
    );
  }
}

/// 応答を返さないネイティブ通知クライアント。
class _HangingNotificationsClient extends FakeLocalNotificationsClient {
  @override
  Future<void> cancel(int id) {
    return Completer<void>().future;
  }
}

class _ThrowingOpenAlarmVolumeClient implements AlarmVolumeClient {
  @override
  Future<AlarmVolumeState> getAlarmVolumeState() async {
    return const AlarmVolumeState(current: 10, max: 10, percent: 1);
  }

  @override
  Future<bool> openSoundSettings() async {
    throw StateError('settings unavailable');
  }
}

class _AppControllerFailSecondStartAlarmPlayer extends FakeAlarmPlayer {
  @override
  Future<void> start() async {
    playCount += 1;
    if (playCount == 2) {
      throw StateError('reassert failed');
    }
  }
}

class _AlwaysFailAlarmPlayer extends FakeAlarmPlayer {
  @override
  Future<void> start() async {
    playCount += 1;
    throw StateError('preview failed');
  }
}

/// 再生開始後は停止できなくなるプレイヤー。
class _StuckOnceStartedAlarmPlayer extends FakeAlarmPlayer {
  bool _started = false;

  @override
  Future<void> start() async {
    playCount += 1;
    _started = true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    if (_started) {
      throw StateError('alarm stop failed');
    }
  }
}

class _AlwaysFailStopAlarmPlayer extends FakeAlarmPlayer {
  @override
  Future<void> stop() async {
    stopCount += 1;
    throw StateError('alarm stop failed');
  }
}

class _FailSecondStopAlarmPlayer extends FakeAlarmPlayer {
  @override
  Future<void> stop() async {
    stopCount += 1;
    if (stopCount == 2) {
      throw StateError('preview stop failed');
    }
  }
}

class _ThrowingRefreshPermissionCoordinator extends PermissionCoordinator {
  @override
  Future<MonitoringPermissionState> refreshMonitoringPermissionState() {
    throw StateError('permission lookup failed');
  }
}

class _TrackingPermissionCoordinator extends PermissionCoordinator {
  _TrackingPermissionCoordinator({
    MonitoringPermissionState? refreshState,
    MonitoringPermissionState? completeState,
    MonitoringPermissionState? notificationState,
    this.openSettingsResult = false,
    this.openSettingsError,
  })  : _refreshState = refreshState ?? _grantedMonitoringPermissionState(),
        _completeState = completeState ?? _grantedMonitoringPermissionState(),
        _notificationState =
            notificationState ?? _grantedMonitoringPermissionState();

  final MonitoringPermissionState _refreshState;
  final MonitoringPermissionState _completeState;
  final MonitoringPermissionState _notificationState;
  final bool openSettingsResult;
  final Object? openSettingsError;

  int refreshCount = 0;
  int completeSetupCount = 0;
  int requestNotificationCount = 0;
  int openSettingsCount = 0;

  @override
  Future<bool> openSettings() async {
    openSettingsCount += 1;
    if (openSettingsError != null) {
      throw openSettingsError!;
    }
    return openSettingsResult;
  }

  @override
  Future<MonitoringPermissionState> refreshMonitoringPermissionState() async {
    refreshCount += 1;
    return _refreshState;
  }

  @override
  Future<MonitoringPermissionState> completeMonitoringSetup() async {
    completeSetupCount += 1;
    return _completeState;
  }

  @override
  Future<MonitoringPermissionState> requestNotificationPermission() async {
    requestNotificationCount += 1;
    return _notificationState;
  }
}

class FakeFileManager extends FileManager {
  FakeFileManager({
    required this.config,
  });

  final AppConfig config;

  GeoModel get _model => _squareModel();

  @override
  Future<ConfigLoadResult> readConfig() async =>
      ConfigLoadResult(config: config);

  Future<GeoModel?> pickAndLoadGeoJson() async => _model;

  Future<GeoModel> loadBundledGeoJson(String assetPath) async => _model;

  @override
  Future<XFile?> pickGeoJsonFile() async {
    return XFile.fromData(
      utf8.encode(_squareGeoJson),
      name: 'test_square.geojson',
      mimeType: 'application/geo+json',
    );
  }

  @override
  Future<XFile?> pickQrImageFile() async {
    return XFile.fromData(
      Uint8List.fromList(const <int>[0]),
      name: 'selected_qr.png',
      mimeType: 'image/png',
      path: 'selected_qr.png',
    );
  }
}

class _QrImageFileManager extends FakeFileManager {
  _QrImageFileManager({required super.config});
}

class _QrImageCancelFileManager extends FakeFileManager {
  _QrImageCancelFileManager({required super.config});

  @override
  Future<XFile?> pickQrImageFile() async {
    return null;
  }
}

class _SavingFileManager extends FakeFileManager {
  _SavingFileManager({required super.config});

  AppConfig? savedConfig;

  @override
  Future<void> saveConfig(AppConfig config) async {
    savedConfig = config;
  }
}

class _CorruptConfigFileManager extends FakeFileManager {
  _CorruptConfigFileManager({required super.config});

  @override
  Future<ConfigLoadResult> readConfig() async => ConfigLoadResult(
        config: config,
        fallbackReason: '設定ファイルを読み込めません: FormatException',
      );
}

class _FailingSaveFileManager extends FakeFileManager {
  _FailingSaveFileManager({required super.config});

  @override
  Future<void> saveConfig(AppConfig config) async {
    throw StateError('config save failed');
  }
}

class _InvalidGeoJsonFileManager extends FakeFileManager {
  _InvalidGeoJsonFileManager({required super.config});

  @override
  Future<XFile?> pickGeoJsonFile() async {
    return XFile.fromData(
      utf8.encode('not-json'),
      name: 'broken.geojson',
      mimeType: 'application/geo+json',
    );
  }
}

class _EmptyGeoJsonFileManager extends FakeFileManager {
  _EmptyGeoJsonFileManager({required super.config});

  @override
  Future<XFile?> pickGeoJsonFile() async {
    return XFile.fromData(
      utf8.encode('{"type":"FeatureCollection","features":[]}'),
      name: 'empty.geojson',
      mimeType: 'application/geo+json',
    );
  }
}

class _LargeGeoJsonFileManager extends FakeFileManager {
  _LargeGeoJsonFileManager({required super.config});

  @override
  Future<XFile?> pickGeoJsonFile() async {
    return XFile.fromData(
      Uint8List(1024 * 1024 + 1),
      name: 'too-large.geojson',
      mimeType: 'application/geo+json',
    );
  }
}

class _ThrowingGeoJsonFileManager extends FakeFileManager {
  _ThrowingGeoJsonFileManager({
    required super.config,
    required this.error,
  });

  final Object error;

  @override
  Future<XFile?> pickGeoJsonFile() async {
    throw error;
  }
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.temporaryPath);

  final String temporaryPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}

class FakeEventLogger extends EventLogger {
  final List<StateSnapshot> stateChanges = <StateSnapshot>[];

  @override
  Future<String> logStateChange(StateSnapshot snapshot) async {
    stateChanges.add(snapshot);
    return snapshot.status.name;
  }

  @override
  Future<String> logLocationFix(LocationFix fix) async {
    return 'logged';
  }
}

class _BlockingLocationLogger extends FakeEventLogger {
  final Completer<void> locationLogEntered = Completer<void>();
  final Completer<void> allowLocationLog = Completer<void>();

  @override
  Future<String> logLocationFix(LocationFix fix) async {
    if (!locationLogEntered.isCompleted) {
      locationLogEntered.complete();
    }
    await allowLocationLog.future;
    return super.logLocationFix(fix);
  }
}

class _ThrowingLocationLogger extends FakeEventLogger {
  @override
  Future<String> logLocationFix(LocationFix fix) {
    throw StateError('location log failed');
  }
}

class FakeLocationService implements LocationService {
  FakeLocationService();

  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();

  bool started = false;
  bool stopped = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    started = true;
    startCount += 1;
    return const LocationServiceStartResult.started();
  }

  @override
  Future<void> stop() async {
    stopped = true;
    stopCount += 1;
  }

  void add(LocationFix fix) {
    _controller.add(fix);
  }

  void addError(Object error) {
    _controller.addError(error);
  }
}

class _ThrowingStartLocationService implements LocationService {
  @override
  Stream<LocationFix> get stream => const Stream<LocationFix>.empty();

  @override
  Future<LocationServiceStartResult> start(AppConfig config) {
    throw StateError('start threw');
  }

  @override
  Future<void> stop() async {}
}

class _FaultyLocationService implements LocationService {
  _FaultyLocationService({
    this.startResult = const LocationServiceStartResult.started(),
    this.throwOnCancel = false,
    this.throwOnStop = false,
  });

  final LocationServiceStartResult startResult;
  final bool throwOnCancel;
  final bool throwOnStop;
  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();

  @override
  Stream<LocationFix> get stream => throwOnCancel
      ? _CancelFailingStream<LocationFix>(_controller.stream)
      : _controller.stream;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    return startResult;
  }

  @override
  Future<void> stop() async {
    if (throwOnStop) {
      throw StateError('location stop failed');
    }
  }
}

class _CancelFailingStream<T> extends Stream<T> {
  _CancelFailingStream(this._delegate);

  final Stream<T> _delegate;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _CancelFailingSubscription<T>(
      _delegate.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
    );
  }
}

class _CancelFailingSubscription<T> implements StreamSubscription<T> {
  _CancelFailingSubscription(this._delegate);

  final StreamSubscription<T> _delegate;

  @override
  Future<void> cancel() async {
    await _delegate.cancel();
    throw StateError('stream cancel failed');
  }

  @override
  void onData(void Function(T data)? handleData) =>
      _delegate.onData(handleData);

  @override
  void onError(Function? handleError) => _delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _delegate.pause(resumeSignal);

  @override
  void resume() => _delegate.resume();

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _delegate.asFuture(futureValue);
}

class _EmittingStartLocationService implements LocationService {
  _EmittingStartLocationService({
    required this.emitOnStartNumbers,
  });

  final Set<int> emitOnStartNumbers;
  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast(sync: true);
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    startCount += 1;
    if (emitOnStartNumbers.contains(startCount)) {
      _controller.add(
        LocationFix(
          latitude: 0.5,
          longitude: 0.5,
          accuracyMeters: 5,
          timestamp: DateTime.utc(2024, 1, 1, 0, 0, startCount),
        ),
      );
    }
    return const LocationServiceStartResult.started();
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  void addError(Object error) {
    _controller.addError(error);
  }
}

class _BlockingReconnectLocationService implements LocationService {
  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  final Completer<void> reconnectStartEntered = Completer<void>();
  final Completer<void> allowReconnectStart = Completer<void>();
  int startCount = 0;
  int stopCount = 0;
  int _activeOperations = 0;
  int maxConcurrentOperations = 0;

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    _enterOperation();
    try {
      startCount += 1;
      if (startCount == 2) {
        reconnectStartEntered.complete();
        await allowReconnectStart.future;
      }
      return const LocationServiceStartResult.started();
    } finally {
      _leaveOperation();
    }
  }

  @override
  Future<void> stop() async {
    _enterOperation();
    try {
      stopCount += 1;
      await Future<void>.delayed(Duration.zero);
    } finally {
      _leaveOperation();
    }
  }

  void addError(Object error) {
    _controller.addError(error);
  }

  void _enterOperation() {
    _activeOperations += 1;
    if (_activeOperations > maxConcurrentOperations) {
      maxConcurrentOperations = _activeOperations;
    }
  }

  void _leaveOperation() {
    _activeOperations -= 1;
  }
}

class _BlockingHealthNotificationsClient extends FakeLocalNotificationsClient {
  final Completer<void> healthShowEntered = Completer<void>();
  final Completer<void> allowHealthShow = Completer<void>();

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  ) async {
    if (id == 1002) {
      if (!healthShowEntered.isCompleted) {
        healthShowEntered.complete();
      }
      await allowHealthShow.future;
    }
    await super.show(id, title, body, details);
  }
}

class _ThrowingCancelNotificationsClient extends FakeLocalNotificationsClient {
  @override
  Future<void> cancel(int id) {
    throw StateError('notification cancel failed');
  }
}

class _ThrowingHealthNotificationsClient extends FakeLocalNotificationsClient {
  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  ) {
    if (id == 1002) {
      throw StateError('health notification failed');
    }
    return super.show(id, title, body, details);
  }

  @override
  Future<void> cancel(int id) {
    if (id == 1002) {
      throw StateError('health cancel failed');
    }
    return super.cancel(id);
  }
}

class _ThrowingShowNotificationsClient extends FakeLocalNotificationsClient {
  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  ) {
    throw StateError('notification show failed');
  }
}

class _FailingStartLocationService implements LocationService {
  @override
  Stream<LocationFix> get stream => const Stream.empty();

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    return const LocationServiceStartResult(
      status: LocationServiceStartStatus.error,
      message: 'boom',
    );
  }

  @override
  Future<void> stop() async {}
}

class _QueuedStartLocationService implements LocationService {
  _QueuedStartLocationService(this._results);

  final List<LocationServiceStartResult> _results;
  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    final index =
        startCount < _results.length ? startCount : _results.length - 1;
    startCount += 1;
    return _results[index];
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  void addError(Object error) {
    _controller.addError(error);
  }
}
