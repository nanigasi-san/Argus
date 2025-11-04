// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

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
    // Return a temporary file for testing
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
    // Create a minimal mock AppController for testing
    final mockFileManager = MockFileManager();
    final config = await mockFileManager.readConfig();
    final tempFile = await mockFileManager.openLogFile();

    final controller = AppController(
      stateMachine: StateMachine(config: config),
      locationService: MockLocationService(),
      fileManager: mockFileManager,
      logger: MockEventLogger(),
      notifier: MockNotifier(),
    );

    // Build our app and trigger a frame.
    await tester.pumpWidget(ArgusApp(controller: controller));

    // Verify that the app title 'Argus' is displayed
    expect(find.text('Argus'), findsWidgets);

    // Verify that the status information is displayed
    expect(find.textContaining('Current state'), findsOneWidget);
  });
}
