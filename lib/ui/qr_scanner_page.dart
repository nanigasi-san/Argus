import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../qr/geojson_qr_codec.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final qrText = barcodes.first.rawValue;
    if (qrText == null || qrText.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // QRテキストがgjb1:で始まることを確認
      if (!qrText.startsWith('gjb1:')) {
        setState(() {
          _errorMessage = 'Invalid QR code format. Expected gjb1: scheme.';
          _isProcessing = false;
        });
        return;
      }

      // AppControllerでGeoJSONを読み込み
      final appController = Provider.of<AppController>(context, listen: false);
      await appController.reloadGeoJsonFromQr(qrText);

      // 成功時は前の画面に戻る
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on GeoJsonQrException catch (e) {
      setState(() {
        _errorMessage = 'Failed to decode QR code: ${e.message}';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
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
                      'Processing QR code...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          if (_errorMessage != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.red.withValues(alpha: 0.9),
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
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
