import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'geo/area_index.dart';
import 'geo/geo_model.dart';
import 'io/config.dart';
import 'io/file_manager.dart';
import 'io/logger.dart';
import 'platform/location_service.dart';
import 'platform/notifier.dart';
import 'state_machine/state.dart';
import 'state_machine/state_machine.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.stateMachine,
    required this.locationService,
    required this.fileManager,
    required this.logger,
    required this.notifier,
  });

  final StateMachine stateMachine;
  final LocationService locationService;
  final FileManager fileManager;
  final EventLogger logger;
  final Notifier notifier;

  AppConfig? _config;
  GeoModel _geoModel = GeoModel.empty();
  AreaIndex _areaIndex = AreaIndex.empty();
  StateSnapshot _snapshot = StateSnapshot(
    status: LocationStateStatus.waitGeoJson,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    notes: 'Booting',
  );
  StreamSubscription<LocationFix>? _subscription;
  String? _lastErrorMessage;
  final List<String> _logs = <String>[];

  StateSnapshot get snapshot => _snapshot;
  AppConfig? get config => _config;
  bool get geoJsonLoaded => _geoModel.hasGeometry;
  String? get lastErrorMessage => _lastErrorMessage;
  List<String> get logs => List.unmodifiable(_logs);

  Future<void> initialize({String? initialGeoAsset}) async {
    await _requestPermissions();
    _config ??= await fileManager.readConfig();
    stateMachine.updateConfig(_config!);

    if (initialGeoAsset != null) {
      try {
        _geoModel = await fileManager.loadBundledGeoJson(initialGeoAsset);
        _areaIndex = AreaIndex.build(_geoModel.polygons);
        stateMachine.updateGeometry(_geoModel, _areaIndex);
      } catch (_) {
        _geoModel = GeoModel.empty();
        _areaIndex = AreaIndex.empty();
        _lastErrorMessage = 'Failed to load bundled GeoJSON.';
      }
    }
    _snapshot = _snapshot.copyWith(
      status: geoJsonLoaded
          ? LocationStateStatus.init
          : LocationStateStatus.waitGeoJson,
      timestamp: DateTime.now(),
      geoJsonLoaded: geoJsonLoaded,
      notes: geoJsonLoaded
          ? 'Ready to monitor'
          : 'Load GeoJSON to start monitoring',
    );
    _addLogLine(
      '${DateTime.now().toIso8601String()} [APP] initialized '
      '${geoJsonLoaded ? 'with bundled GeoJSON' : 'waiting for GeoJSON'}',
    );
    notifyListeners();
  }

  void clearError() {
    if (_lastErrorMessage != null) {
      _lastErrorMessage = null;
      notifyListeners();
    }
  }

  Future<void> startMonitoring() async {
    if (_config == null || !geoJsonLoaded) {
      return;
    }
    await locationService.start(_config!);
    await _subscription?.cancel();
    _subscription = locationService.stream.listen(_handleFix);
    _addLogLine(
      '${DateTime.now().toIso8601String()} [APP] monitoring started',
    );
    notifyListeners();
  }

  Future<void> stopMonitoring() async {
    await _subscription?.cancel();
    _subscription = null;
    await locationService.stop();
    _addLogLine(
      '${DateTime.now().toIso8601String()} [APP] monitoring stopped',
    );
    notifyListeners();
  }

  Future<void> reloadGeoJsonFromPicker() async {
    try {
      final model = await fileManager.pickAndLoadGeoJson();
      if (model == null) {
        return;
      }
      _geoModel = model;
      _areaIndex = AreaIndex.build(model.polygons);
      stateMachine.updateGeometry(_geoModel, _areaIndex);
      _snapshot = _snapshot.copyWith(
        status: LocationStateStatus.init,
        timestamp: DateTime.now(),
        geoJsonLoaded: true,
        notes: 'GeoJSON loaded',
      );
      _lastErrorMessage = null;
      _addLogLine(
        '${DateTime.now().toIso8601String()} [APP] GeoJSON loaded from picker',
      );
      notifyListeners();
    } on FormatException catch (e) {
      _lastErrorMessage = 'Failed to parse GeoJSON: ${e.message}';
      _addLogLine(
        '${DateTime.now().toIso8601String()} [ERROR] ${_lastErrorMessage!}',
      );
      notifyListeners();
    } catch (e) {
      _lastErrorMessage = 'Unable to open file: ${e.toString()}';
      _addLogLine(
        '${DateTime.now().toIso8601String()} [ERROR] ${_lastErrorMessage!}',
      );
      notifyListeners();
    }
  }

  Future<void> _handleFix(LocationFix fix) async {
    final previous = _snapshot.status;
    final locationLog = await logger.logLocationFix(fix);
    _addLogLine(locationLog);
    final evaluation = stateMachine.evaluate(fix);
    _snapshot = evaluation.copyWith(
      geoJsonLoaded: geoJsonLoaded,
    );
    final stateLog = await logger.logStateChange(_snapshot);
    _addLogLine(stateLog);
    await notifier.updateBadge(_snapshot.status);
    if (previous != LocationStateStatus.outer &&
        _snapshot.status == LocationStateStatus.outer) {
      await notifier.notifyOuter();
    } else if (previous == LocationStateStatus.outer &&
        _snapshot.status != LocationStateStatus.outer) {
      await notifier.notifyRecover();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _addLogLine(String line) {
    if (line.isEmpty) {
      return;
    }
    _logs.insert(0, line);
    if (_logs.length > 200) {
      _logs.removeLast();
    }
  }

  Future<void> _requestPermissions() async {
    await _ensureNotificationPermission();
    await _ensureLocationPermission();
  }

  static Future<AppController> bootstrap() async {
    final fileManager = FileManager();
    final config = await fileManager.readConfig();
    final stateMachine = StateMachine(config: config);
    final locationService = GeolocatorLocationService();
    final logFile = await fileManager.openLogFile();
    final logger = EventLogger(logFile);
    final notificationsPlugin = FlutterLocalNotificationsPlugin();
    final notifier = Notifier(notificationsPlugin);
    await notifier.initialize();
    final controller = AppController(
      stateMachine: stateMachine,
      locationService: locationService,
      fileManager: fileManager,
      logger: logger,
      notifier: notifier,
    );
    controller._config = config;
    await controller.initialize(
      initialGeoAsset: 'assets/geojson/sample_area.geojson',
    );
    return controller;
  }

  Future<void> _ensureNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    if (status.isDenied || status.isLimited) {
      final result = await Permission.notification.request();
      if (result.isPermanentlyDenied) {
        await openAppSettings();
      }
    }
  }

  Future<void> _ensureLocationPermission() async {
    var status = await Permission.locationAlways.status;
    if (status.isLimited) {
      status = await Permission.locationAlways.request();
    }
    if (status.isDenied || status.isRestricted) {
      final whenInUseStatus = await Permission.locationWhenInUse.request();
      if (!whenInUseStatus.isGranted) {
        return;
      }
      status = await Permission.locationAlways.request();
    }
    if (status.isPermanentlyDenied || !status.isGranted) {
      await openAppSettings();
    }
  }
}
