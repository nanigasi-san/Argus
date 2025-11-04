import 'dart:async';

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

import 'support/notifier_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppController', () {
    test('loading new GeoJSON resets to init and stops alarm', () async {
      final config = _testConfig();
      final stateMachine = StateMachine(config: config);
      final locationService = FakeLocationService();
      final model = _squareModel();
      final fileManager = FakeFileManager(model: model, config: config);
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
      expect(controller.geoJsonLoaded, isTrue);
      expect(stateMachine.current, LocationStateStatus.init);
      expect(alarm.stopCount, 1);
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
  final points = <LatLng>[
    const LatLng(0, 0),
    const LatLng(0, 1),
    const LatLng(1, 1),
    const LatLng(1, 0),
  ];
  return GeoModel([
    GeoPolygon(points: points),
  ]);
}

class FakeFileManager extends FileManager {
  FakeFileManager({
    required this.model,
    required this.config,
  });

  final GeoModel model;
  final AppConfig config;

  @override
  Future<GeoModel?> pickAndLoadGeoJson() async => model;

  @override
  Future<AppConfig> readConfig() async => config;

  @override
  Future<GeoModel> loadBundledGeoJson(String assetPath) async => model;
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
