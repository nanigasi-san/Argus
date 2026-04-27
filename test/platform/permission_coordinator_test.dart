import 'package:argus/platform/permission_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('PermissionCoordinator', () {
    test('monitoring permission state exposes summaries and blocked messages',
        () {
      const deniedState = MonitoringPermissionState(
        notificationStatus: PermissionStatus.denied,
        locationWhenInUseStatus: PermissionStatus.denied,
        locationAlwaysStatus: PermissionStatus.denied,
        locationServicesEnabled: false,
      );
      const readyState = MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.granted,
        locationAlwaysStatus: PermissionStatus.granted,
        locationServicesEnabled: true,
      );

      expect(deniedState.canStartMonitoring, isFalse);
      expect(deniedState.monitoringBlockedMessage, contains('位置情報サービス'));
      expect(deniedState.setupSummary, contains('位置情報サービス'));
      expect(readyState.notificationGranted, isTrue);
      expect(readyState.locationWhenInUseGranted, isTrue);
      expect(readyState.locationAlwaysGranted, isTrue);
      expect(readyState.canStartMonitoring, isTrue);
      expect(readyState.setupSummary, '監視を開始できる状態です。');
      expect(
        readyState
            .copyWith(locationAlwaysStatus: PermissionStatus.denied)
            .locationAlwaysGranted,
        isFalse,
      );
    });

    test('camera permission state exposes guidance', () {
      const granted =
          CameraPermissionState(status: PermissionStatus.provisional);
      const denied =
          CameraPermissionState(status: PermissionStatus.permanentlyDenied);
      const normalDenied =
          CameraPermissionState(status: PermissionStatus.denied);

      expect(granted.isGranted, isTrue);
      expect(granted.message, 'カメラを使用できます。');
      expect(denied.requiresManualSettings, isTrue);
      expect(denied.message, contains('アプリ設定'));
      expect(normalDenied.message, contains('QR'));
    });

    test('refreshMonitoringPermissionState does not request permissions',
        () async {
      final gateway = _FakePermissionGateway(
        notificationStatusValue: PermissionStatus.denied,
        locationWhenInUseStatusValue: PermissionStatus.denied,
        locationAlwaysStatusValue: PermissionStatus.denied,
      );

      final coordinator = PermissionCoordinator(
        gateway: gateway,
        openSettings: () async => true,
        openLocationSettings: () async => true,
        locationServicesEnabled: () async => true,
      );

      final state = await coordinator.refreshMonitoringPermissionState();

      expect(gateway.requestNotificationCount, 0);
      expect(gateway.requestLocationWhenInUseCount, 0);
      expect(gateway.requestLocationAlwaysCount, 0);
      expect(state.notificationGranted, isFalse);
      expect(state.locationWhenInUseGranted, isFalse);
      expect(state.locationAlwaysGranted, isFalse);
    });

    test(
        'completeMonitoringSetup requests foreground and background location after disclosure',
        () async {
      final gateway = _FakePermissionGateway(
        notificationStatusValue: PermissionStatus.granted,
        locationWhenInUseStatusValue: PermissionStatus.denied,
        locationWhenInUseRequestResult: PermissionStatus.granted,
        locationAlwaysStatusValue: PermissionStatus.denied,
        locationAlwaysRequestResult: PermissionStatus.granted,
      );

      final coordinator = PermissionCoordinator(
        gateway: gateway,
        openSettings: () async => true,
        openLocationSettings: () async => true,
        locationServicesEnabled: () async => true,
      );

      final state = await coordinator.completeMonitoringSetup();

      expect(gateway.requestLocationWhenInUseCount, 1);
      expect(gateway.requestLocationAlwaysCount, 1);
      expect(state.canStartMonitoring, isTrue);
    });

    test(
        'completeMonitoringSetup opens app settings when background remains denied',
        () async {
      final gateway = _FakePermissionGateway(
        notificationStatusValue: PermissionStatus.granted,
        locationWhenInUseStatusValue: PermissionStatus.granted,
        locationAlwaysStatusValue: PermissionStatus.denied,
        locationAlwaysRequestResult: PermissionStatus.permanentlyDenied,
      );
      var openSettingsCount = 0;

      final coordinator = PermissionCoordinator(
        gateway: gateway,
        openSettings: () async {
          openSettingsCount += 1;
          return true;
        },
        openLocationSettings: () async => true,
        locationServicesEnabled: () async => true,
      );

      final state = await coordinator.completeMonitoringSetup();

      expect(gateway.requestLocationAlwaysCount, 1);
      expect(openSettingsCount, 1);
      expect(state.locationAlwaysGranted, isFalse);
    });

    test('requestNotificationPermission requests notification and refreshes',
        () async {
      final gateway = _FakePermissionGateway(
        notificationStatusValue: PermissionStatus.denied,
        notificationRequestResult: PermissionStatus.granted,
      );

      final coordinator = PermissionCoordinator(
        gateway: gateway,
        openSettings: () async => true,
        openLocationSettings: () async => true,
        locationServicesEnabled: () async => true,
      );

      final state = await coordinator.requestNotificationPermission();

      expect(gateway.requestNotificationCount, 1);
      expect(state.notificationGranted, isTrue);
    });

    test('completeMonitoringSetup opens location settings when services off',
        () async {
      final gateway = _FakePermissionGateway();
      var openLocationSettingsCount = 0;

      final coordinator = PermissionCoordinator(
        gateway: gateway,
        openSettings: () async => true,
        openLocationSettings: () async {
          openLocationSettingsCount += 1;
          return true;
        },
        locationServicesEnabled: () async => false,
      );

      final state = await coordinator.completeMonitoringSetup();

      expect(openLocationSettingsCount, 1);
      expect(state.locationServicesEnabled, isFalse);
    });

    test('completeMonitoringSetup opens app settings when foreground denied',
        () async {
      final gateway = _FakePermissionGateway(
        locationWhenInUseStatusValue: PermissionStatus.denied,
        locationWhenInUseRequestResult: PermissionStatus.restricted,
      );
      var openSettingsCount = 0;

      final coordinator = PermissionCoordinator(
        gateway: gateway,
        openSettings: () async {
          openSettingsCount += 1;
          return true;
        },
        openLocationSettings: () async => true,
        locationServicesEnabled: () async => true,
      );

      final state = await coordinator.completeMonitoringSetup();

      expect(gateway.requestLocationWhenInUseCount, 1);
      expect(openSettingsCount, 1);
      expect(state.locationWhenInUseGranted, isFalse);
    });

    test('ensureCameraPermission requests once and can open settings',
        () async {
      final gateway = _FakePermissionGateway(
        cameraStatusValue: PermissionStatus.denied,
        cameraRequestResult: PermissionStatus.restricted,
      );
      var openSettingsCount = 0;

      final coordinator = PermissionCoordinator(
        gateway: gateway,
        openSettings: () async {
          openSettingsCount += 1;
          return true;
        },
        openLocationSettings: () async => true,
        locationServicesEnabled: () async => true,
      );

      final state =
          await coordinator.ensureCameraPermission(openSettingsIfNeeded: true);

      expect(gateway.requestCameraCount, 1);
      expect(state.requiresManualSettings, isTrue);
      expect(openSettingsCount, 1);
    });

    test('openSettings proxies to provided callback', () async {
      var openSettingsCount = 0;
      final coordinator = PermissionCoordinator(
        gateway: _FakePermissionGateway(),
        openSettings: () async {
          openSettingsCount += 1;
          return true;
        },
        openLocationSettings: () async => true,
        locationServicesEnabled: () async => true,
      );

      final opened = await coordinator.openSettings();

      expect(opened, isTrue);
      expect(openSettingsCount, 1);
    });
  });
}

