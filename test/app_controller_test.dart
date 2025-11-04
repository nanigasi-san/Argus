import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

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

import 'support/notifier_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppController', () {
    test('loading new GeoJSON resets to init and stops alarm', () async {
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

      await notifier.notifyOuter();
      expect(alarm.playCount, 1);

      await controller.reloadGeoJsonFromPicker();
      expect(controller.snapshot.status, LocationStateStatus.init);

      expect(controller.snapshot.status, LocationStateStatus.init);
      expect(controller.geoJsonLoaded, isTrue);
      expect(stateMachine.current, LocationStateStatus.init);
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

AppConfig _testConfig() {
  return AppConfig(
    innerBufferM: 5,
    leaveConfirmSamples: 1,
    leaveConfirmSeconds: 1,
    gpsAccuracyBadMeters: 50,
    sampleIntervalS: {'fast': 1},
    sampleDistanceM: {'fast': 1},
    screenWakeOnLeave: false,
  );
}

GeoModel _squareModel() {
  return GeoModel.fromGeoJson(_squareGeoJson);
}

AppController _buildController() {
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

class FakeFileManager extends FileManager {
  FakeFileManager({
    required this.config,
  });

  final AppConfig config;

  GeoModel get _model => _squareModel();

  @override
  Future<AppConfig> readConfig() async => config;

  @override
  Future<GeoModel?> pickAndLoadGeoJson() async => _model;

  @override
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

  bool started = false;
  bool stopped = false;

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<void> start(AppConfig config) async {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void add(LocationFix fix) {
    _controller.add(fix);
  }
}
