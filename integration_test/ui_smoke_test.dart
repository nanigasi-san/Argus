import 'dart:io';

import 'package:argus/garmin/garmin_course_payload.dart';
import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/platform/garmin_transfer_client.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/theme/app_theme.dart';
import 'package:argus/ui/qr_scanner_page.dart';
import 'package:argus/ui/settings_page.dart';
import 'package:argus/ui/garmin_transfer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'support/app_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Mobile UI smoke', () {
    setUpAll(() async {
      await binding.convertFlutterSurfaceToImage();
    });

    testWidgets(
        'Garmin QR image uses native analysis and preserves the phone course',
        (tester) async {
      final bundle = await encodeGeoJson(const GeoJsonQrEncodeInput(
        geoJson:
            '{"type":"FeatureCollection","features":[{"type":"Feature","properties":{},"geometry":{"type":"Polygon","coordinates":[[[140,36],[140.001,36],[140,36.001],[140,36]]]}}]}',
        sourceFileName: 'image_course.geojson',
        scheme: GeoJsonQrScheme.agz1,
        generatePng: true,
      ));
      final image =
          File('${(await getTemporaryDirectory()).path}/argus_e2e_qr.png');
      await image.writeAsBytes(bundle.pngImages.single);
      final controller = HarnessBuilder.buildController(
        hasGeoJson: true,
        fileManager: _QrImageFileManager(image.path),
        permissionCoordinator: HarnessPermissionCoordinator(
          gateway: const HarnessPermissionGateway(
              cameraStatusValue: PermissionStatus.denied),
        ),
      );
      final phoneModel = controller.geoModel;
      addTearDown(() async {
        controller.dispose();
        if (await image.exists()) await image.delete();
      });
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const GarminTransferPage(client: _ScreenshotGarminClient())),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('QRで復元'));
      await tester.pumpAndSettle();
      expect(find.text('QR画像を選択'), findsOneWidget);
      await _tryTakeScreenshot(binding, 'garmin-qr-image-selection');
      await tester.tap(find.text('QR画像を選択'));
      const isIosSimulator = bool.fromEnvironment('ARGUS_IOS_SIMULATOR');
      // Image analysis is performed by the OS plugin, outside Flutter frames.
      for (var i = 0;
          i < 100 &&
              find.text('image_course').evaluate().isEmpty &&
              find.textContaining('iOS Simulator').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(identical(controller.geoModel, phoneModel), isTrue);
      if (isIosSimulator) {
        // mobile_scanner explicitly disables Vision image analysis in Simulator.
        expect(find.textContaining('iOS Simulator'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('argus'), findsOneWidget);
        expect(find.text('GARMINへ転送しました'), findsNothing);
        return;
      }
      expect(find.text('image_course'), findsOneWidget);
      await tester.ensureVisible(find.text('GARMINに送信'));
      await tester.tap(find.text('GARMINに送信'));
      await tester.pumpAndSettle();
      expect(find.text('GARMINへ転送しました'), findsOneWidget);
    });

    testWidgets('Garmin transfer before and after acknowledged send',
        (tester) async {
      final controller = HarnessBuilder.buildController();
      controller.debugSeed(
          geoJson: GeoModel([
        GeoPolygon(points: const [
          LatLng(35, 139),
          LatLng(35, 139.001),
          LatLng(35.001, 139),
        ]),
      ]));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const GarminTransferPage(client: _ScreenshotGarminClient()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'GARMINに送信'),
            )
            .onPressed,
        isNotNull,
      );
      await _tryTakeScreenshot(binding, 'garmin-transfer-option1-before');

      await tester.ensureVisible(find.text('GARMINに送信'));
      await tester.tap(find.text('GARMINに送信'));
      await tester.pumpAndSettle();
      expect(find.text('GARMINへ転送しました'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _tryTakeScreenshot(binding, 'garmin-transfer-option1-after');
    });

    testWidgets('entry screen opens the existing Garmin transfer flow',
        (tester) async {
      final controller = HarnessBuilder.buildController();

      await tester.pumpWidget(HarnessBuilder.buildApp(controller));
      await tester.pumpAndSettle();
      expect(find.text('どちらで利用しますか？'), findsOneWidget);
      await _tryTakeScreenshot(binding, 'usage-mode-selection');

      await tester.tap(find.byKey(const Key('garminModeChoice')));
      await tester.tap(find.byKey(const Key('usageModeNextButton')));
      await tester.pumpAndSettle();

      expect(find.byType(GarminTransferPage), findsOneWidget);
      expect(find.text('GARMINに送る'), findsOneWidget);
      await _tryTakeScreenshot(binding, 'garmin-transfer-entry');
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
      await tester.tap(find.byKey(const Key('usageModeNextButton')));
      await tester.pumpAndSettle();

      expect(find.text('監視開始前に位置情報の設定が必要です'), findsOneWidget);
      expect(find.text('監視開始前に設定する'), findsOneWidget);
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
      await tester.tap(find.byKey(const Key('usageModeNextButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('監視開始前に設定する'));
      await tester.pumpAndSettle();

      expect(find.text('バックグラウンド位置情報の開示'), findsOneWidget);
      expect(
        find.text(
          defaultTargetPlatform == TargetPlatform.iOS
              ? '続ける'
              : '同意して位置情報の設定へ進む',
        ),
        findsOneWidget,
      );

      await _tryTakeScreenshot(binding, 'background-location-disclosure');
    });

    testWidgets('settings page renders the monitoring card and form',
        (tester) async {
      final controller = HarnessBuilder.buildController(hasGeoJson: true);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('設定'), findsOneWidget);
      expect(find.text('監視を開始できる状態です。'), findsOneWidget);
      expect(find.text('境界バッファ距離'), findsOneWidget);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await tester.scrollUntilVisible(
          find.byKey(const Key('alarmPreviewButton')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('警告音をテスト'), findsOneWidget);
      }

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
          debugShowCheckedModeBanner: false,
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
      await tester.tap(find.byKey(const Key('usageModeNextButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('設定'));
      await tester.pumpAndSettle();

      expect(find.text('設定'), findsWidgets);
    });
  });
}

class _QrImageFileManager extends HarnessFileManager {
  _QrImageFileManager(this.imagePath)
      : super(config: HarnessBuilder.createConfig());
  final String imagePath;
  @override
  Future<XFile?> pickQrImageFile() async => XFile(imagePath);
}

class _ScreenshotGarminClient extends GarminTransferClient {
  const _ScreenshotGarminClient();

  @override
  Future<List<GarminDevice>> getDevices() async => const [
        GarminDevice(id: 'fr55-mock', name: 'ForeAthlete 55', connected: true),
      ];

  @override
  Future<GarminTransferResult> sendCourse(
      GarminDevice device, GarminCoursePayload payload) async {
    return const GarminTransferResult(
      deviceName: 'ForeAthlete 55',
      elapsedMs: 1480,
    );
  }
}

Future<void> _tryTakeScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  await binding.takeScreenshot(name);
}
