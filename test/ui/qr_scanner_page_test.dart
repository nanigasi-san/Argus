import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/enums/mobile_scanner_error_code.dart';
import 'package:provider/provider.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/io/config.dart';
import 'package:argus/io/file_manager.dart';
import 'package:argus/io/logger.dart';
import 'package:argus/platform/location_service.dart';
import 'package:argus/platform/notifier.dart';
import 'package:argus/platform/permission_coordinator.dart';
import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:argus/state_machine/state_machine.dart';
import 'package:argus/ui/qr_scanner_page.dart';
import 'package:permission_handler/permission_handler.dart';

import '../support/notifier_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QrScannerPage', () {
    testWidgets('displays scanner page with app bar',
        (WidgetTester tester) async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: _FakeLocationService(),
        fileManager: _FakeFileManager(config: config),
        logger: _FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerOverride: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // AppBarのタイトルを確認
      expect(find.text('Scan QR Code'), findsOneWidget);
    });

    testWidgets('can navigate back', (WidgetTester tester) async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: _FakeLocationService(),
        fileManager: _FakeFileManager(config: config),
        logger: _FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppController>.value(
              value: controller,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => QrScannerPage(
                          permissionCoordinator: _FakePermissionCoordinator(),
                          scannerOverride:
                              const ColoredBox(color: Colors.black),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Scanner'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // スキャナーページを開く
      await tester.tap(find.text('Open Scanner'));
      await tester.pumpAndSettle();

      expect(find.text('Scan QR Code'), findsOneWidget);

      // 戻るボタンをタップ
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Open Scanner'), findsOneWidget);
    });

    testWidgets('shows permission error when camera is denied',
        (WidgetTester tester) async {
      final config = _testConfig();
      final controller = AppController(
        stateMachine: StateMachine(config: config),
        locationService: _FakeLocationService(),
        fileManager: _FakeFileManager(config: config),
        logger: _FakeEventLogger(),
        notifier: Notifier(
          notificationsClient: FakeLocalNotificationsClient(),
          alarmPlayer: FakeAlarmPlayer(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _DeniedCameraPermissionCoordinator(),
              scannerOverride: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('カメラ権限'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('shows settings button when camera requires manual settings',
        (WidgetTester tester) async {
      final controller = _buildController();
      final coordinator = _SequenceCameraPermissionCoordinator(
        states: const [
          CameraPermissionState(status: PermissionStatus.permanentlyDenied),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: coordinator,
              scannerOverride: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('アプリ設定を開く'));
      await tester.pumpAndSettle();

      expect(find.text('アプリ設定を開く'), findsOneWidget);
      expect(coordinator.openSettingsCount, 1);
    });

    testWidgets('retry after permission grant hides error panel',
        (WidgetTester tester) async {
      final controller = _buildController();
      final coordinator = _SequenceCameraPermissionCoordinator(
        states: const [
          CameraPermissionState(status: PermissionStatus.denied),
          CameraPermissionState(status: PermissionStatus.granted),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: coordinator,
              scannerOverride: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('再試行'), findsOneWidget);

      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(find.text('再試行'), findsNothing);
    });

    testWidgets('invalid QR shows dismissible error banner',
        (WidgetTester tester) async {
      final controller = _RecordingQrController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerOverride: const SizedBox.shrink(),
              scannerBuilder: (context, controller, onDetect) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () => onDetect(
                      const BarcodeCapture(
                        barcodes: [Barcode(rawValue: 'not-a-geojson-qr')],
                      ),
                    ),
                    child: const Text('Emit Invalid'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Emit Invalid'));
      await tester.pumpAndSettle();

      expect(find.text('GeoJSON QR コードではありません。'), findsOneWidget);
      expect(controller.scannedTexts, isEmpty);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('GeoJSON QR コードではありません。'), findsNothing);
    });

    testWidgets('valid QR displays controller error when load fails',
        (WidgetTester tester) async {
      final controller = _RecordingQrController()
        ..loadedResult = false
        ..reloadErrorMessage = 'GeoJSON の読込に失敗しました。';

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerOverride: const SizedBox.shrink(),
              scannerBuilder: (context, scannerController, onDetect) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () => onDetect(
                      const BarcodeCapture(
                        barcodes: [Barcode(rawValue: 'gjb1:test')],
                      ),
                    ),
                    child: const Text('Emit Valid'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Emit Valid'));
      await tester.pumpAndSettle();

      expect(controller.scannedTexts, ['gjb1:test']);
      expect(find.text('GeoJSON の読込に失敗しました。'), findsOneWidget);
    });

    testWidgets('valid gjz1 QR is accepted by scanner',
        (WidgetTester tester) async {
      final controller = _RecordingQrController()
        ..loadedResult = false
        ..reloadErrorMessage = 'GeoJSON の読込に失敗しました。';

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerOverride: const SizedBox.shrink(),
              scannerBuilder: (context, scannerController, onDetect) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () => onDetect(
                      const BarcodeCapture(
                        barcodes: [Barcode(rawValue: 'gjz1:test')],
                      ),
                    ),
                    child: const Text('Emit GJZ1'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Emit GJZ1'));
      await tester.pumpAndSettle();

      expect(controller.scannedTexts, ['gjz1:test']);
      expect(find.text('GeoJSON の読込に失敗しました。'), findsOneWidget);
    });

    testWidgets('successful QR load pops scanner route',
        (WidgetTester tester) async {
      final controller = _RecordingQrController()..loadedResult = true;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ChangeNotifierProvider<AppController>.value(
                        value: controller,
                        child: QrScannerPage(
                          permissionCoordinator: _FakePermissionCoordinator(),
                          scannerOverride: const SizedBox.shrink(),
                          scannerBuilder:
                              (context, scannerController, onDetect) {
                            return Center(
                              child: ElevatedButton(
                                onPressed: () => onDetect(
                                  const BarcodeCapture(
                                    barcodes: [
                                      Barcode(rawValue: 'gjb1:success')
                                    ],
                                  ),
                                ),
                                child: const Text('Emit Success'),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open Scanner'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Scanner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emit Success'));
      await tester.pumpAndSettle();

      expect(controller.scannedTexts, ['gjb1:success']);
      expect(find.text('Open Scanner'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsNothing);
    });

    testWidgets('real scanner lifecycle restarts on resume and stops on pause',
        (WidgetTester tester) async {
      final controller = _buildController();
      var startCount = 0;
      var stopCount = 0;
      var disposeCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {
                startCount += 1;
              },
              stopScannerOverride: () async {
                stopCount += 1;
              },
              disposeScannerOverride: () {
                disposeCount += 1;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());

      expect(startCount, 2);
      expect(stopCount, 1);
      expect(disposeCount, 1);
    });

    testWidgets('returning from settings re-prepares scanner on resume',
        (WidgetTester tester) async {
      final controller = _buildController();
      final coordinator = _SequenceCameraPermissionCoordinator(
        states: const [
          CameraPermissionState(status: PermissionStatus.granted),
          CameraPermissionState(status: PermissionStatus.granted),
        ],
      );
      var startCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: coordinator,
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {
                startCount += 1;
                if (startCount == 1) {
                  throw const MobileScannerException(
                    errorCode: MobileScannerErrorCode.controllerUninitialized,
                    errorDetails:
                        MobileScannerErrorDetails(message: 'permission denied'),
                  );
                }
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('アプリ設定を開く'), findsOneWidget);

      await tester.tap(find.text('アプリ設定を開く'));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(startCount, 2);
      expect(coordinator.ensureCameraPermissionCount, 2);
      expect(find.text('アプリ設定を開く'), findsNothing);
    });

    testWidgets('hidden and detached lifecycle states stop scanner',
        (WidgetTester tester) async {
      final controller = _buildController();
      var stopCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {},
              stopScannerOverride: () async {
                stopCount += 1;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();

      expect(stopCount, 2);
    });

    testWidgets('real scanner without stop override handles hidden state',
        (WidgetTester tester) async {
      final controller = _buildController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      expect(find.text('Scan QR Code'), findsOneWidget);
    });

    testWidgets('scanner permission start error offers settings action',
        (WidgetTester tester) async {
      final controller = _buildController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {
                throw const MobileScannerException(
                  errorCode: MobileScannerErrorCode.controllerUninitialized,
                  errorDetails:
                      MobileScannerErrorDetails(message: 'permission denied'),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('アプリ設定から許可してください'), findsOneWidget);
      expect(find.text('アプリ設定を開く'), findsOneWidget);
    });

    testWidgets('scanner mlkit start error shows retry guidance',
        (WidgetTester tester) async {
      final controller = _buildController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {
                throw const MobileScannerException(
                  errorCode: MobileScannerErrorCode.controllerInitializing,
                  errorDetails: MobileScannerErrorDetails(
                    message: 'mlkit download required',
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('ネットワークに接続した状態'), findsOneWidget);
    });

    testWidgets('scanner barcode start error shows retry guidance',
        (WidgetTester tester) async {
      final controller = _buildController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {
                throw const MobileScannerException(
                  errorCode: MobileScannerErrorCode.controllerInitializing,
                  errorDetails: MobileScannerErrorDetails(
                    message: 'barcode engine unavailable',
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('ネットワークに接続した状態'), findsOneWidget);
    });

    testWidgets('scanner download start error shows retry guidance',
        (WidgetTester tester) async {
      final controller = _buildController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {
                throw const MobileScannerException(
                  errorCode: MobileScannerErrorCode.controllerInitializing,
                  errorDetails: MobileScannerErrorDetails(
                    message: 'download required',
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('ネットワークに接続した状態'), findsOneWidget);
    });

    testWidgets('scanner google play start error shows retry guidance',
        (WidgetTester tester) async {
      final controller = _buildController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {
                throw const MobileScannerException(
                  errorCode: MobileScannerErrorCode.controllerInitializing,
                  errorDetails: MobileScannerErrorDetails(
                    message: 'google play services unavailable',
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('ネットワークに接続した状態'), findsOneWidget);
    });

    testWidgets('scanner generic start error shows generic failure message',
        (WidgetTester tester) async {
      final controller = _buildController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {
                throw Exception('unexpected');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('QR スキャナを開始できませんでした'), findsWidgets);
    });

    testWidgets(
        'retry in error state restarts scanner when camera already granted',
        (WidgetTester tester) async {
      final controller = _buildController();
      var startCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerBuilder: (context, scannerController, onDetect) =>
                  const ColoredBox(color: Colors.black),
              startScannerOverride: () async {
                startCount += 1;
                if (startCount == 1) {
                  throw Exception('unexpected');
                }
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('再試行'), findsOneWidget);

      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(startCount, 2);
      expect(find.text('再試行'), findsNothing);
    });

    testWidgets('empty or null barcode payload is ignored',
        (WidgetTester tester) async {
      final controller = _RecordingQrController();
      var emitNull = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerOverride: const SizedBox.shrink(),
              scannerBuilder: (context, scannerController, onDetect) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () => onDetect(
                      BarcodeCapture(
                        barcodes: emitNull
                            ? const [Barcode(rawValue: null)]
                            : const [],
                      ),
                    ),
                    child: const Text('Emit Empty'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Emit Empty'));
      await tester.pumpAndSettle();
      emitNull = true;
      await tester.tap(find.text('Emit Empty'));
      await tester.pumpAndSettle();

      expect(controller.scannedTexts, isEmpty);
      expect(find.text('Dismiss'), findsNothing);
    });

    testWidgets('controller exception while loading QR is surfaced',
        (WidgetTester tester) async {
      final controller = _RecordingQrController()
        ..reloadError = Exception('boom');

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerOverride: const SizedBox.shrink(),
              scannerBuilder: (context, scannerController, onDetect) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () => onDetect(
                      const BarcodeCapture(
                        barcodes: [Barcode(rawValue: 'gjb1:error')],
                      ),
                    ),
                    child: const Text('Emit Error'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Emit Error'));
      await tester.pumpAndSettle();

      expect(find.textContaining('QR コードの処理中にエラーが発生しました'), findsOneWidget);
    });

    testWidgets('GeoJsonQrException while loading QR is surfaced',
        (WidgetTester tester) async {
      final controller = _RecordingQrController()
        ..reloadError = DecodeFailedException('bad payload');

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              scannerOverride: const SizedBox.shrink(),
              scannerBuilder: (context, scannerController, onDetect) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () => onDetect(
                      const BarcodeCapture(
                        barcodes: [Barcode(rawValue: 'gjb1:error')],
                      ),
                    ),
                    child: const Text('Emit Decode Error'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Emit Decode Error'));
      await tester.pumpAndSettle();

      expect(find.textContaining('QR コードの復元に失敗しました'), findsOneWidget);
    });

    testWidgets('real scanner branch renders MobileScanner widget',
        (WidgetTester tester) async {
      final controller = _buildController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppController>.value(
            value: controller,
            child: QrScannerPage(
              permissionCoordinator: _FakePermissionCoordinator(),
              startScannerOverride: () async {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(MobileScanner), findsOneWidget);
    });
  });
}

AppConfig _testConfig() {
  return AppConfig(
    innerBufferM: 5,
    leaveConfirmSamples: 1,
    leaveConfirmSeconds: 1,
    gpsAccuracyBadMeters: 50,
    sampleIntervalS: {'fast': 1},
    sampleDistanceM: {'fast': 1},
    screenWakeOnLeave: false,
    alarmVolume: 1.0,
  );
}

class _FakeFileManager extends FileManager {
  _FakeFileManager({required this.config});

  final AppConfig config;

  @override
  Future<AppConfig> readConfig() async => config;
}

class _FakeEventLogger extends EventLogger {
  _FakeEventLogger() : super();
}

class _FakeLocationService implements LocationService {
  _FakeLocationService();

  @override
  Future<LocationServiceStartResult> start(AppConfig config) async {
    return const LocationServiceStartResult.started();
  }

  @override
  Future<void> stop() async {}

  @override
  Stream<LocationFix> get stream => const Stream.empty();
}

class _FakePermissionGateway implements PermissionGateway {
  @override
  Future<PermissionStatus> cameraStatus() async => PermissionStatus.granted;

  @override
  Future<PermissionStatus> locationAlwaysStatus() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> locationWhenInUseStatus() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> notificationStatus() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> requestCamera() async => PermissionStatus.granted;

  @override
  Future<PermissionStatus> requestLocationAlways() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> requestLocationWhenInUse() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> requestNotification() async =>
      PermissionStatus.granted;
}

class _FakePermissionCoordinator extends PermissionCoordinator {
  _FakePermissionCoordinator()
      : super(
          gateway: _FakePermissionGateway(),
          openSettings: () async => true,
          openLocationSettings: () async => true,
          locationServicesEnabled: () async => true,
        );
}

class _DeniedCameraPermissionGateway extends _FakePermissionGateway {
  @override
  Future<PermissionStatus> cameraStatus() async => PermissionStatus.denied;

  @override
  Future<PermissionStatus> requestCamera() async => PermissionStatus.denied;
}

class _DeniedCameraPermissionCoordinator extends PermissionCoordinator {
  _DeniedCameraPermissionCoordinator()
      : super(
          gateway: _DeniedCameraPermissionGateway(),
          openSettings: () async => true,
          openLocationSettings: () async => true,
          locationServicesEnabled: () async => true,
        );
}

AppController _buildController() {
  final config = _testConfig();
  return AppController(
    stateMachine: StateMachine(config: config),
    locationService: _FakeLocationService(),
    fileManager: _FakeFileManager(config: config),
    logger: _FakeEventLogger(),
    notifier: Notifier(
      notificationsClient: FakeLocalNotificationsClient(),
      alarmPlayer: FakeAlarmPlayer(),
    ),
  );
}

class _SequenceCameraPermissionCoordinator extends PermissionCoordinator {
  _SequenceCameraPermissionCoordinator({required this.states});

  final List<CameraPermissionState> states;
  int _index = 0;
  int openSettingsCount = 0;
  int ensureCameraPermissionCount = 0;

  @override
  Future<CameraPermissionState> ensureCameraPermission({
    bool openSettingsIfNeeded = false,
  }) async {
    ensureCameraPermissionCount += 1;
    final current = states[_index < states.length ? _index : states.length - 1];
    if (_index < states.length - 1) {
      _index += 1;
    }
    return current;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCount += 1;
    return true;
  }
}

class _RecordingQrController extends AppController {
  _RecordingQrController()
      : super(
          stateMachine: StateMachine(config: _testConfig()),
          locationService: _FakeLocationService(),
          fileManager: _FakeFileManager(config: _testConfig()),
          logger: _FakeEventLogger(),
          notifier: Notifier(
            notificationsClient: FakeLocalNotificationsClient(),
            alarmPlayer: FakeAlarmPlayer(),
          ),
        ) {
    debugSeed(
      config: _testConfig(),
      permissionState: const MonitoringPermissionState(
        notificationStatus: PermissionStatus.granted,
        locationWhenInUseStatus: PermissionStatus.granted,
        locationAlwaysStatus: PermissionStatus.granted,
        locationServicesEnabled: true,
      ),
    );
  }

  final List<String> scannedTexts = <String>[];
  bool loadedResult = true;
  String? reloadErrorMessage;
  Object? reloadError;

  @override
  Future<bool> reloadGeoJsonFromQr(String qrText) async {
    scannedTexts.add(qrText);
    if (reloadError != null) {
      throw reloadError!;
    }
    return loadedResult;
  }

  @override
  String? get lastErrorMessage => reloadErrorMessage;
}
