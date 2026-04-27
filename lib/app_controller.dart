import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import 'geo/area_index.dart';
import 'geo/geo_model.dart';
import 'io/config.dart';
import 'io/file_manager.dart';
import 'io/log_entry.dart';
import 'io/logger.dart';
import 'platform/location_service.dart';
import 'platform/notifier.dart';
import 'platform/permission_coordinator.dart';
import 'qr/geojson_qr_codec.dart';
import 'state_machine/state.dart';
import 'state_machine/state_machine.dart';

typedef QrImageAnalyzer = Future<String?> Function(String imagePath);

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
    PermissionCoordinator? permissionCoordinator,
    QrImageAnalyzer? qrImageAnalyzer,
  })  : permissionCoordinator =
            permissionCoordinator ?? PermissionCoordinator(),
        _qrImageAnalyzer = qrImageAnalyzer ?? _defaultQrImageAnalyzer;

  final PermissionCoordinator permissionCoordinator;
  final QrImageAnalyzer _qrImageAnalyzer;

  final StateMachine stateMachine;
  final LocationService locationService;
  final FileManager fileManager;
  final EventLogger logger;
  final Notifier notifier;

  AppConfig? _config;
  GeoModel _geoModel = GeoModel.empty();
  bool _developerMode = false;
  bool _navigationEnabled = true;
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
  Timer? _alarmSnoozeTimer;
  bool _isAlarmSnoozed = false;
  final List<AppLogEntry> _logs = <AppLogEntry>[];
  MonitoringPermissionState _monitoringPermissionState =
      const MonitoringPermissionState.unknown();

  StateSnapshot get snapshot => _snapshot;
  AppConfig? get config => _config;
  bool get geoJsonLoaded => _geoModel.hasGeometry;
  String? get lastErrorMessage => _lastErrorMessage;
  String? get geoJsonFileName => _geoJsonFileName;
  List<AppLogEntry> get logs => List.unmodifiable(_logs);
  bool get developerMode => _developerMode;
  bool get navigationEnabled => _navigationEnabled;
  bool get isAlarmSnoozed => _isAlarmSnoozed;
  bool get canSnoozeAlarm =>
      _snapshot.status == LocationStateStatus.outer && !_isAlarmSnoozed;
  MonitoringPermissionState get monitoringPermissionState =>
      _monitoringPermissionState;
  bool get canStartMonitoring =>
      geoJsonLoaded && _monitoringPermissionState.canStartMonitoring;
  bool get shouldShowPermissionSetupCard =>
      !_monitoringPermissionState.canStartMonitoring ||
      !_monitoringPermissionState.notificationGranted;

  /// アプリケーションを初期化します。
  ///
  /// 権限状態の確認、設定ファイルの読み込み、状態マシンの初期化を行います。
  Future<void> initialize() async {
    await notifier.initialize();
    _monitoringPermissionState =
        await permissionCoordinator.refreshMonitoringPermissionState();
    _config ??= await fileManager.readConfig();
    stateMachine.updateConfig(_config!);

    // アラーム音量を設定
    notifier.setAlarmVolume(_config!.alarmVolume);

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
    _monitoringPermissionState =
        await permissionCoordinator.refreshMonitoringPermissionState();
    if (!_monitoringPermissionState.canStartMonitoring) {
      _lastErrorMessage = _monitoringPermissionState.monitoringBlockedMessage;
      _logWarning('APP', _lastErrorMessage!);
      notifyListeners();
      return;
    }

    final result = await locationService.start(_config!);
    if (result.status != LocationServiceStartStatus.started) {
      _lastErrorMessage = result.message ?? '位置情報の監視を開始できませんでした。';
      _logError('APP', _lastErrorMessage!);
      notifyListeners();
      return;
    }

    await _subscription?.cancel();
    _subscription = locationService.stream.listen(_handleFix);
    _lastErrorMessage = null;
    _logInfo('APP', 'Monitoring started.');
    notifyListeners();
  }

  /// 位置情報の監視を停止します。
  Future<void> stopMonitoring() async {
    _clearAlarmSnooze();
    await _subscription?.cancel();
    _subscription = null;
    await locationService.stop();
    _logInfo('APP', 'Monitoring stopped.');
    notifyListeners();
  }

  Future<void> handleAppTermination() async {
    _clearAlarmSnooze();
    await _subscription?.cancel();
    _subscription = null;
    await locationService.stop();
    await notifier.dismissOuterAlert();
    await cleanupTempGeoJsonFile();
    _logInfo('APP', 'Application terminated. Monitoring and alert stopped.');
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

    // アラーム音量を設定
    notifier.setAlarmVolume(newConfig.alarmVolume);

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
      // 新しいファイルをセットしたらナビゲーション表示を一旦オフ
      _navigationEnabled = false;
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

  /// QRコードからGeoJSONを読み込みます。
  ///
  /// QRテキストからGeoJSONを復元し、一時ファイルとして保存してから
  /// 状態マシンとエリアインデックスを更新します。
  /// エラーが発生した場合は、エラーメッセージを設定します。
  Future<bool> reloadGeoJsonFromQr(String qrText) async {
    // 先に監視を停止（ファイル操作前に停止）
    await stopMonitoring();

    try {
      // QRテキストが対応スキームで始まることを確認
      if (!isSupportedGeoJsonQrText(qrText)) {
        _lastErrorMessage =
            'Invalid QR code format. Expected gjb1: or gjz1: scheme.';
        _logError('APP', _lastErrorMessage!);
        notifyListeners();
        return false;
      }

      // QRテキストからGeoJSONを復元
      final restoredGeoJson = await decodeGeoJson(
        GeoJsonQrDecodeInput(
          qrTexts: [qrText],
          verifyHash: true,
        ),
      );

      // 一時ディレクトリに保存
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/temp_geojson_$timestamp.geojson');
      await tempFile.writeAsString(restoredGeoJson);

      // 既存の一時ファイルがあれば削除
      await cleanupTempGeoJsonFile();

      // 新しい一時ファイルパスを保存
      _tempGeoJsonFilePath = tempFile.path;

      // GeoModelを生成
      final model = GeoModel.fromGeoJson(restoredGeoJson);

      _geoModel = model;
      _geoJsonFileName = 'temp_geojson_$timestamp.geojson';
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
        notes: 'GeoJSON loaded from QR code',
      );
      // 新しいファイルをセットしたらナビゲーション表示を一旦オフ
      _navigationEnabled = false;
      await notifier.stopAlarm();
      _lastErrorMessage = null;
      _logInfo('APP', 'GeoJSON loaded from QR code.',
          timestamp: _snapshot.timestamp);
      notifyListeners();
      return true;
    } on GeoJsonQrException catch (e) {
      _lastErrorMessage = 'Failed to decode QR code: ${e.message}';
      _logError('APP', _lastErrorMessage!);
      notifyListeners();
      return false;
    } on FormatException catch (e) {
      _lastErrorMessage = 'Failed to parse GeoJSON: ${e.message}';
      _logError('APP', _lastErrorMessage!);
      notifyListeners();
      return false;
    } catch (e) {
      _lastErrorMessage =
          'Unable to load GeoJSON from QR code: ${e.toString()}';
      _logError('APP', _lastErrorMessage!);
      notifyListeners();
      return false;
    }
  }

  /// QRコード画像ファイルからGeoJSONを読み込みます。
  Future<bool> reloadGeoJsonFromQrImagePicker() async {
    await stopMonitoring();

    try {
      final file = await fileManager.pickQrImageFile();
      if (file == null) {
        return false;
      }

      final qrText = await _qrImageAnalyzer(file.path);
      if (qrText == null || qrText.trim().isEmpty) {
        _lastErrorMessage = 'QRコード画像からQRコードを読み取れませんでした。';
        _logError('APP', _lastErrorMessage!);
        notifyListeners();
        return false;
      }

      return reloadGeoJsonFromQr(qrText);
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('cancel') ||
          errorMessage.contains('user') ||
          errorMessage.contains('abort')) {
        return false;
      }
      _lastErrorMessage =
          'Unable to load GeoJSON from QR image: ${e.toString()}';
      _logError('APP', _lastErrorMessage!);
      notifyListeners();
      return false;
    }
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
          _logInfo(
              'APP', 'Temporary GeoJSON file deleted: $_tempGeoJsonFilePath');
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
    // OUTERに入ったらナビゲーション表示を再有効化
    if (_snapshot.status == LocationStateStatus.outer) {
      _navigationEnabled = true;
    }
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
      _clearAlarmSnooze();
      await notifier.notifyRecover();
      _logInfo(
        'ALERT',
        'Returned to safe zone.',
        timestamp: _snapshot.timestamp,
      );
    }
    notifyListeners();
  }

  Future<void> snoozeAlarmForOneMinute() async {
    if (!canSnoozeAlarm) {
      return;
    }

    _clearAlarmSnooze();
    _isAlarmSnoozed = true;
    await notifier.stopAlarm();
    _logInfo(
      'ALERT',
      'Alarm snoozed for 1 minute.${_buildNavHint(_snapshot)}',
      timestamp: _snapshot.timestamp,
    );
    _alarmSnoozeTimer = Timer(const Duration(minutes: 1), () {
      unawaited(_resumeAlarmAfterSnooze());
    });
    notifyListeners();
  }

  Future<void> _resumeAlarmAfterSnooze() async {
    _alarmSnoozeTimer = null;
    if (!_isAlarmSnoozed || _snapshot.status != LocationStateStatus.outer) {
      return;
    }

    _isAlarmSnoozed = false;
    await notifier.resumeAlarm();
    _logWarning(
      'ALERT',
      'Alarm resumed after snooze.${_buildNavHint(_snapshot)}',
      timestamp: DateTime.now(),
    );
    notifyListeners();
  }

  void _clearAlarmSnooze() {
    _alarmSnoozeTimer?.cancel();
    _alarmSnoozeTimer = null;
    _isAlarmSnoozed = false;
  }

  @visibleForTesting
  void debugSeed({
    AppConfig? config,
    GeoModel? geoJson,
    AreaIndex? areaIndex,
    bool? developerMode,
    StateSnapshot? snapshot,
    MonitoringPermissionState? permissionState,
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

    if (permissionState != null) {
      _monitoringPermissionState = permissionState;
    }
  }

  @override
  void dispose() {
    _clearAlarmSnooze();
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

  Future<void> refreshMonitoringPermissionState() async {
    _monitoringPermissionState =
        await permissionCoordinator.refreshMonitoringPermissionState();
    notifyListeners();
  }

  Future<void> requestNotificationPermission() async {
    _monitoringPermissionState =
        await permissionCoordinator.requestNotificationPermission();
    notifyListeners();
  }

  Future<void> completeMonitoringPermissionSetup() async {
    _monitoringPermissionState =
        await permissionCoordinator.completeMonitoringSetup();
    if (_monitoringPermissionState.canStartMonitoring) {
      _lastErrorMessage = null;
      _logInfo('APP', 'Monitoring permission setup completed.');
    } else {
      _lastErrorMessage = _monitoringPermissionState.monitoringBlockedMessage;
      _logWarning('APP', _lastErrorMessage!);
    }
    notifyListeners();
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
        (_developerMode || snapshot.status == LocationStateStatus.outer) &&
            _navigationEnabled;
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

Future<String?> _defaultQrImageAnalyzer(String imagePath) async {
  final controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  try {
    final capture = await controller.analyzeImage(
      imagePath,
      formats: const [BarcodeFormat.qrCode],
    );
    for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.trim().isNotEmpty) {
        return rawValue;
      }
    }
    return null;
  } finally {
    await controller.dispose();
  }
}
