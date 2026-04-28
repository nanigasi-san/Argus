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
    this.batteryPercent,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? accuracyMeters;
  final double? batteryPercent;
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

/// Geolocatorパッケージを使用した位置情報サービスの実装。
class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService({
    RuntimePlatform? runtimePlatform,
  }) : _runtimePlatform = runtimePlatform ?? RuntimePlatform.current();

  final RuntimePlatform _runtimePlatform;

  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  StreamSubscription<Position>? _subscription;
  Timer? _pollTimer;

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

    final LocationSettings settings;
    if (_runtimePlatform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: interval,
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Argusが位置情報を監視中です',
          notificationText: '画面を消しても位置情報の追跡は継続されます。',
          notificationChannelName: 'Argusバックグラウンド監視',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (_runtimePlatform.isApple) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );
    }
    const pollSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );

    try {
      await _subscription?.cancel();
      _pollTimer?.cancel();
      _subscription = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen(_emitPosition);
      _pollTimer = Timer.periodic(interval, (_) {
        unawaited(_pollCurrentPosition(pollSettings));
      });
      unawaited(_pollCurrentPosition(pollSettings));
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
    _pollTimer?.cancel();
    _pollTimer = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  void _emitPosition(Position position) {
    _controller.add(
      LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        timestamp: position.timestamp,
      ),
    );
  }

  Future<void> _pollCurrentPosition(LocationSettings settings) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      _emitPosition(position);
    } catch (_) {
      // The stream remains active even if one explicit poll fails.
    }
  }
}

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
