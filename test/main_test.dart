import 'package:flutter_test/flutter_test.dart';

import 'package:argus/main.dart';
import 'package:argus/app_controller.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/io/config.dart';
import 'package:argus/io/file_manager.dart';
import 'package:argus/io/logger.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'dart:io';

class MockLocationService extends LocationService {
  @override
  Future<void> start(AppConfig config) async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<LocationFix> get stream => const Stream.empty();
}

class MockFileManager extends FileManager {
  @override
  Future<AppConfig> readConfig() async {
    return AppConfig.loadDefault();
  }

  @override
  Future<File> openLogFile() async {
    final tempDir = Directory.systemTemp;
    return File('${tempDir.path}/test_argus.log');
  }
}

class MockEventLogger extends EventLogger {
  MockEventLogger() : super();
}

class MockNotifier extends Notifier {
  @override
  Future<void> updateBadge(LocationStateStatus status) async {}

  @override
  Future<void> notifyOuter() async {}

  @override
  Future<void> notifyRecover() async {}
}

void main() {
  testWidgets('Argus app displays correctly', (WidgetTester tester) async {
    final mockFileManager = MockFileManager();
    final config = await mockFileManager.readConfig();

    final controller = AppController(
      stateMachine: StateMachine(config: config),
      locationService: MockLocationService(),
      fileManager: mockFileManager,
      logger: MockEventLogger(),
      notifier: MockNotifier(),
    );

    await tester.pumpWidget(ArgusApp(controller: controller));

    await tester.pumpAndSettle();

    expect(find.text('Argus'), findsWidgets);
  });
}
