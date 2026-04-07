import 'package:argus/platform/permission_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('PermissionCoordinator', () {
    test('initial monitoring permissions stop before background location',
        () async {
      final gateway = _FakePermissionGateway(
        notificationStatusValue: PermissionStatus.denied,
        notificationRequestResult: PermissionStatus.granted,
        locationWhenInUseStatusValue: PermissionStatus.denied,
        locationWhenInUseRequestResult: PermissionStatus.granted,
        locationAlwaysStatusValue: PermissionStatus.denied,
      );

      final coordinator = PermissionCoordinator(
        gateway: gateway,
        openSettings: () async => true,
        openLocationSettings: () async => true,
        locationServicesEnabled: () async => true,
      );

      final state = await coordinator.requestInitialMonitoringPermissions();

      expect(gateway.requestNotificationCount, 1);
      expect(gateway.requestLocationWhenInUseCount, 1);
      expect(gateway.requestLocationAlwaysCount, 0);
      expect(state.locationWhenInUseGranted, isTrue);
      expect(state.locationAlwaysGranted, isFalse);
    });

    test(
        'completeMonitoringSetup requests background location after disclosure',
        () async {
      final gateway = _FakePermissionGateway(
        notificationStatusValue: PermissionStatus.granted,
        locationWhenInUseStatusValue: PermissionStatus.granted,
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
  });

  PermissionStatus notificationStatusValue;
  PermissionStatus notificationRequestResult;
  PermissionStatus locationWhenInUseStatusValue;
  PermissionStatus locationWhenInUseRequestResult;
  PermissionStatus locationAlwaysStatusValue;
  PermissionStatus locationAlwaysRequestResult;

  int requestNotificationCount = 0;
  int requestLocationWhenInUseCount = 0;
  int requestLocationAlwaysCount = 0;

  @override
  Future<PermissionStatus> cameraStatus() async => PermissionStatus.granted;

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
    return PermissionStatus.granted;
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
