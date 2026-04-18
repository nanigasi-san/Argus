import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:permission_handler/permission_handler.dart';

typedef OpenAppSettingsCallback = Future<bool> Function();
typedef OpenLocationSettingsCallback = Future<bool> Function();
typedef LocationServicesEnabledCallback = Future<bool> Function();

abstract class PermissionGateway {
  Future<PermissionStatus> notificationStatus();
  Future<PermissionStatus> requestNotification();
  Future<PermissionStatus> locationWhenInUseStatus();
  Future<PermissionStatus> requestLocationWhenInUse();
  Future<PermissionStatus> locationAlwaysStatus();
  Future<PermissionStatus> requestLocationAlways();
  Future<PermissionStatus> cameraStatus();
  Future<PermissionStatus> requestCamera();
}

class PermissionHandlerGateway implements PermissionGateway {
  const PermissionHandlerGateway();

  @override
  Future<PermissionStatus> notificationStatus() =>
      Permission.notification.status;

  @override
  Future<PermissionStatus> requestNotification() =>
      Permission.notification.request();

  @override
  Future<PermissionStatus> locationWhenInUseStatus() =>
      Permission.locationWhenInUse.status;

  @override
  Future<PermissionStatus> requestLocationWhenInUse() =>
      Permission.locationWhenInUse.request();

  @override
  Future<PermissionStatus> locationAlwaysStatus() =>
      Permission.locationAlways.status;

  @override
  Future<PermissionStatus> requestLocationAlways() =>
      Permission.locationAlways.request();

  @override
  Future<PermissionStatus> cameraStatus() => Permission.camera.status;

  @override
  Future<PermissionStatus> requestCamera() => Permission.camera.request();
}

class MonitoringPermissionState {
  const MonitoringPermissionState({
    required this.notificationStatus,
    required this.locationWhenInUseStatus,
    required this.locationAlwaysStatus,
    required this.locationServicesEnabled,
  });

  const MonitoringPermissionState.unknown()
      : this(
          notificationStatus: PermissionStatus.denied,
          locationWhenInUseStatus: PermissionStatus.denied,
          locationAlwaysStatus: PermissionStatus.denied,
          locationServicesEnabled: true,
        );

  final PermissionStatus notificationStatus;
  final PermissionStatus locationWhenInUseStatus;
  final PermissionStatus locationAlwaysStatus;
  final bool locationServicesEnabled;

  bool get notificationGranted => _isGranted(notificationStatus);

  bool get locationWhenInUseGranted => _isGranted(locationWhenInUseStatus);

  bool get locationAlwaysGranted => _isGranted(locationAlwaysStatus);

  bool get canStartMonitoring =>
      locationServicesEnabled && locationAlwaysGranted;

  String get monitoringBlockedMessage {
    if (!locationServicesEnabled) {
      return '端末の位置情報サービスを有効にしてください。';
    }
    if (!locationWhenInUseGranted) {
      return '監視を開始するには位置情報の使用中許可が必要です。';
    }
    if (!locationAlwaysGranted) {
      return '監視を開始するには、バックグラウンド位置情報の開示を確認し、位置情報を「常に許可」にしてください。';
    }
    return '';
  }

  String get setupSummary {
    if (!locationServicesEnabled) {
      return 'バックグラウンド監視の前に、端末全体の位置情報サービスを有効にしてください。';
    }
    if (!locationWhenInUseGranted) {
      return '初回セットアップでは、まず位置情報の使用中許可が必要です。';
    }
    if (!locationAlwaysGranted) {
      return '監視を開始する前に、バックグラウンド位置情報の開示を確認し、「常に許可」を設定してください。';
    }
    if (!notificationGranted) {
      return '通知を許可すると、警告を見逃しにくくなります。';
    }
    return '監視を開始できる状態です。';
  }

  MonitoringPermissionState copyWith({
    PermissionStatus? notificationStatus,
    PermissionStatus? locationWhenInUseStatus,
    PermissionStatus? locationAlwaysStatus,
    bool? locationServicesEnabled,
  }) {
    return MonitoringPermissionState(
      notificationStatus: notificationStatus ?? this.notificationStatus,
      locationWhenInUseStatus:
          locationWhenInUseStatus ?? this.locationWhenInUseStatus,
      locationAlwaysStatus: locationAlwaysStatus ?? this.locationAlwaysStatus,
      locationServicesEnabled:
          locationServicesEnabled ?? this.locationServicesEnabled,
    );
  }

