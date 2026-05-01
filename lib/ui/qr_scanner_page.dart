import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../platform/permission_coordinator.dart';
import '../qr/geojson_qr_codec.dart';

enum _QrScannerState {
  checkingPermission,
  preparingScanner,
  ready,
  error,
}

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({
    super.key,
    this.permissionCoordinator,
    this.scannerOverride,
    this.scannerBuilder,
    this.startScannerOverride,
    this.stopScannerOverride,
    this.disposeScannerOverride,
  });

  final PermissionCoordinator? permissionCoordinator;
  final Widget? scannerOverride;
  final Widget Function(
    BuildContext context,
    MobileScannerController? controller,
    Future<void> Function(BarcodeCapture capture) onDetect,
  )? scannerBuilder;
  final Future<void> Function()? startScannerOverride;
  final Future<void> Function()? stopScannerOverride;
  final VoidCallback? disposeScannerOverride;

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage>
    with WidgetsBindingObserver {
  late final PermissionCoordinator _permissionCoordinator =
      widget.permissionCoordinator ?? PermissionCoordinator();
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _cameraGranted = false;
  bool _showSettingsAction = false;
  bool _isStartingScanner = false;
  bool _awaitingSettingsReturn = false;
  String? _errorMessage;
  _QrScannerState _scannerState = _QrScannerState.checkingPermission;

  bool get _usesRealScanner => widget.scannerOverride == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_usesRealScanner) {
      _controller = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [BarcodeFormat.qrCode],
      );
    }
    unawaited(_prepareScanner());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.disposeScannerOverride?.call();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_usesRealScanner || !_cameraGranted || _isProcessing) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        if (_awaitingSettingsReturn) {
          _awaitingSettingsReturn = false;
          unawaited(_prepareScanner());
        } else {
          unawaited(_resumeScanner());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_stopScanner());
    }
  }

  Future<void> _prepareScanner() async {
    if (mounted) {
      setState(() {
        _scannerState = _QrScannerState.checkingPermission;
        _errorMessage = null;
      });
    }

    final cameraPermission =
        await _permissionCoordinator.ensureCameraPermission();
    if (!mounted) {
      return;
    }

    if (!cameraPermission.isGranted) {
      setState(() {
        _cameraGranted = false;
        _scannerState = _QrScannerState.error;
        _showSettingsAction = cameraPermission.requiresManualSettings;
        _errorMessage = cameraPermission.message;
      });
      return;
    }

    _cameraGranted = true;
    _showSettingsAction = false;
    await _startScanner();
  }

  Future<void> _startScanner() async {
    if (!mounted) {
      return;
    }
    if (!_usesRealScanner) {
      setState(() {
        _scannerState = _QrScannerState.ready;
      });
      return;
    }
    if (_controller == null || _isStartingScanner) {
      return;
    }

    setState(() {
      _scannerState = _QrScannerState.preparingScanner;
      _errorMessage = null;
    });
    _isStartingScanner = true;

    try {
      await _startScannerController();
      if (!mounted) {
        return;
      }
      setState(() {
        _scannerState = _QrScannerState.ready;
      });
    } on MobileScannerException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _scannerState = _QrScannerState.error;
        _errorMessage = _scannerErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _scannerState = _QrScannerState.error;
        _errorMessage = 'QR スキャナを開始できませんでした。時間をおいて再試行してください。\n$e';
      });
    } finally {
      _isStartingScanner = false;
    }
  }

  Future<void> _resumeScanner() async {
    if (!mounted || !_cameraGranted || _scannerState == _QrScannerState.error) {
      return;
    }
    await _startScanner();
  }

  Future<void> _retry() async {
    if (!_cameraGranted) {
      await _prepareScanner();
      return;
    }
    await _startScanner();
  }

  Future<void> _openSettingsAndRefresh() async {
    _awaitingSettingsReturn = true;
    await _permissionCoordinator.openSettings();
  }

  Future<void> _startScannerController() {
    return widget.startScannerOverride?.call() ?? _controller!.start();
  }

  Future<void> _stopScanner() {
    return widget.stopScannerOverride?.call() ??
        _controller?.stop() ??
        Future<void>.value();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      return;
    }

    final qrText = barcodes.first.rawValue;
    if (qrText == null || qrText.isEmpty) {
      return;
    }

    final appController = Provider.of<AppController>(context, listen: false);

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    await _stopScanner();

    try {
      if (!isSupportedGeoJsonQrText(qrText)) {
        setState(() {
          _errorMessage = 'GeoJSON QR コードではありません。';
          _isProcessing = false;
        });
        unawaited(_resumeScanner());
        return;
      }

      final loaded = await appController.reloadGeoJsonFromQr(qrText);

      if (mounted && loaded) {
        Navigator.of(context).pop();
      } else if (mounted && !loaded) {
        setState(() {
          _errorMessage =
              appController.lastErrorMessage ?? 'GeoJSON の読込に失敗しました。';
          _isProcessing = false;
        });
        unawaited(_resumeScanner());
      }
    } on GeoJsonQrException catch (e) {
      setState(() {
        _errorMessage = 'QR コードの復元に失敗しました: ${e.message}';
        _isProcessing = false;
      });
      unawaited(_resumeScanner());
    } catch (e) {
      setState(() {
        _errorMessage = 'QR コードの処理中にエラーが発生しました: $e';
        _isProcessing = false;
      });
      unawaited(_resumeScanner());
    }
  }

  String _scannerErrorMessage(MobileScannerException error) {
    final message = error.toString().toLowerCase();
    if (message.contains('permission')) {
      _showSettingsAction = true;
      return 'カメラ権限を確認できませんでした。アプリ設定から許可してください。';
    }
    if (message.contains('mlkit') ||
        message.contains('barcode') ||
        message.contains('download') ||
        message.contains('google play')) {
      return 'QR スキャナを初期化できませんでした。アプリを再起動して再試行してください。';
    }
    return 'QR スキャナを開始できませんでした。再試行してください。';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('QRコードを読み込む'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.scannerBuilder != null
                ? widget.scannerBuilder!(context, _controller, _handleBarcode)
                : _usesRealScanner
                    ? (_controller == null
                        ? const ColoredBox(color: Colors.black)
                        : MobileScanner(
                            controller: _controller!,
                            onDetect: _handleBarcode,
                          ))
                    : (widget.scannerOverride ?? const SizedBox.shrink()),
          ),
          if (_scannerState != _QrScannerState.ready)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.88),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _ScannerStatusPanel(
                      state: _scannerState,
                      message: _errorMessage,
                      showSettingsAction: _showSettingsAction,
                      onRetry: _retry,
                      onOpenSettings: _openSettingsAndRefresh,
                    ),
                  ),
                ),
              ),
            ),
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'QRコードを処理しています...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          if (_errorMessage != null && _scannerState == _QrScannerState.ready)
            Positioned(
              left: 12,
              right: 12,
              bottom: bottomInset + 12,
              child: Material(
                color: Colors.red.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                          });
                        },
                        child: const Text('閉じる'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScannerStatusPanel extends StatelessWidget {
  const _ScannerStatusPanel({
    required this.state,
    required this.message,
    required this.showSettingsAction,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final _QrScannerState state;
  final String? message;
  final bool showSettingsAction;
  final Future<void> Function() onRetry;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _QrScannerState.checkingPermission:
      case _QrScannerState.preparingScanner:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'QR スキャナを準備しています...',
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case _QrScannerState.ready:
        return const SizedBox.shrink();
      case _QrScannerState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner, color: Colors.white, size: 56),
            const SizedBox(height: 16),
            Text(
              message ?? 'QR スキャナを利用できません。',
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('再試行'),
            ),
            if (showSettingsAction) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onOpenSettings,
                child: const Text('アプリ設定を開く'),
              ),
            ],
          ],
        );
    }
  }
}
