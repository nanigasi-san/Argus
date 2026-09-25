import 'dart:async';
import 'dart:io';

import 'package:argus/app_controller.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/io/config.dart';
import 'package:argus/io/file_manager.dart';
import 'package:argus/platform/compass_service.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_harness.dart';

// A square spanning 35.000–35.010 N and 139.000–139.010 E.
const coreGeoJsonFixture = '''
{"type":"FeatureCollection","features":[{"type":"Feature",
"properties":{},"geometry":{"type":"Polygon","coordinates":[[
[139.000,35.000],[139.010,35.000],[139.010,35.010],
[139.000,35.010],[139.000,35.000]]]}}]}
''';
const inside = LatLng(35.005, 139.005);
const outside = LatLng(35.005, 139.020);
// About 36 m from the west edge: INNER at the 0 m default, NEAR at 50 m.
const bufferProbe = LatLng(35.005, 139.0004);

class CoreE2eHarness {
  CoreE2eHarness._(this.documents);

  final Directory documents;
  final location = ScriptedLocationService();
  final permissions = MutablePermissionGateway();
  final notifications = RecordingNotificationsClient();
  final alarm = RecordingAlarmPlayer();
  final vibration = RecordingVibrationPlayer();
  final logger = RecordingEventLogger();
  late final AppController controller;

  static Future<CoreE2eHarness> create({bool permissionsGranted = true}) async {
    final temp = await getTemporaryDirectory();
    final harness = CoreE2eHarness._(
      await temp.createTemp('core_e2e_'),
    );
    harness.permissions.granted = permissionsGranted;
    final config = await AppConfig.loadDefault();
    harness.controller = AppController(
      stateMachine: StateMachine(config: config),
      locationService: harness.location,
      fileManager: FileManager(
        documentsDirectoryProvider: () async => harness.documents,
      ),
      logger: harness.logger,
      notifier: Notifier(
        notificationsClient: harness.notifications,
        alarmPlayer: harness.alarm,
        vibrationPlayer: harness.vibration,
      ),
      permissionCoordinator: PermissionCoordinator(
        gateway: harness.permissions,
        openSettings: () async => true,
        openLocationSettings: () async => true,
        locationServicesEnabled: () async => true,
      ),
      compassService: const SilentCompassService(),
      alarmVolumeClient: const FixedAlarmVolumeClient(),
    );
    await harness.controller.initialize();
    return harness;
  }

  Future<bool> loadGeoJson() async {
    final bundle = await encodeGeoJson(const GeoJsonQrEncodeInput(
      geoJson: coreGeoJsonFixture,
      sourceFileName: 'core_square.geojson',
      scheme: GeoJsonQrScheme.agz1,
      generatePng: false,
    ));
    return controller.reloadGeoJsonFromQr(bundle.qrTexts.single);
  }

  LocationFix fix(LatLng point, int elapsedSeconds, {double accuracy = 5}) {
    return LocationFix(
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp:
          DateTime.utc(2026, 1, 1).add(Duration(seconds: elapsedSeconds)),
      accuracyMeters: accuracy,
      monitoringElapsed: Duration(seconds: elapsedSeconds),
    );
  }

  Future<void> dispose() async {
    await controller.handleAppTermination();
    controller.dispose();
    await location.close();
    controller.notifier.badgeState.dispose();
    await documents.delete(recursive: true);
  }
}

class ScriptedLocationService implements LocationService {
  final _controller = StreamController<LocationFix>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  int activeSubscriptions = 0;
  int deliveredFixCount = 0;
  AppConfig? lastStartConfig;
  bool running = false;

  @override
  late final Stream<LocationFix> stream = Stream<LocationFix>.multi((sink) {
    activeSubscriptions++;
    final subscription = _controller.stream.listen((fix) {
      deliveredFixCount++;
      sink.addSync(fix);
    }, onError: sink.addErrorSync, onDone: sink.closeSync);
    sink.onCancel = () async {
      await subscription.cancel();
      activeSubscriptions--;
    };
  }, isBroadcast: true);

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    startCount++;
    lastStartConfig = config;
    running = true;
    return const LocationServiceStartResult.started();
  }

  @override
  Future<void> stop() async {
    stopCount++;
    running = false;
  }

  // Allow emissions while stopped to verify subscription cancellation.
  void emit(LocationFix fix) => _controller.add(fix);
  Future<void> close() => _controller.close();
}

class MutablePermissionGateway implements PermissionGateway {
  bool granted = true;
  PermissionStatus get status =>
      granted ? PermissionStatus.granted : PermissionStatus.denied;

  @override
  Future<PermissionStatus> notificationStatus() async => status;
  @override
  Future<PermissionStatus> requestNotification() async => status;
  @override
  Future<PermissionStatus> locationWhenInUseStatus() async => status;
  @override
  Future<PermissionStatus> requestLocationWhenInUse() async => status;
  @override
  Future<PermissionStatus> locationAlwaysStatus() async => status;
  @override
  Future<PermissionStatus> requestLocationAlways() async => status;
  @override
  Future<PermissionStatus> cameraStatus() async => PermissionStatus.denied;
  @override
  Future<PermissionStatus> requestCamera() async => PermissionStatus.denied;
}

class RecordingNotificationsClient extends HarnessLocalNotificationsClient {
  final activeIds = <int>{};
  int showCount = 0;
  int cancelCount = 0;

  @override
  Future<void> show(
      int id, String? title, String? body, NotificationDetails details) async {
    showCount++;
    activeIds.add(id);
  }

  @override
  Future<void> cancel(int id) async {
    cancelCount++;
    activeIds.remove(id);
  }
}

class RecordingAlarmPlayer implements AlarmPlayer {
  bool playing = false;
  int startCount = 0;
  int stopCount = 0;
  @override
  Future<void> start() async {
    startCount++;
    playing = true;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    playing = false;
  }
}

class RecordingVibrationPlayer implements VibrationPlayer {
  bool playing = false;
  @override
  Future<void> start() async => playing = true;
  @override
  Future<void> stop() async => playing = false;
}

class RecordingEventLogger extends HarnessEventLogger {
  final fixes = <LocationFix>[];
  final states = <StateSnapshot>[];
  @override
  Future<String> logLocationFix(LocationFix fix) async {
    fixes.add(fix);
    return 'logged';
  }

  @override
  Future<String> logStateChange(StateSnapshot snapshot) async {
    states.add(snapshot);
    return snapshot.status.name;
  }
}

class SilentCompassService implements CompassService {
  const SilentCompassService();
  @override
  Stream<double?> get headings => const Stream<double?>.empty();
}

class FixedAlarmVolumeClient implements AlarmVolumeClient {
  const FixedAlarmVolumeClient();
  @override
  Future<AlarmVolumeState> getAlarmVolumeState() async =>
      const AlarmVolumeState(current: 10, max: 10, percent: 1);
  @override
  Future<bool> openSoundSettings() async => true;
}
