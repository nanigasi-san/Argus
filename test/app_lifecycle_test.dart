import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/main.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state_machine.dart';

import 'support/notifier_fakes.dart';
import 'support/test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ArgusApp refreshes permissions on resume', (tester) async {
    final controller = _LifecycleController();

    await tester.pumpWidget(ArgusApp(controller: controller));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(controller.refreshCount, 1);
  });

  testWidgets('ArgusApp handles app termination on detach', (tester) async {
    final controller = _LifecycleController();

    await tester.pumpWidget(ArgusApp(controller: controller));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();

    expect(controller.terminationCount, 1);
  });

  testWidgets('ArgusApp removes lifecycle observer on dispose', (tester) async {
    final controller = _LifecycleController();

    await tester.pumpWidget(ArgusApp(controller: controller));
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(controller.refreshCount, 0);
  });
}

class _LifecycleController extends AppController {
  _LifecycleController()
      : super(
          stateMachine: StateMachine(config: createTestConfig()),
          locationService: FakeLocationService(),
          fileManager: FakeFileManager(config: createTestConfig()),
          logger: FakeEventLogger(),
          notifier: Notifier(
            notificationsClient: FakeLocalNotificationsClient(),
            alarmPlayer: FakeAlarmPlayer(),
          ),
          permissionCoordinator: PermissionCoordinator(),
        ) {
    debugSeed(config: createTestConfig());
  }

  int refreshCount = 0;
  int terminationCount = 0;

  @override
  Future<void> refreshMonitoringPermissionState() async {
    refreshCount += 1;
  }

  @override
  Future<void> handleAppTermination() async {
    terminationCount += 1;
  }
}
