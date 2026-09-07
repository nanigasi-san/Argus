import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../io/config.dart';

/// 位置情報のスナップショットを表すクラス。
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracyMeters,
    this.monitoringElapsed,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? accuracyMeters;

  /// 監視開始からの単調増加する経過時間。
  ///
  /// `AppController` が監視セッション単位で計測して付与する。位置サービスの
  /// 再接続をまたいでも巻き戻らないため、ヒステリシス判定の基準に使える。
  /// 壁時計やGPSタイムスタンプは補正・巻き戻りがあるため使用しない。
  final Duration? monitoringElapsed;

  /// 監視セッションの経過時間を付与した複製を返します。
  LocationFix withMonitoringElapsed(Duration? elapsed) {
    return LocationFix(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      accuracyMeters: accuracyMeters,
      monitoringElapsed: elapsed,
    );
  }
}

/// 位置情報サービスへの抽象インターフェース。
///
/// プラットフォーム固有の実装はこのインターフェースを実装します。
abstract class LocationService {
  Stream<LocationFix> get stream;
  Future<LocationServiceStartResult> start(AppConfig config);
  Future<void> stop();
}

enum LocationServiceStartStatus {
  started,
  servicesDisabled,
  permissionMissing,
  error,
}

class LocationStreamEndedException implements Exception {
  const LocationStreamEndedException();

  @override
  String toString() => '位置情報ストリームが予期せず終了しました。';
}

class LocationServiceStartResult {
  const LocationServiceStartResult({
    required this.status,
    this.message,
  });

  const LocationServiceStartResult.started()
      : status = LocationServiceStartStatus.started,
        message = null;

  final LocationServiceStartStatus status;
  final String? message;
}

class LocationSettingsFactory {
  const LocationSettingsFactory();

  LocationSettings buildStreamSettings({
    required RuntimePlatform runtimePlatform,
    required Duration interval,
  }) {
    if (runtimePlatform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: interval,
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ARGUSが位置情報を監視中です',
          notificationText: '画面を消しても位置情報の追跡は継続されます。',
          notificationChannelName: 'ARGUSバックグラウンド監視',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (runtimePlatform.isApple) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }
}

// coverage:ignore-start
/// Geolocatorパッケージを使用した位置情報サービスの実装。
class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService({
    RuntimePlatform? runtimePlatform,
    LocationSettingsFactory? settingsFactory,
  })  : _runtimePlatform = runtimePlatform ?? RuntimePlatform.current(),
        _settingsFactory = settingsFactory ?? const LocationSettingsFactory();

  final RuntimePlatform _runtimePlatform;
  final LocationSettingsFactory _settingsFactory;

  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  StreamSubscription<Position>? _subscription;
  DateTime? _startedAt;

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationServiceStartResult(
        status: LocationServiceStartStatus.servicesDisabled,
        message: '端末の位置情報サービスが無効です。',
      );
    }

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      return const LocationServiceStartResult(
        status: LocationServiceStartStatus.permissionMissing,
        message: '位置情報を「常に許可」にしてください。',
      );
    }

    final normalizedConfig = config.normalized();
    final interval =
        Duration(seconds: normalizedConfig.effectiveFastSampleIntervalS);

    final settings = _settingsFactory.buildStreamSettings(
      runtimePlatform: _runtimePlatform,
      interval: interval,
    );
    try {
      await _subscription?.cancel();
      _startedAt = DateTime.now();
      _subscription = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen(
        _emitPosition,
        onError: (Object error, StackTrace stackTrace) {
          _controller.addError(error, stackTrace);
        },
        onDone: () {
          _controller.addError(const LocationStreamEndedException());
        },
      );
      return const LocationServiceStartResult.started();
    } catch (e) {
      return LocationServiceStartResult(
        status: LocationServiceStartStatus.error,
        message: e.toString(),
      );
    }
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _startedAt = null;
  }

  // monitoringElapsed はここでは付けない。位置サービスは再接続で stop/start を
  // 繰り返すため、ここで計測すると再接続ごとに 0 へ戻り、ヒステリシスの基準時刻が
  // 巻き戻る。監視セッションの経過時間は AppController が所有する。
  void _emitPosition(Position position) {
    final startedAt = _startedAt;
    if (startedAt == null || position.timestamp.isBefore(startedAt)) {
      return;
    }
    _controller.add(
      LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        timestamp: position.timestamp,
      ),
    );
  }
}
// coverage:ignore-end

class RuntimePlatform {
  const RuntimePlatform({
    required this.isAndroid,
    required this.isIOS,
    required this.isMacOS,
  });

  factory RuntimePlatform.current() {
    return RuntimePlatform(
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
      isMacOS: Platform.isMacOS,
    );
  }

  final bool isAndroid;
  final bool isIOS;
  final bool isMacOS;

  bool get isApple => isIOS || isMacOS;
}

class FakeLocationService implements LocationService {
  FakeLocationService(this._stream);

  final Stream<LocationFix> _stream;

  @override
  Stream<LocationFix> get stream => _stream;

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    return const LocationServiceStartResult.started();
  }

  @override
  Future<void> stop() async {}
}
