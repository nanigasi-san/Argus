import 'dart:async';
import 'dart:convert';

import 'package:argus/app_controller.dart';
import 'package:argus/geo/area_index.dart';
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
    alarmVolume: 1.0,
  );
}

GeoModel createSquareModel() {
  return GeoModel.fromGeoJson(_squareGeoJson);
}

class FakeFileManager extends FileManager {
  FakeFileManager({required this.config});

  final AppConfig config;

  GeoModel get _model => createSquareModel();

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

AppController buildTestController({
  bool hasGeoJson = false,
  StateSnapshot? snapshot,
  bool? developerMode,
}) {
  final config = createTestConfig();
  final stateMachine = StateMachine(config: config);
  final fileManager = FakeFileManager(config: config);
  final controller = AppController(
    stateMachine: stateMachine,
    locationService: FakeLocationService(),
    fileManager: fileManager,
    logger: FakeEventLogger(),
    notifier: Notifier(
      notificationsClient: FakeLocalNotificationsClient(),
      alarmPlayer: FakeAlarmPlayer(),
    ),
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
  );

  return controller;
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
