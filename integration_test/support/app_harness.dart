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

class HarnessBuilder {
  const HarnessBuilder._();

  static AppConfig createConfig() {
    return AppConfig(
      innerBufferM: 5,
      leaveConfirmSamples: 1,
      leaveConfirmSeconds: 1,
      gpsAccuracyBadMeters: 50,
      sampleIntervalS: const {'fast': 1},
      sampleDistanceM: const {'fast': 1},
      screenWakeOnLeave: false,
      alarmVolume: 1.0,
    );
  }

  static GeoModel createSquareModel() {
    return GeoModel.fromGeoJson(_squareGeoJson);
  }

  static AppController buildController({
    bool hasGeoJson = false,
    bool? developerMode,
    StateSnapshot? snapshot,
    MonitoringPermissionState? permissionState,
    bool pendingBackgroundDisclosurePrompt = false,
    PermissionCoordinator? permissionCoordinator,
  }) {
    final config = createConfig();
    final stateMachine = StateMachine(config: config);
    final fileManager = HarnessFileManager(config: config);
    final controller = AppController(
      stateMachine: stateMachine,
      locationService: HarnessLocationService(),
      fileManager: fileManager,
      logger: HarnessEventLogger(),
      notifier: Notifier(
        notificationsClient: HarnessLocalNotificationsClient(),
        alarmPlayer: HarnessAlarmPlayer(),
        vibrationPlayer: HarnessVibrationPlayer(),
      ),
      permissionCoordinator: permissionCoordinator,
    );

    GeoModel? geoModel;
    AreaIndex? areaIndex;
    if (hasGeoJson) {
      geoModel = createSquareModel();
      areaIndex = AreaIndex.build(geoModel.polygons);
    }

    controller.debugSeed(
      config: config,
      geoJson: geoModel,
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
      pendingBackgroundDisclosurePrompt: pendingBackgroundDisclosurePrompt,
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
  Future<AppConfig> readConfig() async => config;

  @override
  Future<XFile?> pickGeoJsonFile() async {
    return XFile.fromData(
      utf8.encode(_squareGeoJson),
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

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    return const LocationServiceStartResult.started();
  }

  @override
  Future<void> stop() async {}
}

class HarnessLocalNotificationsClient implements LocalNotificationsClient {
  @override
  Future<void> cancel(int id) async {}

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
  ) async {}
}

class HarnessAlarmPlayer implements AlarmPlayer {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class HarnessVibrationPlayer implements VibrationPlayer {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
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

const String _squareGeoJson = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {"name": "Integration Area"},
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[0,0],[1,0],[1,1],[0,1],[0,0]]]
      }
    }
  ]
}
''';
