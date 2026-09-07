import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
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
typedef AppNowProvider = DateTime Function();

/// 監視の経過時間を返す単調増加クロック。
///
/// 壁時計（`AppNowProvider`）はNTP補正・タイムゾーン変更・手動変更で前後に飛ぶため、
/// 「GPSが何秒来ていないか」「エリア外が何秒続いたか」の判定には使えない。
/// 監視の継続時間に関わる判定はすべてこちらを使う。
typedef AppElapsedProvider = Duration Function();

/// プロセス起動からの単調増加時間。既定の [AppElapsedProvider]。
final Stopwatch _processStopwatch = Stopwatch()..start();

Duration _processElapsed() => _processStopwatch.elapsed;

const double minRequiredAlarmVolumePercent = 0.5;

enum MonitoringLifecycle {
  idle,
  starting,
  acquiring,
  active,
  stale,
  reconnecting,
  stopping,
  failed,
}

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
    AlarmVolumeClient? alarmVolumeClient,
    bool? isAndroid,
    AppNowProvider? nowProvider,
    AppElapsedProvider? elapsedProvider,
    Duration? staleTimeoutOverride,
    Duration watchdogInterval = const Duration(seconds: 1),
    int maxReconnectFailures = 5,
    List<Duration> reconnectDelays = const <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
  })  : permissionCoordinator =
            permissionCoordinator ?? PermissionCoordinator(),
        _qrImageAnalyzer = qrImageAnalyzer ?? _defaultQrImageAnalyzer,
        alarmVolumeClient =
            alarmVolumeClient ?? const MethodChannelAlarmClient(),
        _isAndroidOverride = isAndroid,
        _now = nowProvider ?? DateTime.now,
        _elapsed = elapsedProvider ?? _processElapsed,
        _staleTimeoutOverride = staleTimeoutOverride,
        _watchdogInterval = watchdogInterval,
        _maxReconnectFailures = maxReconnectFailures,
        _reconnectDelays = List<Duration>.unmodifiable(reconnectDelays) {
    assert(watchdogInterval > Duration.zero);
    assert(maxReconnectFailures > 0);
    assert(reconnectDelays.isNotEmpty);
    assert(reconnectDelays.every((delay) => delay > Duration.zero));
  }

  final PermissionCoordinator permissionCoordinator;
  final QrImageAnalyzer _qrImageAnalyzer;
  final AlarmVolumeClient alarmVolumeClient;
  final bool? _isAndroidOverride;
  final AppNowProvider _now;
  final AppElapsedProvider _elapsed;
  final Duration? _staleTimeoutOverride;
  final Duration _watchdogInterval;
  final int _maxReconnectFailures;
  final List<Duration> _reconnectDelays;

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
  Timer? _locationWatchdogTimer;
  Timer? _reconnectTimer;

  /// 監視セッション開始時点の単調クロック値。
  ///
  /// 位置サービスは再接続で stop/start を繰り返すため、経過時間を位置サービス側で
  /// 計測するとヒステリシスの基準時刻が再接続ごとに巻き戻り、OUTER 確定が
  /// 無期限に遅延する。監視セッションを所有する側で1本だけ持つ。
  Duration? _monitoringStartedElapsed;

  /// 直近のfixを受け取った時点の監視セッション経過時間。
  Duration? _lastFixElapsed;
  MonitoringLifecycle _monitoringLifecycle = MonitoringLifecycle.idle;
  int _reconnectAttempt = 0;
  bool _reconnectInProgress = false;

  /// 連続して位置サービスの再開に失敗した回数。fix受信・再開成功でリセットする。
  ///
  /// 「再開できない」（権限失効・サービス無効）と「再開できたがfixが来ない」
  /// （トンネル・森林）は別物。後者は待ち続けるべきなので、失敗のみ数える。
  int _reconnectFailureCount = 0;

  /// 自動再接続を打ち切ったか。打ち切り後はアプリ復帰時にのみ再試行する。
  bool _locationRecoveryAbandoned = false;
  bool _monitoringStaleWarningActive = false;
  int _monitoringHealthGeneration = 0;
  int _locationFixSequence = 0;
  Future<void> _fixProcessingQueue = Future<void>.value();
  Future<void> _locationServiceOperationQueue = Future<void>.value();
  bool _isAlarmSnoozed = false;
  int _monitoringRunId = 0;
  bool _isDisposed = false;
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
  bool get isAlarmPreviewPlaying => notifier.isAlarmPreviewPlaying;
  bool get canPreviewAlarm =>
      !isMonitoringSession && _snapshot.status != LocationStateStatus.outer;
  MonitoringLifecycle get monitoringLifecycle => _monitoringLifecycle;
  bool get isMonitoringSession => switch (_monitoringLifecycle) {
        MonitoringLifecycle.starting ||
        MonitoringLifecycle.acquiring ||
        MonitoringLifecycle.active ||
        MonitoringLifecycle.stale ||
        MonitoringLifecycle.reconnecting ||
        MonitoringLifecycle.stopping =>
          true,
        MonitoringLifecycle.idle || MonitoringLifecycle.failed => false,
      };
  bool get canModifyConfiguration => !isMonitoringSession;
  MonitoringPermissionState get monitoringPermissionState =>
      _monitoringPermissionState;
  bool get _isAndroid => _isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);
  bool get canStartMonitoring =>
      geoJsonLoaded &&
      _monitoringPermissionState.canStartMonitoring &&
      (_monitoringLifecycle == MonitoringLifecycle.idle ||
          _monitoringLifecycle == MonitoringLifecycle.failed);
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
    _config ??= (await fileManager.readConfig()).normalized();
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
    if (!geoJsonLoaded ||
        (_monitoringLifecycle != MonitoringLifecycle.idle &&
            _monitoringLifecycle != MonitoringLifecycle.failed)) {
      return;
    }
    final startAttemptId = ++_monitoringRunId;
    _monitoringLifecycle = MonitoringLifecycle.starting;
    _lastErrorMessage = null;
    notifyListeners();

    if (isAlarmPreviewPlaying) {
      try {
        await stopAlarmPreview();
      } catch (error) {
        if (_isCurrentStartAttempt(startAttemptId)) {
          _monitoringLifecycle = MonitoringLifecycle.failed;
          _lastErrorMessage = '警告音テストを停止できないため、監視を開始できませんでした。';
          _logError('ALERT', 'Failed to stop alarm preview: $error');
          notifyListeners();
        }
        return;
      }
    }
    if (!_isCurrentStartAttempt(startAttemptId)) {
      return;
    }
    if (_config == null || !geoJsonLoaded) {
      _monitoringLifecycle = MonitoringLifecycle.failed;
      _lastErrorMessage = 'GeoJSONと設定を確認してください。';
      notifyListeners();
      return;
    }
    try {
      _monitoringPermissionState =
          await permissionCoordinator.refreshMonitoringPermissionState();
    } catch (error) {
      if (_isCurrentStartAttempt(startAttemptId)) {
        _monitoringLifecycle = MonitoringLifecycle.failed;
        _lastErrorMessage = '位置情報の権限状態を確認できないため、監視を開始できませんでした。';
        _logError('APP', 'Failed to refresh monitoring permissions: $error');
        notifyListeners();
      }
      return;
    }
    if (!_isCurrentStartAttempt(startAttemptId)) {
      return;
    }
    if (!_monitoringPermissionState.canStartMonitoring) {
      _monitoringLifecycle = MonitoringLifecycle.failed;
      _lastErrorMessage = _monitoringPermissionState.monitoringBlockedMessage;
      _logWarning('APP', _lastErrorMessage!);
      notifyListeners();
      return;
    }

    stateMachine.resetMonitoring();
    try {
      await _subscription?.cancel();
    } catch (error) {
      _logWarning('GPS', 'Failed to cancel previous location stream: $error');
    } finally {
      _subscription = null;
    }
    if (!_isCurrentStartAttempt(startAttemptId)) {
      return;
    }
    final runId = startAttemptId;
    _subscription = locationService.stream.listen(
      (fix) => _onLocationFix(fix, runId),
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_handleLocationStreamError(error, runId));
      },
    );
    _fixProcessingQueue = Future<void>.value();
    _monitoringStartedElapsed = _elapsed();
    _lastFixElapsed = Duration.zero;
    _reconnectAttempt = 0;
    _reconnectInProgress = false;
    _reconnectFailureCount = 0;
    _locationRecoveryAbandoned = false;
    _monitoringLifecycle = MonitoringLifecycle.acquiring;
    notifyListeners();

    LocationServiceStartResult result;
    try {
      result = await _runLocationServiceOperation(
        () => locationService.start(_config!),
      );
    } catch (error) {
      result = LocationServiceStartResult(
        status: LocationServiceStartStatus.error,
        message: error.toString(),
      );
    }
    if (!_isCurrentMonitoringRun(runId)) {
      return;
    }
    if (result.status != LocationServiceStartStatus.started) {
      _monitoringRunId += 1;
      _cancelLocationRecovery();
      try {
        await _subscription?.cancel();
      } catch (error) {
        _logWarning('GPS', 'Failed to cancel failed location stream: $error');
      } finally {
        _subscription = null;
      }
      try {
        await _runLocationServiceOperation(locationService.stop);
      } catch (error) {
        _logWarning('GPS', 'Failed to clean up location start: $error');
      }
      _monitoringLifecycle = MonitoringLifecycle.failed;
      _lastErrorMessage = result.message ?? '位置情報の監視を開始できませんでした。';
      _logError('APP', _lastErrorMessage!);
      notifyListeners();
      return;
    }

    if (_monitoringLifecycle != MonitoringLifecycle.active) {
      _lastFixElapsed = _monitoringElapsed();
      _monitoringLifecycle = MonitoringLifecycle.acquiring;
    }
    _startLocationWatchdog(runId);
    _lastErrorMessage = null;
    _logInfo('APP', 'Monitoring started.');
    notifyListeners();
  }

  Future<bool> canStartWithCurrentAlarmVolume() async {
    if (!_isAndroid) {
      return true;
    }

    try {
      final volumeState = await alarmVolumeClient.getAlarmVolumeState();
      return volumeState.percent >= minRequiredAlarmVolumePercent;
    } catch (error) {
      _logWarning('APP', 'Failed to check alarm volume: $error');
      return true;
    }
  }

  Future<bool> openAlarmSoundSettings() async {
    try {
      return await alarmVolumeClient.openSoundSettings();
    } catch (error) {
      _logWarning('APP', 'Failed to open sound settings: $error');
      return false;
    }
  }

  Future<bool> startAlarmPreview(double volume) async {
    if (!canPreviewAlarm) {
      return false;
    }

    try {
      notifier.setAlarmVolume(volume);
      await notifier.startAlarmPreview();
      _logInfo('ALERT', 'Alarm preview started.');
      notifyListeners();
      return notifier.isAlarmPreviewPlaying;
    } catch (error) {
      notifier.setAlarmVolume(
        _config?.alarmVolume ?? AppConfig.defaultAlarmVolume,
      );
      _logWarning('ALERT', 'Failed to start alarm preview: $error');
      notifyListeners();
      return false;
    }
  }

  Future<void> stopAlarmPreview() async {
    final wasPlaying = notifier.isAlarmPreviewPlaying;
    await notifier.stopAlarmPreview();
    notifier.setAlarmVolume(
      _config?.alarmVolume ?? AppConfig.defaultAlarmVolume,
    );
    if (wasPlaying) {
      _logInfo('ALERT', 'Alarm preview stopped.');
    }
    notifyListeners();
  }

  /// 位置情報の監視を停止します。
  Future<void> stopMonitoring() async {
    if (!isMonitoringSession && _subscription == null) {
      return;
    }
    _monitoringLifecycle = MonitoringLifecycle.stopping;
    notifyListeners();
    _monitoringRunId += 1;
    _cancelLocationRecovery();
    _clearAlarmSnooze();
    try {
      await notifier.dismissOuterAlert();
    } catch (error) {
      _logWarning('ALERT', 'Failed to dismiss alert while stopping: $error');
    }
    _reportUnstoppedAlert();
    try {
      await notifier.clearMonitoringStale();
    } catch (error) {
      _logWarning(
        'ALERT',
        'Failed to clear GPS warning while stopping: $error',
      );
    }
    try {
      await _subscription?.cancel();
    } catch (error) {
      _logWarning('GPS', 'Failed to cancel location stream cleanly: $error');
    } finally {
      _subscription = null;
    }
    try {
      await _runLocationServiceOperation(locationService.stop);
    } catch (error) {
      _logWarning('GPS', 'Failed to stop location service cleanly: $error');
    }
    stateMachine.updateGeometry(_geoModel, _areaIndex);
    _snapshot = StateSnapshot(
      status: geoJsonLoaded
          ? LocationStateStatus.waitStart
          : LocationStateStatus.waitGeoJson,
      timestamp: DateTime.now(),
      geoJsonLoaded: geoJsonLoaded,
      notes: geoJsonLoaded
          ? 'Monitoring stopped. Ready to restart.'
          : 'Monitoring stopped. Load GeoJSON to start monitoring.',
    );
    _monitoringLifecycle = MonitoringLifecycle.idle;
    _logInfo('APP', 'Monitoring stopped.');
    notifyListeners();
  }

  Future<void> handleAppTermination() async {
    _monitoringRunId += 1;
    _cancelLocationRecovery();
    _monitoringLifecycle = MonitoringLifecycle.stopping;
    _clearAlarmSnooze();
    if (isAlarmPreviewPlaying) {
      try {
        await stopAlarmPreview();
      } catch (error) {
        _logWarning('ALERT', 'Failed to stop preview on termination: $error');
      }
    }
    try {
      await notifier.dismissOuterAlert();
    } catch (error) {
      _logWarning('ALERT', 'Failed to dismiss alert on termination: $error');
    }
    _reportUnstoppedAlert();
    try {
      await notifier.clearMonitoringStale();
    } catch (error) {
      _logWarning(
          'ALERT', 'Failed to clear GPS warning on termination: $error');
    }
    try {
      await _subscription?.cancel();
    } catch (error) {
      _logWarning('GPS', 'Failed to cancel location stream: $error');
    } finally {
      _subscription = null;
    }
    try {
      await _runLocationServiceOperation(locationService.stop);
    } catch (error) {
      _logWarning(
          'GPS', 'Failed to stop location service on termination: $error');
    }
    await cleanupTempGeoJsonFile();
    _monitoringLifecycle = MonitoringLifecycle.idle;
    _logInfo('APP', 'Application terminated. Monitoring and alert stopped.');
  }

  Future<void> handleAppResumed() async {
    try {
      await refreshMonitoringPermissionState();
    } catch (error) {
      _logWarning('APP', 'Failed to refresh permissions on resume: $error');
    }
    if ((_monitoringLifecycle == MonitoringLifecycle.stale ||
            _monitoringLifecycle == MonitoringLifecycle.reconnecting) &&
        _reconnectTimer == null &&
        !_reconnectInProgress) {
      // 打ち切り後の復帰契機。利用者が設定で権限を直して戻ってきた可能性が
      // あるので、レジューム時だけは打ち切りを解除して再試行する。
      _locationRecoveryAbandoned = false;
      _reconnectFailureCount = 0;
      _scheduleLocationReconnect(_monitoringRunId);
    }
    if (_snapshot.status != LocationStateStatus.outer || _isAlarmSnoozed) {
      return;
    }
    try {
      await notifier.reassertAlarm();
      _logInfo('ALERT', 'Alarm playback reasserted after app resume.');
    } catch (error) {
      _logWarning('ALERT', 'Failed to reassert alarm after app resume: $error');
    }
  }

  /// 開発者モードの有効/無効を切り替えます。
  ///
  /// 開発者モードが有効な場合、UIに詳細な状態情報が表示されます。
  /// 監視中も変更できる。表示の切り替えだけで監視の挙動には影響しないため、
  /// 設定ロックの対象にしない。GPSが不調なときこそログと詳細を見たいので、
  /// ロックすると原因調査のために監視を止めさせることになる。
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
  /// 監視中は設定を変更せず、停止後の変更を求めます。
  Future<void> updateConfig(AppConfig newConfig) async {
    if (_config == null) {
      return;
    }
    if (!canModifyConfiguration) {
      _rejectConfigurationChange();
      return;
    }

    // 設定を更新
    final normalizedConfig = newConfig.normalized();
    _config = normalizedConfig;
    stateMachine.updateConfig(normalizedConfig);

    // アラーム音量を設定
    notifier.setAlarmVolume(normalizedConfig.alarmVolume);

    // 設定をファイルに保存
    await fileManager.saveConfig(normalizedConfig);

    _logInfo(
      'APP',
      'Config updated: innerBuffer=${normalizedConfig.innerBufferM}m, '
          'polling=${normalizedConfig.effectiveFastSampleIntervalS}s, '
          'gpsThreshold=${normalizedConfig.gpsAccuracyBadMeters}m',
    );

    notifyListeners();
  }

  /// ファイルピッカーからGeoJSONファイルを読み込みます。
  ///
  /// ファイルが正常に読み込まれた場合、状態マシンとエリアインデックスを更新します。
  /// エラーが発生した場合は、エラーメッセージを設定します。
  Future<void> reloadGeoJsonFromPicker() async {
    if (!canModifyConfiguration) {
      _rejectConfigurationChange();
      return;
    }

    try {
      // ファイル名を取得するために、file_selectorを直接使用
      final file = await fileManager.pickGeoJsonFile();
      if (file == null) {
        // キャンセル時は何もしない（ログも出さない）
        return;
      }

      final sourceBytes = await file.length();
      if (sourceBytes > GeoJsonLimits.defaults.maxSourceBytes) {
        throw FormatException(
          'GeoJSONのサイズが上限（${GeoJsonLimits.defaults.maxSourceBytes} bytes）を超えています。',
        );
      }
      final raw = await file.readAsString();
      final model = GeoModel.fromGeoJson(raw);
      _requireMonitorableGeometry(model);

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
    if (!canModifyConfiguration) {
      _rejectConfigurationChange();
      return false;
    }

    try {
      // QRテキストが対応スキームで始まることを確認
      if (!isSupportedGeoJsonQrText(qrText)) {
        _lastErrorMessage =
            'Invalid QR code format. Expected gjz1: or agz1: scheme.';
        _logError('APP', _lastErrorMessage!);
        notifyListeners();
        return false;
      }

      // QRテキストからGeoJSONを復元
      final decoded = await compute(_decodeGeoJsonQrText, qrText);
      final restoredGeoJson = decoded.geoJson;
      final model = GeoModel.fromGeoJson(restoredGeoJson);
      _requireMonitorableGeometry(model);

      // 一時ディレクトリに保存
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/temp_geojson_$timestamp.geojson');
      await tempFile.writeAsString(restoredGeoJson);

      // 既存の一時ファイルがあれば削除
      await cleanupTempGeoJsonFile();

      // 新しい一時ファイルパスを保存
      _tempGeoJsonFilePath = tempFile.path;

      _geoModel = model;
      _geoJsonFileName = decoded.fileName ?? 'temp_geojson_$timestamp.geojson';
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
    if (!canModifyConfiguration) {
      _rejectConfigurationChange();
      return false;
    }

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

      return await reloadGeoJsonFromQr(qrText);
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
        // coverage:ignore-start
        // File.delete failures depend on the host filesystem and permissions.
        _logError('APP', 'Failed to delete temporary GeoJSON file: $e');
        // coverage:ignore-end
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

  bool _isCurrentMonitoringRun(int runId) {
    return _subscription != null && runId == _monitoringRunId;
  }

  bool _isCurrentStartAttempt(int attemptId) {
    return attemptId == _monitoringRunId &&
        _monitoringLifecycle == MonitoringLifecycle.starting;
  }

  /// 監視開始からの単調増加経過時間。監視中でなければ [Duration.zero]。
  Duration _monitoringElapsed() {
    final startedAt = _monitoringStartedElapsed;
    if (startedAt == null) {
      return Duration.zero;
    }
    final elapsed = _elapsed() - startedAt;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration get _locationStaleTimeout {
    final override = _staleTimeoutOverride;
    if (override != null) {
      return override;
    }
    final sampleSeconds = _config?.effectiveFastSampleIntervalS ??
        AppConfig.defaultFastSampleIntervalS;
    final basedOnSampling = Duration(seconds: sampleSeconds * 3);
    const minimum = Duration(seconds: 15);
    return basedOnSampling > minimum ? basedOnSampling : minimum;
  }

  void _startLocationWatchdog(int runId) {
    _locationWatchdogTimer?.cancel();
    _locationWatchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      if (!_isCurrentMonitoringRun(runId)) {
        return;
      }
      if (_monitoringLifecycle != MonitoringLifecycle.acquiring &&
          _monitoringLifecycle != MonitoringLifecycle.active) {
        return;
      }
      final lastFix = _lastFixElapsed;
      if (lastFix != null &&
          _monitoringElapsed() - lastFix >= _locationStaleTimeout) {
        unawaited(_markLocationStale(runId, reason: 'GPS fix timeout'));
      }
    });
  }

  void _onLocationFix(LocationFix fix, int runId) {
    if (!_isCurrentMonitoringRun(runId)) {
      return;
    }
    final sessionElapsed = _monitoringElapsed();
    final stampedFix = fix.withMonitoringElapsed(sessionElapsed);
    final shouldClearStaleWarning = _monitoringStaleWarningActive;
    _locationFixSequence += 1;
    _lastFixElapsed = sessionElapsed;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _reconnectFailureCount = 0;
    _locationRecoveryAbandoned = false;
    _monitoringLifecycle = MonitoringLifecycle.active;
    if (shouldClearStaleWarning) {
      _monitoringStaleWarningActive = false;
      final healthGeneration = ++_monitoringHealthGeneration;
      unawaited(
        _clearMonitoringStaleWarning(runId, healthGeneration),
      );
    }
    notifyListeners();

    _fixProcessingQueue = _fixProcessingQueue.then((_) async {
      await _handleFix(stampedFix, runId);
    }).catchError((Object error, StackTrace stackTrace) {
      if (_isCurrentMonitoringRun(runId)) {
        _logError('GPS', 'Failed to process location fix: $error');
        notifyListeners();
      }
    });
  }

  Future<void> _clearMonitoringStaleWarning(
    int runId,
    int healthGeneration,
  ) async {
    try {
      await notifier.clearMonitoringStale();
      if (_isCurrentMonitoringRun(runId) &&
          healthGeneration == _monitoringHealthGeneration &&
          !_monitoringStaleWarningActive) {
        _logInfo('GPS', 'Location updates recovered.');
      }
    } catch (error) {
      if (_isCurrentMonitoringRun(runId)) {
        _logWarning('ALERT', 'Failed to clear GPS warning: $error');
      }
    }
  }

  Future<void> _handleLocationStreamError(Object error, int runId) async {
    if (!_isCurrentMonitoringRun(runId)) {
      return;
    }
    await _markLocationStale(runId, reason: error.toString());
  }

  Future<void> _markLocationStale(
    int runId, {
    required String reason,
  }) async {
    if (!_isCurrentMonitoringRun(runId)) {
      return;
    }
    final alreadyRecovering =
        _monitoringLifecycle == MonitoringLifecycle.stale ||
            _monitoringLifecycle == MonitoringLifecycle.reconnecting;
    if (!alreadyRecovering) {
      _monitoringLifecycle = MonitoringLifecycle.stale;
      _monitoringStaleWarningActive = true;
      final healthGeneration = ++_monitoringHealthGeneration;
      _logWarning('GPS', 'Location updates stopped: $reason.');
      notifyListeners();
      _scheduleLocationReconnect(runId);
      unawaited(
        _showMonitoringStaleWarning(runId, healthGeneration),
      );
    }
    if (_isCurrentMonitoringRun(runId) &&
        _reconnectTimer == null &&
        !_reconnectInProgress) {
      _scheduleLocationReconnect(runId);
    }
  }

  Future<void> _showMonitoringStaleWarning(
    int runId,
    int healthGeneration,
  ) async {
    try {
      await notifier.notifyMonitoringStale();
    } catch (error) {
      if (_isCurrentMonitoringRun(runId) &&
          healthGeneration == _monitoringHealthGeneration &&
          _monitoringStaleWarningActive) {
        _logWarning('ALERT', 'Failed to show GPS warning: $error');
      }
    }
  }

  void _scheduleLocationReconnect(int runId) {
    if (!_isCurrentMonitoringRun(runId) ||
        _locationRecoveryAbandoned ||
        _reconnectTimer != null ||
        _reconnectInProgress) {
      return;
    }
    final delayIndex = _reconnectAttempt < _reconnectDelays.length
        ? _reconnectAttempt
        : _reconnectDelays.length - 1;
    final delay = _reconnectDelays[delayIndex];
    _reconnectAttempt += 1;
    _monitoringLifecycle = MonitoringLifecycle.reconnecting;
    _logInfo(
      'GPS',
      'Scheduling location reconnect attempt $_reconnectAttempt '
          'in ${delay.inMilliseconds}ms.',
    );
    notifyListeners();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_reconnectLocation(runId));
    });
  }

  /// 自動再接続を打ち切り、原因を利用者に伝えます。
  ///
  /// 監視セッションは維持する（`stale` のまま）。`failed` にすると
  /// `isMonitoringSession` が false になり、警報が鳴っている最中に設定ロックと
  /// 強制終了警告が外れてしまう。復帰はアプリのレジュームを契機にする。
  void _abandonLocationRecovery(
    int runId, {
    required String reason,
    required String userMessage,
  }) {
    _locationRecoveryAbandoned = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _monitoringLifecycle = MonitoringLifecycle.stale;
    _lastErrorMessage = userMessage;
    _logError('GPS', 'Location recovery abandoned: $reason');
    notifyListeners();
  }

  Future<void> _reconnectLocation(int runId) async {
    if (!_isCurrentMonitoringRun(runId) || _reconnectInProgress) {
      return;
    }
    _reconnectInProgress = true;
    _monitoringLifecycle = MonitoringLifecycle.reconnecting;
    notifyListeners();
    try {
      final config = _config;
      if (config == null) {
        throw StateError('Configuration is unavailable.');
      }
      // 位置情報が来なくなる最も多い原因は権限の失効。再確認しないと、
      // 直せない状態のまま30秒間隔で無音の再試行を続けることになる。
      try {
        final permissionState =
            await permissionCoordinator.refreshMonitoringPermissionState();
        if (!_isCurrentMonitoringRun(runId)) {
          return;
        }
        _monitoringPermissionState = permissionState;
        if (!permissionState.canStartMonitoring) {
          _abandonLocationRecovery(
            runId,
            reason: 'monitoring permission is no longer granted',
            userMessage: permissionState.monitoringBlockedMessage,
          );
          return;
        }
      } catch (error) {
        // 権限を確認できないだけでは打ち切らない。再開を試す。
        _logWarning(
          'APP',
          'Failed to refresh permissions during reconnect: $error',
        );
      }
      if (!_isCurrentMonitoringRun(runId)) {
        return;
      }
      final fixSequenceBeforeStart = _locationFixSequence;
      final result = await _runLocationServiceOperation(() async {
        await locationService.stop();
        if (!_isCurrentMonitoringRun(runId)) {
          return null;
        }
        return locationService.start(config);
      });
      if (result == null) {
        return;
      }
      if (!_isCurrentMonitoringRun(runId)) {
        return;
      }
      if (result.status != LocationServiceStartStatus.started) {
        throw StateError(result.message ?? 'Location service restart failed.');
      }
      // 再開できた。以降fixが来ないのはGPSの受信環境の問題なので、
      // 失敗としては数えず待ち続ける。
      _reconnectFailureCount = 0;
      final fixArrivedDuringStart =
          _locationFixSequence != fixSequenceBeforeStart;
      if (fixArrivedDuringStart ||
          _monitoringLifecycle == MonitoringLifecycle.active) {
        _monitoringLifecycle = MonitoringLifecycle.active;
        _logInfo('GPS', 'Location service reconnected with a fresh fix.');
      } else if (_monitoringLifecycle != MonitoringLifecycle.stale) {
        _lastFixElapsed = _monitoringElapsed();
        _monitoringLifecycle = MonitoringLifecycle.acquiring;
        _logInfo('GPS', 'Location service reconnected; waiting for a fix.');
      }
      notifyListeners();
    } catch (error) {
      if (_isCurrentMonitoringRun(runId)) {
        _reconnectFailureCount += 1;
        _monitoringLifecycle = MonitoringLifecycle.stale;
        _logWarning(
          'GPS',
          'Location reconnect failed '
              '($_reconnectFailureCount/$_maxReconnectFailures): $error',
        );
        if (_reconnectFailureCount >= _maxReconnectFailures) {
          _abandonLocationRecovery(
            runId,
            reason: 'location service restart failed '
                '$_reconnectFailureCount times: $error',
            userMessage: '位置情報の監視を再開できません。'
                '端末の位置情報サービスと権限を確認してください。',
          );
        } else {
          notifyListeners();
        }
      }
    } finally {
      _reconnectInProgress = false;
    }
    if (_isCurrentMonitoringRun(runId) &&
        _monitoringLifecycle == MonitoringLifecycle.stale) {
      _scheduleLocationReconnect(runId);
    }
  }

  void _cancelLocationRecovery() {
    _monitoringStartedElapsed = null;
    _locationWatchdogTimer?.cancel();
    _locationWatchdogTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _lastFixElapsed = null;
    _reconnectAttempt = 0;
    _reconnectInProgress = false;
    _reconnectFailureCount = 0;
    _locationRecoveryAbandoned = false;
    _monitoringStaleWarningActive = false;
    _monitoringHealthGeneration += 1;
  }

  Future<T> _runLocationServiceOperation<T>(
    Future<T> Function() operation,
  ) {
    final result = _locationServiceOperationQueue.then<T>(
      (_) => operation(),
    );
    _locationServiceOperationQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  /// 警報の停止に失敗して鳴り続けている可能性があれば利用者に伝えます。
  ///
  /// 停止失敗をログだけに残すと、警報が鳴り続けているのに画面には何も出ず、
  /// 利用者は原因も対処も分からないまま強制終了するしかなくなる。
  bool _reportUnstoppedAlert() {
    if (!notifier.hasActiveAlertPlayback) {
      return false;
    }
    _lastErrorMessage = '警報を停止できませんでした。'
        '音やバイブが続く場合は端末の音量を下げ、アプリを再起動してください。';
    _logError('ALERT', 'Alert playback could not be stopped.');
    return true;
  }

  void _rejectConfigurationChange() {
    _lastErrorMessage = '監視中は設定やGeoJSONを変更できません。先に監視を停止してください。';
    _logWarning('APP', _lastErrorMessage!);
    notifyListeners();
  }

  Future<void> _handleFix(LocationFix fix, int runId) async {
    if (!_isCurrentMonitoringRun(runId)) {
      return;
    }

    final previous = _snapshot.status;
    await logger.logLocationFix(fix);
    if (!_isCurrentMonitoringRun(runId)) {
      return;
    }

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
    if (!_isCurrentMonitoringRun(runId)) {
      return;
    }

    _logInfo(
      'STATE',
      describeSnapshot(_snapshot),
      timestamp: _snapshot.timestamp,
    );
    await notifier.updateBadge(_snapshot.status);
    if (!_isCurrentMonitoringRun(runId)) {
      return;
    }

    if (previous != LocationStateStatus.outer &&
        _snapshot.status == LocationStateStatus.outer) {
      final delivery = await notifier.notifyOuter();
      if (!_isCurrentMonitoringRun(runId)) {
        return;
      }
      if (delivery.hasFailures) {
        _logWarning(
          'ALERT',
          'One or more alert channels failed: ${delivery.failureSummary}',
          timestamp: _snapshot.timestamp,
        );
      }
      _logWarning(
        'ALERT',
        'Safe zone exited.${_buildNavHint(_snapshot)}',
        timestamp: _snapshot.timestamp,
      );
    } else if (previous == LocationStateStatus.outer &&
        _snapshot.status != LocationStateStatus.outer) {
      _clearAlarmSnooze();
      try {
        await notifier.notifyRecover();
      } catch (error) {
        _logWarning('ALERT', 'Failed to dismiss alert on re-entry: $error');
      }
      if (!_isCurrentMonitoringRun(runId)) {
        return;
      }
      _reportUnstoppedAlert();
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
    try {
      await notifier.stopAlarm();
    } catch (error) {
      _logWarning('ALERT', 'Failed to stop alarm for snooze: $error');
    }
    // 実際に止まっていないのに「ミュート中」と表示すると、鳴り続けている
    // 理由を利用者が誤解する。ミュート状態に入らず、停止失敗として伝える。
    if (_reportUnstoppedAlert()) {
      _isAlarmSnoozed = false;
      notifyListeners();
      return;
    }
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
    try {
      await notifier.resumeAlarm();
      _logWarning(
        'ALERT',
        'Alarm resumed after snooze.${_buildNavHint(_snapshot)}',
        timestamp: _now(),
      );
    } catch (error) {
      _logWarning('ALERT', 'Failed to resume alarm after snooze: $error');
    }
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
    MonitoringLifecycle? monitoringLifecycle,
    bool clearConfig = false,
  }) {
    if (clearConfig) {
      _config = null;
    }
    if (config != null) {
      _config = config.normalized();
      stateMachine.updateConfig(_config!);
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
      _monitoringLifecycle = monitoringLifecycle ??
          switch (snapshot.status) {
            LocationStateStatus.inner ||
            LocationStateStatus.near ||
            LocationStateStatus.outerPending ||
            LocationStateStatus.outer ||
            LocationStateStatus.gpsBad =>
              MonitoringLifecycle.active,
            LocationStateStatus.waitGeoJson ||
            LocationStateStatus.waitStart =>
              MonitoringLifecycle.idle,
          };
    } else if (monitoringLifecycle != null) {
      _monitoringLifecycle = monitoringLifecycle;
    }

    if (permissionState != null) {
      _monitoringPermissionState = permissionState;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cancelLocationRecovery();
    _clearAlarmSnooze();
    _subscription?.cancel();
    // dispose()は同期メソッドなので、非同期処理は実行しない
    // アプリ終了時のクリーンアップはmain.dartのWidgetsBindingObserverで処理
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  void _addLogEntry(AppLogEntry entry) {
    _logs.insert(0, entry);
    if (_logs.length > 200) {
      _logs.removeLast();
    }
  }

  // coverage:ignore-start
  static Future<AppController> bootstrap() async {
    final fileManager = FileManager();
    final config = (await fileManager.readConfig()).normalized();
    final stateMachine = StateMachine(config: config);
    final locationService = GeolocatorLocationService();
    final logger = EventLogger();
    final notificationsPlugin = FlutterLocalNotificationsPlugin();
    final notifier = Notifier(
      plugin: notificationsPlugin,
      vibrationPlayer: const NativeVibrationPlayer(),
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
  // coverage:ignore-end

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

  Future<bool> openPermissionSettings() async {
    try {
      return await permissionCoordinator.openSettings();
    } catch (error) {
      _logWarning('APP', 'Failed to open permission settings: $error');
      return false;
    }
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

void _requireMonitorableGeometry(GeoModel model) {
  if (!model.hasGeometry) {
    throw const FormatException(
      'GeoJSONに監視可能なPolygon/MultiPolygonがありません。',
    );
  }
}

Future<DecodedGeoJson> _decodeGeoJsonQrText(String qrText) {
  return decodeGeoJsonWithMetadata(
    GeoJsonQrDecodeInput(
      qrTexts: [qrText],
      verifyHash: true,
    ),
  );
}

// coverage:ignore-start
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
// coverage:ignore-end
