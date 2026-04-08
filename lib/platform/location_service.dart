import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
  GeolocatorLocationService();

  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  StreamSubscription<Position>? _subscription;

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

    final intervalSeconds = config.sampleIntervalS['fast'] ??
        (config.sampleIntervalS.values.isNotEmpty
            ? config.sampleIntervalS.values.reduce(math.min)
            : 3);
    final interval = Duration(seconds: intervalSeconds);
    const distanceFilter = 0;

    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distanceFilter,
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
    } else if (Platform.isIOS || Platform.isMacOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distanceFilter,
      );
    }

    try {
      _subscription?.cancel();
      _subscription = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen((position) {
        _controller.add(
          LocationFix(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
            timestamp: position.timestamp,
          ),
        );
      });
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
  }
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
