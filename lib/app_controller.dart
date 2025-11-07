import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'geo/area_index.dart';
import 'geo/geo_model.dart';
import 'io/config.dart';
import 'io/file_manager.dart';
import 'io/log_entry.dart';
import 'io/logger.dart';
import 'platform/location_service.dart';
import 'platform/notifier.dart';
import 'qr/geojson_qr_codec.dart';
import 'state_machine/state.dart';
import 'state_machine/state_machine.dart';

/// アプリケーション全体の状態と動作を管理するコントローラ。
///
/// 位置情報の監視、GeoJSONの読み込み、設定管理、ログ記録などを統合的に処理します。
/// ChangeNotifierを継承しており、状態変更時にUIに通知します。
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
  String? _tempGeoJsonFilePath;
  final List<AppLogEntry> _logs = <AppLogEntry>[];

  StateSnapshot get snapshot => _snapshot;
  AppConfig? get config => _config;
  bool get geoJsonLoaded => _geoModel.hasGeometry;
  String? get lastErrorMessage => _lastErrorMessage;
  String? get geoJsonFileName => _geoJsonFileName;
  List<AppLogEntry> get logs => List.unmodifiable(_logs);
  bool get developerMode => _developerMode;

  /// アプリケーションを初期化します。
  ///
  /// 権限の要求、設定ファイルの読み込み、状態マシンの初期化を行います。
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

  /// エラーメッセージをクリアします。
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

  /// 位置情報の監視を停止します。
  Future<void> stopMonitoring() async {
    await _subscription?.cancel();
    _subscription = null;
    await locationService.stop();
    _logInfo('APP', 'Monitoring stopped.');
    notifyListeners();
  }

  /// 開発者モードの有効/無効を切り替えます。
  ///
  /// 開発者モードが有効な場合、UIに詳細な状態情報が表示されます。
  void setDeveloperMode(bool enabled) {
    if (_developerMode == enabled) {
      return;
    }
    _developerMode = enabled;
    _logInfo('APP', 'Developer mode ${enabled ? 'enabled' : 'disabled'}.');
    notifyListeners();
  }

  /// アプリケーション設定を更新します。
  ///
  /// 監視中の場合は一時停止してから設定を更新し、再開します。
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

  /// ファイルピッカーからGeoJSONファイルを読み込みます。
  ///
  /// ファイルが正常に読み込まれた場合、状態マシンとエリアインデックスを更新します。
  /// エラーが発生した場合は、エラーメッセージを設定します。
  Future<void> reloadGeoJsonFromPicker() async {
    await stopMonitoring();

    try {
      final file = await fileManager.pickGeoJsonFile();
      if (file == null) {
        return;
      }

      final raw = await file.readAsString();
      final model = GeoModel.fromGeoJson(raw);
      final extractedName = _extractFileName(file.path) ?? file.name;
      final normalizedFileName = _normalizeToGeoJson(extractedName);

      await _loadGeoJsonModel(model, normalizedFileName, 'GeoJSON loaded');
    } on FormatException catch (e) {
      _handleGeoJsonError('Failed to parse GeoJSON: ${e.message}');
    } catch (e) {
      if (_isUserCancellationError(e)) {
        return;
      }
      _handleGeoJsonError('Unable to open file: ${e.toString()}');
    }
  }

  /// GeoJSONモデルを読み込み、状態を更新します。
  Future<void> _loadGeoJsonModel(
    GeoModel model,
    String fileName,
    String notes,
  ) async {
    _geoModel = model;
    _geoJsonFileName = fileName;
    _areaIndex = AreaIndex.build(model.polygons);
    stateMachine.updateGeometry(_geoModel, _areaIndex);

    _snapshot = StateSnapshot(
      status: LocationStateStatus.waitStart,
      timestamp: DateTime.now(),
      geoJsonLoaded: true,
      distanceToBoundaryM: null,
      bearingToBoundaryDeg: null,
      nearestBoundaryPoint: null,
      notes: notes,
    );
    await notifier.stopAlarm();
    _lastErrorMessage = null;
    _logInfo('APP', 'GeoJSON loaded.', timestamp: _snapshot.timestamp);
    notifyListeners();
  }

  /// GeoJSON読み込みエラーを処理します。
  void _handleGeoJsonError(String message) {
    _lastErrorMessage = message;
    _logError('APP', _lastErrorMessage!);
    notifyListeners();
  }

  /// エラーがユーザーキャンセルによるものかどうかを判定します。
  bool _isUserCancellationError(dynamic error) {
    final errorMessage = error.toString().toLowerCase();
    return errorMessage.contains('cancel') ||
        errorMessage.contains('user') ||
        errorMessage.contains('abort');
  }

  /// QRコードからGeoJSONを読み込みます。
  ///
  /// QRテキストからGeoJSONを復元し、一時ファイルとして保存してから
  /// 状態マシンとエリアインデックスを更新します。
  /// エラーが発生した場合は、エラーメッセージを設定します。
  Future<void> reloadGeoJsonFromQr(String qrText) async {
    await stopMonitoring();

    try {
      if (!qrText.startsWith('gjb1:')) {
        _handleGeoJsonError('Invalid QR code format. Expected gjb1: scheme.');
        return;
      }

      final restoredGeoJson = await _decodeQrText(qrText);
      final tempFileName = await _saveTempGeoJson(restoredGeoJson);
      final model = GeoModel.fromGeoJson(restoredGeoJson);

      await _loadGeoJsonModel(model, tempFileName, 'GeoJSON loaded from QR code');
    } on GeoJsonQrException catch (e) {
      _handleGeoJsonError('Failed to decode QR code: ${e.message}');
    } on FormatException catch (e) {
      _handleGeoJsonError('Failed to parse GeoJSON: ${e.message}');
    } catch (e) {
      _handleGeoJsonError('Unable to load GeoJSON from QR code: ${e.toString()}');
    }
  }

  /// QRテキストをデコードしてGeoJSON文字列を取得します。
  Future<String> _decodeQrText(String qrText) async {
    return await decodeGeoJson(
      GeoJsonQrDecodeInput(
        qrTexts: [qrText],
        verifyHash: true,
      ),
    );
  }

  /// GeoJSONを一時ファイルとして保存し、ファイル名を返します。
  Future<String> _saveTempGeoJson(String geoJson) async {
    await cleanupTempGeoJsonFile();

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/temp_geojson_$timestamp.geojson');
    await tempFile.writeAsString(geoJson);

    _tempGeoJsonFilePath = tempFile.path;
    return 'temp_geojson_$timestamp.geojson';
  }

  /// 一時GeoJSONファイルを削除します。
  ///
  /// アプリ終了時や新しいQRコードを読み込む際に呼び出されます。
  Future<void> cleanupTempGeoJsonFile() async {
    if (_tempGeoJsonFilePath != null) {
      try {
        final file = File(_tempGeoJsonFilePath!);
        if (await file.exists()) {
          await file.delete();
          _logInfo('APP', 'Temporary GeoJSON file deleted: $_tempGeoJsonFilePath');
        }
      } catch (e) {
        _logError('APP', 'Failed to delete temporary GeoJSON file: $e');
      }
      _tempGeoJsonFilePath = null;
    }
  }

  /// パスからファイル名を抽出します。
  String? _extractFileName(String path) {
    if (path.isEmpty) return null;
    // パスセパレータで分割して最後の要素（ファイル名）を取得
    final parts = path.split(RegExp(r'[/\\]'));
    final fileName = parts.last;
    // クエリパラメータやフラグメントを除去
    final cleanFileName = fileName.split('?').first.split('#').first;
    return cleanFileName.isNotEmpty ? cleanFileName : null;
  }

  /// ファイル名の拡張子を.geojsonに正規化します。
  String _normalizeToGeoJson(String fileName) {
    // 拡張子を除去
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    // .geojson拡張子を追加
    return '$nameWithoutExt.geojson';
  }

  /// 位置情報の更新を処理します。
  ///
  /// 位置情報をログに記録し、状態マシンで評価して状態を更新します。
  /// OUTER状態への遷移時には通知とアラームを発火し、
  /// OUTER状態からの復帰時には通知をキャンセルしてアラームを停止します。
  Future<void> _handleFix(LocationFix fix) async {
    final previous = _snapshot.status;
    await _logLocationFix(fix);
    final evaluation = stateMachine.evaluate(fix);
    _snapshot = evaluation.copyWith(geoJsonLoaded: geoJsonLoaded);
    await _processStateChange(previous);
    notifyListeners();
  }

  /// 位置情報をログに記録します。
  Future<void> _logLocationFix(LocationFix fix) async {
    await logger.logLocationFix(fix);
    _logDebug(
      'GPS',
      'lat=${fix.latitude.toStringAsFixed(6)} '
          'lon=${fix.longitude.toStringAsFixed(6)} '
          'acc=${fix.accuracyMeters?.toStringAsFixed(1) ?? '-'}m',
      timestamp: fix.timestamp,
    );
  }

  /// 状態変化を処理します。
  ///
  /// 状態をログに記録し、OUTER状態への遷移や復帰を検知して通知を制御します。
  Future<void> _processStateChange(LocationStateStatus previous) async {
    await logger.logStateChange(_snapshot);
    _logInfo(
      'STATE',
      describeSnapshot(_snapshot),
      timestamp: _snapshot.timestamp,
    );
    await notifier.updateBadge(_snapshot.status);

    if (previous != LocationStateStatus.outer &&
        _snapshot.status == LocationStateStatus.outer) {
      await _handleOuterTransition();
    } else if (previous == LocationStateStatus.outer &&
        _snapshot.status != LocationStateStatus.outer) {
      await _handleRecoveryFromOuter();
    }
  }

  /// OUTER状態への遷移を処理します。
  Future<void> _handleOuterTransition() async {
    await notifier.notifyOuter();
    _logWarning(
      'ALERT',
      'Safe zone exited.${_buildNavHint(_snapshot)}',
      timestamp: _snapshot.timestamp,
    );
  }

  /// OUTER状態からの復帰を処理します。
  Future<void> _handleRecoveryFromOuter() async {
    await notifier.notifyRecover();
    _logInfo(
      'ALERT',
      'Returned to safe zone.',
      timestamp: _snapshot.timestamp,
    );
  }

  @visibleForTesting
  void debugSeed({
    AppConfig? config,
    GeoModel? geoJson,
    AreaIndex? areaIndex,
    bool? developerMode,
    StateSnapshot? snapshot,
  }) {
    if (config != null) {
      _config = config;
      stateMachine.updateConfig(config);
    }

    if (geoJson != null) {
      _geoModel = geoJson;
    }

    if (areaIndex != null) {
      _areaIndex = areaIndex;
    } else if (geoJson != null) {
      _areaIndex = AreaIndex.build(geoJson.polygons);
    }

    if (geoJson != null || areaIndex != null) {
      stateMachine.updateGeometry(_geoModel, _areaIndex);
      _snapshot = _snapshot.copyWith(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.now(),
        geoJsonLoaded: geoJsonLoaded,
      );
    } else if (config != null) {
      _snapshot = _snapshot.copyWith(
        timestamp: DateTime.now(),
        geoJsonLoaded: geoJsonLoaded,
      );
    }

    if (developerMode != null) {
      _developerMode = developerMode;
    }

    if (snapshot != null) {
      _snapshot = snapshot;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // dispose()は同期メソッドなので、非同期処理は実行しない
    // アプリ終了時のクリーンアップはmain.dartのWidgetsBindingObserverで処理
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
