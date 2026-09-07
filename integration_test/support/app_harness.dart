import 'dart:async';
import 'dart:convert';

import 'package:argus/app_controller.dart';
import 'package:argus/geo/area_index.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/io/config.dart';
import 'package:argus/io/file_manager.dart';
import 'package:argus/io/logger.dart';
import 'package:argus/main.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../test/support/test_doubles.dart' as shared;

class HarnessBuilder {
  const HarnessBuilder._();

  static AppConfig createConfig() {
    return shared.createTestConfig();
  }

  static GeoModel createSquareModel() {
    return shared.createSquareModel();
  }

  static AppController buildController({
    bool hasGeoJson = false,
    GeoModel? geoModel,
    bool? developerMode,
    StateSnapshot? snapshot,
    MonitoringPermissionState? permissionState,
    PermissionCoordinator? permissionCoordinator,
    LocationService? locationService,
    Notifier? notifier,
    AlarmVolumeClient? alarmVolumeClient,
    bool? isAndroid,
  }) {
    final config = createConfig();
    final stateMachine = StateMachine(config: config);
    final fileManager = HarnessFileManager(config: config);
    final controller = AppController(
      stateMachine: stateMachine,
      locationService: locationService ?? HarnessLocationService(),
      fileManager: fileManager,
      logger: HarnessEventLogger(),
      notifier: notifier ??
          Notifier(
            notificationsClient: HarnessLocalNotificationsClient(),
            alarmPlayer: HarnessAlarmPlayer(),
            vibrationPlayer: HarnessVibrationPlayer(),
          ),
      permissionCoordinator: permissionCoordinator,
      alarmVolumeClient: alarmVolumeClient,
      isAndroid: isAndroid,
    );

    GeoModel? selectedGeoModel = geoModel;
    AreaIndex? areaIndex;
    if (hasGeoJson && selectedGeoModel == null) {
      selectedGeoModel = createSquareModel();
    }
    if (selectedGeoModel != null) {
      areaIndex = AreaIndex.build(selectedGeoModel.polygons);
    }

    controller.debugSeed(
      config: config,
      geoJson: selectedGeoModel,
      areaIndex: areaIndex,
      snapshot: snapshot,
      developerMode: developerMode,
      permissionState: permissionState ??
          const MonitoringPermissionState(
            notificationStatus: PermissionStatus.granted,
            locationWhenInUseStatus: PermissionStatus.granted,
            locationAlwaysStatus: PermissionStatus.granted,
            locationServicesEnabled: true,
          ),
    );

    return controller;
  }

  static Widget buildApp(AppController controller) {
    return ArgusApp(controller: controller);
  }
}

class HarnessFileManager extends FileManager {
  HarnessFileManager({required this.config});

  final AppConfig config;

  @override
  Future<ConfigLoadResult> readConfig() async =>
      ConfigLoadResult(config: config);

  @override
  Future<XFile?> pickGeoJsonFile() async {
    return XFile.fromData(
      utf8.encode(shared.squareGeoJsonFixture),
      name: 'integration_square.geojson',
      mimeType: 'application/geo+json',
    );
  }
}

class HarnessEventLogger extends EventLogger {
  @override
  Future<String> logLocationFix(LocationFix fix) async => 'logged';

  @override
  Future<String> logStateChange(StateSnapshot snapshot) async =>
      snapshot.status.name;
}

class HarnessLocationService implements LocationService {
  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    startCount += 1;
    return const LocationServiceStartResult.started();
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  void add(LocationFix fix) {
    _controller.add(fix);
  }

  void addError(Object error) {
    _controller.addError(error);
  }
}

class HarnessLocalNotificationsClient implements LocalNotificationsClient {
  final List<int> shownIds = <int>[];
  final List<int> cancelledIds = <int>[];

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> ensureAndroidChannel(AndroidNotificationChannel channel) async {}

  @override
  Future<void> initialize(InitializationSettings settings) async {}

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails details,
  ) async {
    shownIds.add(id);
  }
}

class HarnessAlarmPlayer implements AlarmPlayer {
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

class HarnessVibrationPlayer implements VibrationPlayer {
  int startCount = 0;
  int pulseCount = 0;
  int stopCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<void> pulse(Duration duration) async {
    pulseCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

class HarnessAlarmVolumeClient implements AlarmVolumeClient {
  const HarnessAlarmVolumeClient();

  @override
  Future<AlarmVolumeState> getAlarmVolumeState() async {
    return const AlarmVolumeState(current: 10, max: 10, percent: 1);
  }

  @override
  Future<bool> openSoundSettings() async => true;
}

class HarnessPermissionGateway implements PermissionGateway {
  const HarnessPermissionGateway({
    this.notificationStatusValue = PermissionStatus.granted,
    this.locationWhenInUseStatusValue = PermissionStatus.granted,
    this.locationAlwaysStatusValue = PermissionStatus.granted,
    this.cameraStatusValue = PermissionStatus.granted,
  });

  final PermissionStatus notificationStatusValue;
  final PermissionStatus locationWhenInUseStatusValue;
  final PermissionStatus locationAlwaysStatusValue;
  final PermissionStatus cameraStatusValue;

  @override
  Future<PermissionStatus> cameraStatus() async => cameraStatusValue;

  @override
  Future<PermissionStatus> locationAlwaysStatus() async =>
      locationAlwaysStatusValue;

  @override
  Future<PermissionStatus> locationWhenInUseStatus() async =>
      locationWhenInUseStatusValue;

  @override
  Future<PermissionStatus> notificationStatus() async =>
      notificationStatusValue;

  @override
  Future<PermissionStatus> requestCamera() async => cameraStatusValue;

  @override
  Future<PermissionStatus> requestLocationAlways() async =>
      locationAlwaysStatusValue;

  @override
  Future<PermissionStatus> requestLocationWhenInUse() async =>
      locationWhenInUseStatusValue;

  @override
  Future<PermissionStatus> requestNotification() async =>
      notificationStatusValue;
}

class HarnessPermissionCoordinator extends PermissionCoordinator {
  HarnessPermissionCoordinator({
    PermissionGateway? gateway,
    bool locationServicesEnabled = true,
  }) : super(
          gateway: gateway ?? const HarnessPermissionGateway(),
          openSettings: () async => true,
          openLocationSettings: () async => true,
          locationServicesEnabled: () async => locationServicesEnabled,
        );
}
