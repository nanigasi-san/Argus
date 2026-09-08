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

/// [AppController.startMonitoring] の結果。
enum MonitoringStartOutcome {
  /// 監視を開始した。
  started,

  /// 端末のアラーム音量が低すぎるため開始しなかった。
  ///
  /// 呼び出し元は音量を上げる案内を出したうえで再試行できる。
  alarmVolumeTooLow,

  /// 上記以外の理由で開始しなかった。理由は [AppController.lastErrorMessage]。
  notStarted,
}

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
    Duration staleReminderInterval = const Duration(seconds: 60),
    Duration platformCallTimeout = const Duration(seconds: 5),
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
        _staleReminderInterval = staleReminderInterval,
        _platformCallTimeout = platformCallTimeout,
        _reconnectDelays = List<Duration>.unmodifiable(reconnectDelays) {
    assert(watchdogInterval > Duration.zero);
    assert(maxReconnectFailures > 0);
    assert(staleReminderInterval > Duration.zero);
    assert(platformCallTimeout > Duration.zero);
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
  final Duration _staleReminderInterval;

  /// プラットフォームチャネル越しの呼び出しを待つ上限。
  final Duration _platformCallTimeout;
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

  /// GPS途絶警告を反復するタイマー。
  ///
  /// 1回だけ通知して終わりだと、無音通知＋350msの振動1回を見逃した時点で
  /// 監視が死んでいることに気づけなくなる。途絶が続くあいだは伝え続ける。
  Timer? _staleEscalationTimer;

  /// GPS途絶が始まった時点の監視セッション経過時間。
  Duration? _staleSinceElapsed;

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

  /// 警報の発報・停止に失敗したことを伝える警告。
  ///
  /// `lastErrorMessage` とは別に持つ。あちらはSnackbarで4秒表示して自動的に
  /// 消える経路で、「サイレントが鳴っていない」「警報が止まっていない」という
  /// 事実の伝達には向かない。ポケットに入れて走っている利用者が見るのは
  /// 数十秒後なので、明示的に閉じるまで残す必要がある。
  String? _alertReliabilityWarning;
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
    final configLoad = await fileManager.readConfig();
    _config ??= configLoad.config.normalized();
    stateMachine.updateConfig(_config!);
    if (configLoad.fallbackReason != null) {
      // 保存済みの閾値が黙って初期値へ戻るのは、利用者が「調整したつもりの
      // 設定」で走ることを意味する。起動時に必ず知らせる。
      _logError(
          'APP',
          'Saved settings were not usable: '
              '${configLoad.fallbackReason}');
      _lastErrorMessage = '保存された設定を読み込めなかったため、初期設定で起動しました。'
          '設定画面で内容を確認してください。';
    }

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

  /// 警報の発報・停止に失敗したことを伝える警告。閉じるまで残ります。
  String? get alertReliabilityWarning => _alertReliabilityWarning;

  /// 警報の信頼性に関する警告を閉じます。
  void clearAlertReliabilityWarning() {
    if (_alertReliabilityWarning != null) {
      _alertReliabilityWarning = null;
      notifyListeners();
    }
  }

  /// エラーメッセージをクリアします。
  void clearError() {
    if (_lastErrorMessage != null) {
      _lastErrorMessage = null;
      notifyListeners();
    }
  }

  /// 位置情報の監視を開始します。
  ///
  /// 開始条件（GeoJSON・設定・権限・Androidのアラーム音量）はすべてここで
  /// 判定する。呼び出し元に判定を任せると、別の入口から安全条件を迂回して
  /// 監視を始められてしまい、確認から開始までの間に音量を下げられる隙も残る。
  Future<MonitoringStartOutcome> startMonitoring() async {
    if (!geoJsonLoaded ||
        (_monitoringLifecycle != MonitoringLifecycle.idle &&
            _monitoringLifecycle != MonitoringLifecycle.failed)) {
      return MonitoringStartOutcome.notStarted;
    }
    final startAttemptId = ++_monitoringRunId;
    _monitoringLifecycle = MonitoringLifecycle.starting;
    _lastErrorMessage = null;
    notifyListeners();

    // 鳴っている音（試聴音、前回停止に失敗した警報）は監視開始前に必ず止める。
    // 止められないまま始めると、常時鳴っている音と本物のOUTER警報を
    // 区別できず、警報が意味を持たなくなる。
    //
    // 判定は「停止呼び出しが失敗したか」ではなく「実際に鳴っていないか」で行う。
    // 一過性の失敗のあと停止できたのなら、開始を妨げる理由はない。
    if (isAlarmPreviewPlaying) {
      try {
        await stopAlarmPreview();
      } catch (error) {
        _logError('ALERT', 'Failed to stop alarm preview: $error');
      }
    }
    if (notifier.hasActiveAlertPlayback) {
      try {
        await notifier.stopAlarm();
      } catch (error) {
        _logWarning('ALERT', 'Failed to stop leftover alert on start: $error');
      }
    }
    if (notifier.hasActiveAlertPlayback) {
      _reportUnstoppedAlert();
      if (_isCurrentStartAttempt(startAttemptId)) {
        _monitoringLifecycle = MonitoringLifecycle.failed;
        _lastErrorMessage = '鳴っている警報を停止できないため、監視を開始できませんでした。';
        notifyListeners();
      }
      return MonitoringStartOutcome.notStarted;
    }
    // ここまで来たら「何も鳴っていない」ことを確認できている。前セッションの
    // 発報・停止失敗の警告は現状を表していないので消す。残すと、直った警報を
    // 信用しなくなるか、常に出ている警告として無視する癖がつく。
    _alertReliabilityWarning = null;
    if (!_isCurrentStartAttempt(startAttemptId)) {
      return MonitoringStartOutcome.notStarted;
    }
    if (_config == null || !geoJsonLoaded) {
      _monitoringLifecycle = MonitoringLifecycle.failed;
      _lastErrorMessage = 'GeoJSONと設定を確認してください。';
      notifyListeners();
      return MonitoringStartOutcome.notStarted;
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
      return MonitoringStartOutcome.notStarted;
    }
    if (!_isCurrentStartAttempt(startAttemptId)) {
      return MonitoringStartOutcome.notStarted;
    }
    if (!_monitoringPermissionState.canStartMonitoring) {
      _monitoringLifecycle = MonitoringLifecycle.failed;
      _lastErrorMessage = _monitoringPermissionState.monitoringBlockedMessage;
      _logWarning('APP', _lastErrorMessage!);
      notifyListeners();
      return MonitoringStartOutcome.notStarted;
    }

    // 音量確認は開始直前に行う。呼び出し元で確認してから開始を頼む形だと、
    // その間に音量を下げられても検出できない。
    if (!await canStartWithCurrentAlarmVolume()) {
      if (_isCurrentStartAttempt(startAttemptId)) {
        // failed ではなく idle に戻す。音量が低いのは「失敗」ではなく
        // ワンタップで直せる前提条件であり、赤い「開始失敗」を残すと
        // 何か壊れたように見える。stopMonitoring は failed を解除できない。
        _monitoringLifecycle = MonitoringLifecycle.idle;
        // lastErrorMessage は立てない。この理由だけは呼び出し元が
        // 音量を上げる手段を含む専用ダイアログを出すため、文字列で重ねると
        // その案内を上書きしてしまう。戻り値が利用者向けの伝達経路になる。
        _logWarning(
          'APP',
          'Monitoring start refused: alarm volume below '
              '${(minRequiredAlarmVolumePercent * 100).round()}%.',
        );
        notifyListeners();
      }
      return MonitoringStartOutcome.alarmVolumeTooLow;
    }
    if (!_isCurrentStartAttempt(startAttemptId)) {
      return MonitoringStartOutcome.notStarted;
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
      return MonitoringStartOutcome.notStarted;
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
      ).timeout(_platformCallTimeout);
    } catch (error) {
      result = LocationServiceStartResult(
        status: LocationServiceStartStatus.error,
        message: error.toString(),
      );
    }
    if (!_isCurrentMonitoringRun(runId)) {
      return MonitoringStartOutcome.notStarted;
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
      return MonitoringStartOutcome.notStarted;
    }

    if (_monitoringLifecycle != MonitoringLifecycle.active) {
      _lastFixElapsed = _monitoringElapsed();
      _monitoringLifecycle = MonitoringLifecycle.acquiring;
    }
    _startLocationWatchdog(runId);
    _lastErrorMessage = null;
    _logInfo('APP', 'Monitoring started.');
    notifyListeners();
    return MonitoringStartOutcome.started;
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

  /// 結果を待てない場所（画面のdisposeなど）から警告音テストを止めます。
  ///
  /// 例外を投げない。dispose は同期メソッドで待てないため、投げても未処理の
  /// 非同期エラーになるだけで誰にも伝わらず、鳴りっぱなしの試聴音に気づけない。
  /// 代わりに停止できなかったことを警告として残す。
  void stopAlarmPreviewInBackground() {
    if (!isAlarmPreviewPlaying) {
      return;
    }
    unawaited(() async {
      try {
        await stopAlarmPreview();
      } catch (error) {
        _logWarning('ALERT', 'Failed to stop alarm preview on dispose: $error');
      }
      _reportUnstoppedAlert();
    }());
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
    await _guardedCleanup(
      'ALERT',
      'Dismissing alert while stopping',
      notifier.dismissOuterAlert,
    );
    _reportUnstoppedAlert();
    await _guardedCleanup(
      'ALERT',
      'Clearing GPS warning while stopping',
      notifier.clearMonitoringStale,
    );
    final subscription = _subscription;
    _subscription = null;
    await _guardedCleanup(
      'GPS',
      'Cancelling location stream while stopping',
      () async => subscription?.cancel(),
    );
    await _guardedCleanup(
      'GPS',
      'Stopping location service while stopping',
      () => _runLocationServiceOperation(locationService.stop),
    );
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
    await _guardedCleanup(
      'ALERT',
      'Dismissing alert on termination',
      notifier.dismissOuterAlert,
    );
    _reportUnstoppedAlert();
    await _guardedCleanup(
      'ALERT',
      'Clearing GPS warning on termination',
      notifier.clearMonitoringStale,
    );
    final subscription = _subscription;
    _subscription = null;
    await _guardedCleanup(
      'GPS',
      'Cancelling location stream on termination',
      () async => subscription?.cancel(),
    );
    await _guardedCleanup(
      'GPS',
      'Stopping location service on termination',
      () => _runLocationServiceOperation(locationService.stop),
    );
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
      // ただし失敗回数は 0 に戻さず「あと1回」だけ与える。0 に戻すと、
      // 競技中によくあるアプリ切り替えのたびに満額の再試行が復活し、
      // 打ち切りが実質的に効かなくなる。復帰に成功すれば fix 受信時に
      // 0 へ戻るので、本当に直った場合は通常運転に復帰できる。
      _locationRecoveryAbandoned = false;
      _reconnectFailureCount = _maxReconnectFailures - 1;
      _scheduleLocationReconnect(_monitoringRunId);
    }
    if (_snapshot.status != LocationStateStatus.outer || _isAlarmSnoozed) {
      return;
    }
    try {
      await notifier.reassertAlarm();
      _logInfo('ALERT', 'Alarm playback reasserted after app resume.');
    } catch (error) {
      // OUTERのままアプリへ戻ったのに警報を鳴らし直せなかった状態。
      // 画面はOUTER表示のままなので、伝えないと「鳴っているはず」と誤解する。
      _reportAlertFailure(
        'アプリ復帰時に警報を再開できませんでした。'
            'エリア外の警告に気づけない可能性があります。'
            '端末の音量・サイレントモードを確認してください。',
        'Failed to reassert alarm after app resume: $error',
      );
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

    final normalizedConfig = newConfig.normalized();

    // 先に永続化してから適用する。逆順だと、保存に失敗したとき画面には
    // 「設定の反映に失敗しました」と出るのに動作中の閾値はすでに変わって
    // おり、次回起動で元へ戻る。利用者は「変えたつもりの値」で走ることに
    // なるので、見えている状態と保存された状態を一致させる。
    await fileManager.saveConfig(normalizedConfig);

    // 保存を待つ間に監視が始まっていたら適用しない。監視中に閾値や
    // ヒステリシス条件が入れ替わると、状態機械の前提が途中で変わる。
    if (!canModifyConfiguration) {
      // 保存は済んでいるので「何も保存されていない」と読める文言にしない。
      _lastErrorMessage = '監視中は設定を反映できません。'
          '保存した内容は次回起動時に反映されます。';
      _logWarning('APP', _lastErrorMessage!);
      notifyListeners();
      return;
    }

    _config = normalizedConfig;
    stateMachine.updateConfig(normalizedConfig);
    notifier.setAlarmVolume(normalizedConfig.alarmVolume);

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

      // ファイル名をpathから抽出し、拡張子を.geojsonに統一
      final extractedName = _extractFileName(file.path) ?? file.name;
      _applyLoadedGeoJson(
        model,
        _normalizeToGeoJson(extractedName),
        notes: 'GeoJSON loaded',
      );
    } on FormatException catch (e) {
      _lastErrorMessage = 'Failed to parse GeoJSON: ${e.message}';
      _logError('APP', _lastErrorMessage!);
      notifyListeners();
    } catch (e) {
      // キャンセルは pickGeoJsonFile() が null を返すことで表現される。
      // 例外メッセージに 'cancel' / 'user' / 'abort' が含まれるかで
      // 判定してはいけない。Androidのアプリ専用パスは /data/user/0/... で
      // あり、そこで起きた FileSystemException が「利用者のキャンセル」と
      // 誤判定されて無言で消える。読み込めなかったことは必ず伝える。
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

      // 一時ディレクトリに保存。
      // 旧ファイルの削除は「新しいパスを記録したあと」「パスが異なる場合だけ」
      // 行う。書き込み後に旧パスで削除すると、同一ミリ秒の連続読み込みで
      // 旧パスと新パスが一致し、書いたばかりのファイルを消してしまう。
      final tempDir = await getTemporaryDirectory();
      // 注入済みクロックを使う。DateTime.now() 直呼びだと、同一ミリ秒に
      // 連続読み込みしたときのファイル名衝突をテストで再現できない。
      final timestamp = _now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/temp_geojson_$timestamp.geojson');
      final previousTempPath = _tempGeoJsonFilePath;
      try {
        await tempFile.writeAsString(restoredGeoJson, flush: true);
      } catch (error) {
        // 書き込み途中で失敗した断片を残さない。残すと誰も参照しないまま
        // 端末に溜まり続ける。
        try {
          if (await tempFile.exists()) {
            // coverage:ignore-start
            // 書き込みが途中まで成功してファイルが残る状況は、ホストの
            // ファイルシステム依存でテストから再現できない。
            await tempFile.delete();
            // coverage:ignore-end
          }
        } catch (_) {
          // 削除できなくても読み込み失敗として扱えばよい。
        }
        rethrow;
      }

      _tempGeoJsonFilePath = tempFile.path;
      if (previousTempPath != null && previousTempPath != tempFile.path) {
        await _deleteTempGeoJsonFile(previousTempPath);
      }

      _applyLoadedGeoJson(
        model,
        decoded.fileName ?? 'temp_geojson_$timestamp.geojson',
        notes: 'GeoJSON loaded from QR code',
      );
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
      // キャンセルは pickQrImageFile() が null を返すことで表現される。
      // 例外メッセージの文字列で判定してはいけない（Androidのアプリ専用パス
      // /data/user/0/... で起きた例外を「利用者のキャンセル」と誤判定する）。
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
    final path = _tempGeoJsonFilePath;
    if (path == null) {
      return;
    }
    _tempGeoJsonFilePath = null;
    await _deleteTempGeoJsonFile(path);
  }

  Future<void> _deleteTempGeoJsonFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        _logInfo('APP', 'Temporary GeoJSON file deleted: $path');
      }
    } catch (e) {
      // coverage:ignore-start
      // File.delete failures depend on the host filesystem and permissions.
      _logError('APP', 'Failed to delete temporary GeoJSON file: $e');
      // coverage:ignore-end
    }
  }

  /// 読み込んだGeoJSONを適用し、監視開始待ちの状態へ戻します。
  ///
  /// ファイル・QR・QR画像の3経路で共通の後処理をここへ集約する。
  /// 別々に書くと、片方だけ状態のクリアが漏れる（距離や方位が前の
  /// エリアのまま残るなど）事故が起きやすい。
  void _applyLoadedGeoJson(
    GeoModel model,
    String fileName, {
    required String notes,
  }) {
    _geoModel = model;
    _geoJsonFileName = fileName;
    _areaIndex = AreaIndex.build(model.polygons);
    stateMachine.updateGeometry(_geoModel, _areaIndex);

    _snapshot = StateSnapshot(
      status: LocationStateStatus.waitStart,
      timestamp: _now(),
      geoJsonLoaded: true,
      distanceToBoundaryM: null,
      bearingToBoundaryDeg: null,
      nearestBoundaryPoint: null,
      notes: notes,
    );
    // 新しいエリアを読み込んだらナビゲーション表示を一旦オフにする。
    _navigationEnabled = false;
    _lastErrorMessage = null;
    _logInfo('APP', notes, timestamp: _snapshot.timestamp);
    notifyListeners();
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

  /// 後始末のためのプラットフォーム呼び出しを、失敗もタイムアウトも
  /// 握りつぶしてログに残しつつ実行します。
  ///
  /// ネイティブ側が応答を返さないと、監視の開始・停止が `starting` /
  /// `stopping` から抜けられなくなる。この状態では開始も停止も設定変更も
  /// できず、アプリを再起動するしか復帰手段がなくなる。待つのをやめて
  /// 後始末を先へ進めるほうが安全。
  Future<void> _guardedCleanup(
    String tag,
    String description,
    Future<void> Function() action,
  ) async {
    try {
      await action().timeout(_platformCallTimeout);
    } on TimeoutException {
      _logWarning(
          tag,
          '$description timed out after '
          '${_platformCallTimeout.inSeconds}s.');
    } catch (error) {
      _logWarning(tag, '$description failed: $error');
    }
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
      _cancelStaleEscalation();
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
      _staleSinceElapsed = _monitoringElapsed();
      final healthGeneration = ++_monitoringHealthGeneration;
      _logWarning('GPS', 'Location updates stopped: $reason.');
      notifyListeners();
      _scheduleLocationReconnect(runId);
      unawaited(
        _showMonitoringStaleWarning(runId, healthGeneration),
      );
      _startStaleEscalation(runId);
    }
    if (_isCurrentMonitoringRun(runId) &&
        _reconnectTimer == null &&
        !_reconnectInProgress) {
      _scheduleLocationReconnect(runId);
    }
  }

  /// 途絶が続くあいだ、一定間隔で警告を出し直します。
  void _startStaleEscalation(int runId) {
    _staleEscalationTimer?.cancel();
    _staleEscalationTimer = Timer.periodic(_staleReminderInterval, (timer) {
      // 条件を判定して return するだけだと、フラグを倒す経路が増えたときに
      // 永久に発火し続けるタイマーが残る。自分で止める。
      // coverage:ignore-start
      // 現状フラグを倒す経路はすべて _cancelStaleEscalation() を通るため
      // ここへは到達しない。将来の経路追加に対する保険として残す。
      if (!_isCurrentMonitoringRun(runId) || !_monitoringStaleWarningActive) {
        timer.cancel();
        if (identical(timer, _staleEscalationTimer)) {
          _staleEscalationTimer = null;
        }
        return;
      }
      // coverage:ignore-end
      final healthGeneration = ++_monitoringHealthGeneration;
      _logWarning(
        'GPS',
        'Location updates still stopped after '
            '${formatOutageDuration(_currentOutage() ?? Duration.zero)}.',
      );
      unawaited(_showMonitoringStaleWarning(runId, healthGeneration));
    });
  }

  void _cancelStaleEscalation() {
    _staleEscalationTimer?.cancel();
    _staleEscalationTimer = null;
    _staleSinceElapsed = null;
  }

  /// GPS途絶が続いている時間。途絶していなければ null。
  Duration? _currentOutage() {
    final since = _staleSinceElapsed;
    if (since == null) {
      return null;
    }
    final outage = _monitoringElapsed() - since;
    return outage.isNegative ? Duration.zero : outage;
  }

  Future<void> _showMonitoringStaleWarning(
    int runId,
    int healthGeneration,
  ) async {
    try {
      await notifier.notifyMonitoringStale(
        outage: _currentOutage(),
        recoveryAbandoned: _locationRecoveryAbandoned,
      );
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
    _cancelStaleEscalation();
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
  /// 警報を出せなかったことを、閉じるまで消えない警告として伝えます。
  void _reportAlertFailure(String message, String logMessage) {
    _alertReliabilityWarning = message;
    _logError('ALERT', logMessage);
    notifyListeners();
  }

  bool _reportUnstoppedAlert() {
    if (!notifier.hasActiveAlertPlayback) {
      return false;
    }
    _alertReliabilityWarning = '警報を停止できませんでした。'
        '音やバイブが続く場合は端末の音量を下げ、アプリを再起動してください。';
    _logError('ALERT', 'Alert playback could not be stopped.');
    notifyListeners();
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
        // 発報経路が欠けたことをログだけに残すと、警報音が鳴っていないのに
        // 通常のOUTER画面が出て「警報は動いている」と誤解される。
        _alertReliabilityWarning = '${delivery.failedChannelsLabel}'
            'を発報できませんでした。エリア外の警告に気づけない可能性があります。'
            '端末の音量・サイレントモード・通知設定を確認してください。';
        notifyListeners();
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
      // ミュート解除の表示だけ戻して音が鳴らないと、エリア外なのに
      // 「警報は動いている」と誤解する。ログだけに残してはいけない。
      _reportAlertFailure(
        '1分間のミュート後に警報を再開できませんでした。'
            'エリア外の警告に気づけない可能性があります。'
            '端末の音量・サイレントモードを確認してください。',
        'Failed to resume alarm after snooze: $error',
      );
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
    String? alertReliabilityWarning,
    bool clearConfig = false,
  }) {
    if (alertReliabilityWarning != null) {
      _alertReliabilityWarning = alertReliabilityWarning;
    }
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
    // 他の終了経路と同じく runId を進めてから購読を捨てる。進めないと
    // _isCurrentMonitoringRun が true のままで、購読解除が効くまでの間に
    // 届いた fix が破棄済みのコントローラで処理されてしまう。
    _monitoringRunId += 1;
    _cancelLocationRecovery();
    _clearAlarmSnooze();
    _subscription?.cancel();
    _subscription = null;
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
    final config = (await fileManager.readConfig()).config.normalized();
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