  static bool _isGranted(PermissionStatus status) {
    return status.isGranted || status.isLimited || status.isProvisional;
  }
}

class CameraPermissionState {
  const CameraPermissionState({required this.status});

  final PermissionStatus status;

  bool get isGranted =>
      status.isGranted || status.isLimited || status.isProvisional;

  bool get requiresManualSettings =>
      status.isPermanentlyDenied || status.isRestricted;

  String get message {
    if (isGranted) {
      return 'カメラを使用できます。';
    }
    if (requiresManualSettings) {
      return 'カメラ権限が無効です。アプリ設定から許可してください。';
    }
    return 'QR を読み取るにはカメラ権限が必要です。';
  }
}

class PermissionCoordinator {
  PermissionCoordinator({
    PermissionGateway? gateway,
    OpenAppSettingsCallback? openSettings,
    OpenLocationSettingsCallback? openLocationSettings,
    LocationServicesEnabledCallback? locationServicesEnabled,
  })  : _gateway = gateway ?? const PermissionHandlerGateway(),
        _openAppSettings = openSettings ?? openAppSettings,
        _openLocationSettings =
            openLocationSettings ?? geolocator.Geolocator.openLocationSettings,
        _locationServicesEnabled = locationServicesEnabled ??
            geolocator.Geolocator.isLocationServiceEnabled;

  final PermissionGateway _gateway;
  final OpenAppSettingsCallback _openAppSettings;
  final OpenLocationSettingsCallback _openLocationSettings;
  final LocationServicesEnabledCallback _locationServicesEnabled;

  Future<MonitoringPermissionState> refreshMonitoringPermissionState() async {
    final locationServicesEnabled = await _locationServicesEnabled();
    final notificationStatus = await _gateway.notificationStatus();
    final locationWhenInUseStatus = await _gateway.locationWhenInUseStatus();
    final locationAlwaysStatus = await _gateway.locationAlwaysStatus();

    return MonitoringPermissionState(
      notificationStatus: notificationStatus,
      locationWhenInUseStatus: locationWhenInUseStatus,
      locationAlwaysStatus: locationAlwaysStatus,
      locationServicesEnabled: locationServicesEnabled,
    );
  }

  Future<MonitoringPermissionState> requestNotificationPermission() async {
    await _gateway.requestNotification();
    return refreshMonitoringPermissionState();
  }

  Future<MonitoringPermissionState> completeMonitoringSetup() async {
    var state = await refreshMonitoringPermissionState();
    if (!state.locationServicesEnabled) {
      await _openLocationSettings();
      return state;
    }

    if (!state.locationWhenInUseGranted) {
      await _gateway.requestLocationWhenInUse();
      state = await refreshMonitoringPermissionState();
      if (!state.locationWhenInUseGranted &&
          _needsManualSettings(state.locationWhenInUseStatus)) {
        await _openAppSettings();
        return state;
      }
    }

    if (!state.locationAlwaysGranted) {
      await _gateway.requestLocationAlways();
      state = await refreshMonitoringPermissionState();
      if (!state.locationAlwaysGranted) {
        await _openAppSettings();
        return state;
      }
    }

    return state;
  }

  Future<CameraPermissionState> ensureCameraPermission({
    bool openSettingsIfNeeded = false,
  }) async {
    var status = await _gateway.cameraStatus();
    if (!_isGranted(status)) {
      status = await _gateway.requestCamera();
    }
    final result = CameraPermissionState(status: status);
    if (openSettingsIfNeeded && result.requiresManualSettings) {
      await _openAppSettings();
    }
    return result;
  }

  Future<bool> openSettings() => _openAppSettings();

  bool _isGranted(PermissionStatus status) {
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  bool _needsManualSettings(PermissionStatus status) {
    return status.isPermanentlyDenied || status.isRestricted;
  }
}
