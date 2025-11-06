import 'dart:async';
import 'dart:convert';

import 'package:argus/app_controller.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/io/config.dart';
import 'package:argus/io/file_manager.dart';
import 'package:argus/io/logger.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:file_selector/file_selector.dart';

import 'notifier_fakes.dart';

AppConfig createTestConfig() {
  return AppConfig(
    innerBufferM: 5,
    leaveConfirmSamples: 1,
    leaveConfirmSeconds: 1,
    gpsAccuracyBadMeters: 50,
    sampleIntervalS: const {'fast': 1},
    sampleDistanceM: const {'fast': 1},
    screenWakeOnLeave: false,
  );
}

GeoModel buildSquareModel() {
  return GeoModel.fromGeoJson(_squareGeoJson);
}

AppController buildTestController({
  AppConfig? config,
  GeoModel? geoModel,
  StateSnapshot? snapshot,
  bool developerMode = false,
  bool hasGeoJson = false,
  String? geoJsonFileName,
  EventLogger? logger,
}) {
  final effectiveConfig = config ?? createTestConfig();
  final controller = AppController(
    stateMachine: StateMachine(config: effectiveConfig),
    locationService: FakeLocationService(),
    fileManager: FakeFileManager(config: effectiveConfig),
    logger: logger ?? FakeEventLogger(),
    notifier: Notifier(
      notificationsClient: FakeLocalNotificationsClient(),
      alarmPlayer: FakeAlarmPlayer(),
    ),
  );
  controller.debugInitialize(
    config: effectiveConfig,
    geoModel: geoModel ?? (hasGeoJson ? buildSquareModel() : null),
    snapshot: snapshot ??
        StateSnapshot(
          status: hasGeoJson
              ? LocationStateStatus.waitStart
              : LocationStateStatus.waitGeoJson,
          timestamp: DateTime.now(),
        ),
    developerMode: developerMode,
    geoJsonFileName:
        geoJsonFileName ?? (hasGeoJson ? 'test_square.geojson' : null),
  );
  return controller;
}

class FakeFileManager extends FileManager {
  FakeFileManager({
    required this.config,
  });

  final AppConfig config;

  GeoModel get _model => buildSquareModel();

  @override
  Future<AppConfig> readConfig() async => config;

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

class FakeLocationService implements LocationService {
  FakeLocationService();

  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();

  bool hasStarted = false;
  bool hasStopped = false;

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<void> start(AppConfig config) async {
    hasStarted = true;
  }

  @override
  Future<void> stop() async {
    hasStopped = true;
  }

  void add(LocationFix fix) {
    _controller.add(fix);
  }
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
