import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/ui/qr_scanner_page.dart';
import 'package:argus/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'support/app_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Android UI smoke', () {
    setUpAll(() async {
      await binding.convertFlutterSurfaceToImage();
    });

    testWidgets(
        'home shows setup card when monitoring permissions are incomplete',
        (tester) async {
      final controller = HarnessBuilder.buildController(
        hasGeoJson: true,
        snapshot: StateSnapshot(
          status: LocationStateStatus.waitStart,
          timestamp: DateTime.utc(2026, 4, 4),
          geoJsonLoaded: true,
        ),
        permissionState: const MonitoringPermissionState(
          notificationStatus: PermissionStatus.denied,
          locationWhenInUseStatus: PermissionStatus.granted,
          locationAlwaysStatus: PermissionStatus.denied,
          locationServicesEnabled: true,
        ),
      );

      await tester.pumpWidget(HarnessBuilder.buildApp(controller));
      await tester.pumpAndSettle();

      expect(find.text('バックグラウンド位置情報の設定が必要です'), findsOneWidget);
      expect(find.text('開示を確認して設定へ進む'), findsOneWidget);
      expect(find.text('通知を許可'), findsOneWidget);

      await _tryTakeScreenshot(binding, 'home-permission-card');
    });

    testWidgets('home can open background location disclosure', (tester) async {
      final controller = HarnessBuilder.buildController(
        hasGeoJson: true,
        permissionState: const MonitoringPermissionState(
          notificationStatus: PermissionStatus.granted,
          locationWhenInUseStatus: PermissionStatus.granted,
          locationAlwaysStatus: PermissionStatus.denied,
          locationServicesEnabled: true,
        ),
      );

      await tester.pumpWidget(HarnessBuilder.buildApp(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('開示を確認して設定へ進む'));
      await tester.pumpAndSettle();

      expect(find.text('バックグラウンド位置情報の開示'), findsOneWidget);
      expect(find.text('同意して位置情報の設定へ進む'), findsOneWidget);

      await _tryTakeScreenshot(binding, 'background-location-disclosure');
    });

    testWidgets('settings page renders the monitoring card and form',
        (tester) async {
      final controller = HarnessBuilder.buildController(hasGeoJson: true);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('監視を開始できる状態です。'), findsOneWidget);
      expect(find.text('反応距離 (Inner buffer)'), findsOneWidget);

      await _tryTakeScreenshot(binding, 'settings-form');
    });

    testWidgets('qr page shows retry UI when camera permission is denied',
        (tester) async {
      final controller = HarnessBuilder.buildController(hasGeoJson: true);
      final deniedCoordinator = HarnessPermissionCoordinator(
        gateway: const HarnessPermissionGateway(
          cameraStatusValue: PermissionStatus.denied,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: deniedCoordinator,
              scannerOverride: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('カメラ権限'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);

      await _tryTakeScreenshot(binding, 'qr-permission-error');
    });

    testWidgets('home can navigate to settings from overflow menu',
        (tester) async {
      final controller = HarnessBuilder.buildController(hasGeoJson: true);

      await tester.pumpWidget(HarnessBuilder.buildApp(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });
  });
}

Future<void> _tryTakeScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  await binding.takeScreenshot(name);
}
