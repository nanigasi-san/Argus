import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'geo/area_index.dart';
import 'geo/geo_model.dart';
import 'io/config.dart';
import 'io/file_manager.dart';
import 'io/log_entry.dart';
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
  bool _developerMode = false;
  AreaIndex _areaIndex = AreaIndex.empty();
  StateSnapshot _snapshot = StateSnapshot(
    status: LocationStateStatus.waitGeoJson,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    notes: 'Booting',
  );
  StreamSubscription<LocationFix>? _subscription;
  String? _lastErrorMessage;
  String? _geoJsonFileName;
  final List<AppLogEntry> _logs = <AppLogEntry>[];

  StateSnapshot get snapshot => _snapshot;
  AppConfig? get config => _config;
  bool get geoJsonLoaded => _geoModel.hasGeometry;
  String? get lastErrorMessage => _lastErrorMessage;
  String? get geoJsonFileName => _geoJsonFileName;
  List<AppLogEntry> get logs => List.unmodifiable(_logs);
  bool get developerMode => _developerMode;

  Future<void> initialize() async {
    await _requestPermissions();
    _config ??= await fileManager.readConfig();
    stateMachine.updateConfig(_config!);

    _snapshot = _snapshot.copyWith(
      status: geoJsonLoaded
          ? LocationStateStatus.waitStart
          : LocationStateStatus.waitGeoJson,
      timestamp: DateTime.now(),
      geoJsonLoaded: geoJsonLoaded,
      notes: geoJsonLoaded
          ? 'Ready to monitor'
          : 'Load GeoJSON to start monitoring',
    );
    _logInfo(
      'APP',
      geoJsonLoaded
          ? 'Initialized with bundled GeoJSON.'
          : 'Initialization completed. Waiting for GeoJSON.',
      timestamp: _snapshot.timestamp,
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
    _logInfo('APP', 'Monitoring started.');
    notifyListeners();
  }

  Future<void> stopMonitoring() async {
    await _subscription?.cancel();
    _subscription = null;
    await locationService.stop();
    _logInfo('APP', 'Monitoring stopped.');
    notifyListeners();
  }

  void setDeveloperMode(bool enabled) {
    if (_developerMode == enabled) {
      return;
    }
    _developerMode = enabled;
    _logInfo('APP', 'Developer mode ${enabled ? 'enabled' : 'disabled'}.');
    notifyListeners();
  }

  Future<void> updateConfig(AppConfig newConfig) async {
    if (_config == null) {
      return;
    }

    final wasMonitoring = _subscription != null;

    // 監視中であれば一時停止
    if (wasMonitoring) {
      await stopMonitoring();
    }

    // 設定を更新
    _config = newConfig;
    stateMachine.updateConfig(newConfig);

    // 設定をファイルに保存
    await fileManager.saveConfig(newConfig);

    _logInfo(
      'APP',
      'Config updated: innerBuffer=${newConfig.innerBufferM}m, '
          'polling=${newConfig.sampleIntervalS['fast']}s, '
          'gpsThreshold=${newConfig.gpsAccuracyBadMeters}m',
    );

    // 監視中だった場合は新しい設定で再開
    if (wasMonitoring && geoJsonLoaded) {
      await startMonitoring();
    }

    notifyListeners();
  }

  Future<void> reloadGeoJsonFromPicker() async {
    // 先に監視を停止（ファイル操作前に停止）
    await stopMonitoring();

    try {
      // ファイル名を取得するために、file_selectorを直接使用
      final file = await fileManager.pickGeoJsonFile();
      if (file == null) {
        // キャンセル時は何もしない（ログも出さない）
        return;
      }

      final raw = await file.readAsString();
      final model = GeoModel.fromGeoJson(raw);

      _geoModel = model;
      // ファイル名をpathから抽出し、拡張子を.geojsonに統一
      final extractedName = _extractFileName(file.path) ?? file.name;
      _geoJsonFileName = _normalizeToGeoJson(extractedName);
      _areaIndex = AreaIndex.build(model.polygons);
      stateMachine.updateGeometry(_geoModel, _areaIndex);

      // waitStart状態に戻し、距離・方位角などの情報をクリア
      _snapshot = StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.now(),
        geoJsonLoaded: true,
        distanceToBoundaryM: null,
        bearingToBoundaryDeg: null,
        nearestBoundaryPoint: null,
        notes: 'GeoJSON loaded',
      );
      await notifier.stopAlarm();
      _lastErrorMessage = null;
      _logInfo('APP', 'GeoJSON loaded.', timestamp: _snapshot.timestamp);
      notifyListeners();
    } on FormatException catch (e) {
      _lastErrorMessage = 'Failed to parse GeoJSON: ${e.message}';
      _logError('APP', _lastErrorMessage!);
      notifyListeners();
    } catch (e) {
      // ファイルピッカーをキャンセルした場合などはエラーログを出さない
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('cancel') ||
          errorMessage.contains('user') ||
          errorMessage.contains('abort')) {
        return;
      }
      _lastErrorMessage = 'Unable to open file: ${e.toString()}';
      _logError('APP', _lastErrorMessage!);
      notifyListeners();
    }
  }

  String? _extractFileName(String path) {
    if (path.isEmpty) return null;
    // パスセパレータで分割して最後の要素（ファイル名）を取得
    final parts = path.split(RegExp(r'[/\\]'));
    final fileName = parts.last;
    // クエリパラメータやフラグメントを除去
    final cleanFileName = fileName.split('?').first.split('#').first;
    return cleanFileName.isNotEmpty ? cleanFileName : null;
  }

  String _normalizeToGeoJson(String fileName) {
    // 拡張子を除去
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    // .geojson拡張子を追加
    return '$nameWithoutExt.geojson';
  }

  Future<void> _handleFix(LocationFix fix) async {
    final previous = _snapshot.status;
    await logger.logLocationFix(fix);
    _logDebug(
      'GPS',
      'lat=${fix.latitude.toStringAsFixed(6)} '
          'lon=${fix.longitude.toStringAsFixed(6)} '
          'acc=${fix.accuracyMeters?.toStringAsFixed(1) ?? '-'}m',
      timestamp: fix.timestamp,
    );
    final evaluation = stateMachine.evaluate(fix);
    _snapshot = evaluation.copyWith(
      geoJsonLoaded: geoJsonLoaded,
    );
    await logger.logStateChange(_snapshot);
    _logInfo(
      'STATE',
      describeSnapshot(_snapshot),
      timestamp: _snapshot.timestamp,
    );
    await notifier.updateBadge(_snapshot.status);
    if (previous != LocationStateStatus.outer &&
        _snapshot.status == LocationStateStatus.outer) {
      await notifier.notifyOuter();
      _logWarning(
        'ALERT',
        'Safe zone exited.${_buildNavHint(_snapshot)}',
        timestamp: _snapshot.timestamp,
      );
    } else if (previous == LocationStateStatus.outer &&
        _snapshot.status != LocationStateStatus.outer) {
      await notifier.notifyRecover();
      _logInfo(
        'ALERT',
        'Returned to safe zone.',
        timestamp: _snapshot.timestamp,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _addLogEntry(AppLogEntry entry) {
    _logs.insert(0, entry);
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
    final logger = EventLogger();
    final notificationsPlugin = FlutterLocalNotificationsPlugin();
    final notifier = Notifier(
      plugin: notificationsPlugin,
      vibrationPlayer: RepeatingVibrationPlayer(),
    );
    await notifier.initialize();
    final controller = AppController(
      stateMachine: stateMachine,
      locationService: locationService,
      fileManager: fileManager,
      logger: logger,
      notifier: notifier,
    );
    controller._config = config;
    await controller.initialize();
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

  void _log(
    String tag,
    String message, {
    AppLogLevel level = AppLogLevel.info,
    DateTime? timestamp,
  }) {
    final entry = AppLogEntry(
      tag: tag,
      message: message,
      level: level,
      timestamp: timestamp ?? DateTime.now(),
    );
    _addLogEntry(entry);
  }

  void _logInfo(String tag, String message, {DateTime? timestamp}) {
    _log(tag, message, level: AppLogLevel.info, timestamp: timestamp);
  }

  void _logWarning(String tag, String message, {DateTime? timestamp}) {
    _log(tag, message, level: AppLogLevel.warning, timestamp: timestamp);
  }

  void _logError(String tag, String message, {DateTime? timestamp}) {
    _log(tag, message, level: AppLogLevel.error, timestamp: timestamp);
  }

  void _logDebug(String tag, String message, {DateTime? timestamp}) {
    _log(tag, message, level: AppLogLevel.debug, timestamp: timestamp);
  }

  @visibleForTesting
  String describeSnapshot(StateSnapshot snapshot) {
    final showNav =
        _developerMode || snapshot.status == LocationStateStatus.outer;
    final dist = showNav && snapshot.distanceToBoundaryM != null
        ? '${snapshot.distanceToBoundaryM!.toStringAsFixed(2)}m'
        : '-';
    final accuracy = snapshot.horizontalAccuracyM != null
        ? '${snapshot.horizontalAccuracyM!.toStringAsFixed(1)}m'
        : '-';
    final bearing = showNav && snapshot.bearingToBoundaryDeg != null
        ? '${snapshot.bearingToBoundaryDeg!.toStringAsFixed(0)}deg'
        : '-';
    final nearest = showNav && snapshot.nearestBoundaryPoint != null
        ? ' (${snapshot.nearestBoundaryPoint!.latitude.toStringAsFixed(5)},'
            '${snapshot.nearestBoundaryPoint!.longitude.toStringAsFixed(5)})'
        : '';
    final notes = (snapshot.notes ?? '').isEmpty ? '' : ' (${snapshot.notes})';
    return 'status=${snapshot.status.name} dist=$dist acc=$accuracy '
        'bearing=$bearing$nearest$notes';
  }

  String _buildNavHint(StateSnapshot snapshot) {
    final distance = snapshot.distanceToBoundaryM;
    final bearing = snapshot.bearingToBoundaryDeg;
    final target = snapshot.nearestBoundaryPoint;
    if (distance == null || bearing == null || target == null) {
      return '';
    }
    final cardinal = _cardinalFromBearing(bearing);
    final formattedBearing = '${bearing.toStringAsFixed(0)}deg';
    final formattedTarget =
        'lat=${target.latitude.toStringAsFixed(5)}, lon=${target.longitude.toStringAsFixed(5)}';
    return ' Move ${distance.toStringAsFixed(0)}m toward $cardinal '
        '($formattedBearing) heading to $formattedTarget.';
  }

  String _cardinalFromBearing(double bearing) {
    const labels = <String>[
      'N',
      'NE',
      'E',
      'SE',
      'S',
      'SW',
      'W',
      'NW',
    ];
    final normalized = (bearing % 360 + 360) % 360;
    final index = ((normalized + 22.5) ~/ 45) % labels.length;
    return labels[index];
  }
}
