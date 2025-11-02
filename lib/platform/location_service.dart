import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../io/config.dart';

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

abstract class LocationService {
  Stream<LocationFix> get stream;
  Future<void> start(AppConfig config);
  Future<void> stop();
}

class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService();

  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  StreamSubscription<Position>? _subscription;

  @override
  Stream<LocationFix> get stream => _controller.stream;

  @override
  Future<void> start(AppConfig config) async {
    final granted = await _ensurePermission();
    if (!granted) {
      return;
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
      );
    } else if (Platform.isIOS || Platform.isMacOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distanceFilter,
      );
    }

    _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((position) {
      _controller.add(
        LocationFix(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          timestamp: position.timestamp ?? DateTime.now(),
        ),
      );
    });
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}

class FakeLocationService implements LocationService {
  FakeLocationService(this._stream);

  final Stream<LocationFix> _stream;

  @override
  Stream<LocationFix> get stream => _stream;

  @override
  Future<void> start(AppConfig config) async {}

  @override
  Future<void> stop() async {}
}