class _FakePermissionGateway implements PermissionGateway {
  _FakePermissionGateway({
    this.notificationStatusValue = PermissionStatus.granted,
    this.notificationRequestResult = PermissionStatus.granted,
    this.locationWhenInUseStatusValue = PermissionStatus.granted,
    this.locationWhenInUseRequestResult = PermissionStatus.granted,
    this.locationAlwaysStatusValue = PermissionStatus.granted,
    this.locationAlwaysRequestResult = PermissionStatus.granted,
    this.cameraStatusValue = PermissionStatus.granted,
    this.cameraRequestResult = PermissionStatus.granted,
  });

  PermissionStatus notificationStatusValue;
  PermissionStatus notificationRequestResult;
  PermissionStatus locationWhenInUseStatusValue;
  PermissionStatus locationWhenInUseRequestResult;
  PermissionStatus locationAlwaysStatusValue;
  PermissionStatus locationAlwaysRequestResult;
  PermissionStatus cameraStatusValue;
  PermissionStatus cameraRequestResult;

  int requestNotificationCount = 0;
  int requestLocationWhenInUseCount = 0;
  int requestLocationAlwaysCount = 0;
  int requestCameraCount = 0;

  @override
  Future<PermissionStatus> cameraStatus() async => cameraStatusValue;

  @override
  Future<PermissionStatus> locationAlwaysStatus() async =>
      locationAlwaysStatusValue;

  @override
  Future<PermissionStatus> locationWhenInUseStatus() async =>
      locationWhenInUseStatusValue;

  @override
  Future<PermissionStatus> notificationStatus() async =>
      notificationStatusValue;

  @override
  Future<PermissionStatus> requestCamera() async {
    requestCameraCount += 1;
    cameraStatusValue = cameraRequestResult;
    return cameraRequestResult;
  }

  @override
  Future<PermissionStatus> requestLocationAlways() async {
    requestLocationAlwaysCount += 1;
    locationAlwaysStatusValue = locationAlwaysRequestResult;
    return locationAlwaysRequestResult;
  }

  @override
  Future<PermissionStatus> requestLocationWhenInUse() async {
    requestLocationWhenInUseCount += 1;
    locationWhenInUseStatusValue = locationWhenInUseRequestResult;
    return locationWhenInUseRequestResult;
  }

  @override
  Future<PermissionStatus> requestNotification() async {
    requestNotificationCount += 1;
    notificationStatusValue = notificationRequestResult;
    return notificationRequestResult;
  }
}
