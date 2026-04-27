import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/ui/background_location_disclosure_page.dart';

import '../support/notifier_fakes.dart';
import '../support/platform_mocks.dart';
import '../support/test_doubles.dart';

void main() {
  setUpAll(() async {
    await mockUrlLauncher(launchResult: true);
  });

  tearDown(() async {
    await clearUrlLauncherMock();
  });

  testWidgets('continue button completes setup and pops true', (tester) async {
    final controller = _DisclosureTestController();
    bool? result;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showBackgroundLocationDisclosure(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意して位置情報の設定へ進む'));
    await tester.pumpAndSettle();

    expect(controller.completeSetupCount, 1);
    expect(result, isTrue);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('cancel button pops false', (tester) async {
    final controller = _DisclosureTestController();
    bool? result;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showBackgroundLocationDisclosure(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今はしない'));
    await tester.pumpAndSettle();

    expect(controller.completeSetupCount, 0);
    expect(result, isFalse);
  });

  testWidgets('privacy policy failure shows snackbar', (tester) async {
    await clearUrlLauncherMock();
    await mockUrlLauncher(launchResult: false);
    final controller = _DisclosureTestController();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(home: BackgroundLocationDisclosurePage()),
      ),
    );

    await tester.ensureVisible(find.text('Privacy Policy を開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy Policy を開く'));
    await tester.pumpAndSettle();

    expect(find.text('プライバシーポリシーを開けませんでした。'), findsOneWidget);
  });
}

class _DisclosureTestController extends AppController {
  _DisclosureTestController()
      : super(
          stateMachine: StateMachine(config: createTestConfig()),
          locationService: FakeLocationService(),
          fileManager: FakeFileManager(config: createTestConfig()),
          logger: FakeEventLogger(),
          notifier: Notifier(
            notificationsClient: FakeLocalNotificationsClient(),
            alarmPlayer: FakeAlarmPlayer(),
          ),
          permissionCoordinator: _DisclosurePermissionCoordinator(),
        ) {
    debugSeed(
      config: createTestConfig(),
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.granted,
        locationAlwaysStatus: PermissionStatus.denied,
        locationServicesEnabled: true,
      ),
    );
  }

  int completeSetupCount = 0;

  @override
  Future<void> completeMonitoringPermissionSetup() async {
    completeSetupCount += 1;
  }
}

class _DisclosurePermissionCoordinator extends PermissionCoordinator {}
