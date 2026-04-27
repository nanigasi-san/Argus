import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../qr/geojson_qr_codec.dart';

typedef GeoJsonQrEncoder = Future<GeoJsonQrBundle> Function(
  GeoJsonQrEncodeInput input,
);
typedef GeoJsonFilePicker = Future<fs.XFile?> Function();
typedef QrGallerySaver = Future<void> Function(Uint8List bytes, String name);
typedef QrShareHandler = Future<void> Function(
  Uint8List bytes,
  String fileName,
  BuildContext context,
);

class QrGeneratorPage extends StatefulWidget {
  const QrGeneratorPage({
    super.key,
    this.filePicker,
    this.encoder = encodeGeoJson,
    this.gallerySaver = _saveQrToGallery,
    this.shareHandler = _shareQrImage,
  });

  final GeoJsonFilePicker? filePicker;
  final GeoJsonQrEncoder encoder;
  final QrGallerySaver gallerySaver;
  final QrShareHandler shareHandler;

  @override
  State<QrGeneratorPage> createState() => _QrGeneratorPageState();
}

class _QrGeneratorPageState extends State<QrGeneratorPage> {
  bool _isGenerating = false;
  bool _isSaving = false;
  bool _isSharing = false;
  String? _errorMessage;
  _GeneratedQr? _generatedQr;

  bool get _hasSingleQr => _generatedQr != null;

  Future<void> _selectAndGenerate() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _generatedQr = null;
    });

    try {
      final selected = await (widget.filePicker ?? _pickGeoJsonFile)();
      if (!mounted) {
        return;
      }
      if (selected == null) {
        setState(() {
          _isGenerating = false;
        });
        return;
      }

      final rawGeoJson = await selected.readAsString();
      final bundle = await widget.encoder(
        GeoJsonQrEncodeInput(
          geoJson: rawGeoJson,
          scheme: GeoJsonQrScheme.gjz1,
          enableHash: true,
          maxQrTextLength: 2500,
          eccLevel: QrErrorCorrectionLevel.quartile,
          generatePng: true,
          modulePixelSize: 8,
          quietZoneModules: 4,
        ),
      );

      if (!mounted) {
        return;
      }

      if (bundle.pngImages.length != 1) {
        setState(() {
          _isGenerating = false;
          _errorMessage = '1枚のQRに収まりません。GeoJSONを簡略化してください。';
        });
        return;
      }

      setState(() {
        _isGenerating = false;
        _generatedQr = _GeneratedQr(
          fileName: _displayFileName(selected),
          imageBytes: bundle.pngImages.single,
          info: bundle.info,
          schemeLabel: _schemeLabel(bundle.qrTexts.single),
          hashHex: bundle.hashHex,
          minimizedBytes: bundle.minimizedGeoJson.length,
          qrTextBytes: bundle.qrTexts.single.length,
        );
      });
    } on GeoJsonQrException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isGenerating = false;
        _errorMessage = 'QRコードの生成に失敗しました: ${e.message}';
      });
    } on FormatException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isGenerating = false;
        _errorMessage = 'GeoJSONの形式が正しくありません: ${e.message}';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isGenerating = false;
        _errorMessage = 'QRコードの生成中にエラーが発生しました: $e';
      });
    }
  }

  Future<void> _saveQr() async {
    final generated = _generatedQr;
    if (generated == null || _isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await widget.gallerySaver(
        generated.imageBytes,
        generated.outputBaseName,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写真に保存しました')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _shareQr() async {
    final generated = _generatedQr;
    if (generated == null || _isSharing) {
      return;
    }

    setState(() {
      _isSharing = true;
    });
    try {
      await widget.shareHandler(
        generated.imageBytes,
        '${generated.outputBaseName}.png',
        context,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('共有に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final generated = _generatedQr;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate QR code'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: _isGenerating ? null : _selectAndGenerate,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_isGenerating ? '生成中...' : 'GeoJSONを選択'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _ErrorPanel(message: _errorMessage!),
            ],
            if (generated != null) ...[
              const SizedBox(height: 20),
              _QrPreview(generated: generated),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _hasSingleQr && !_isSaving ? _saveQr : null,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt),
                      label: const Text('保存'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _hasSingleQr && !_isSharing ? _shareQr : null,
                      icon: _isSharing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share),
                      label: const Text('共有'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QrPreview extends StatelessWidget {
  const _QrPreview({required this.generated});

  final _GeneratedQr generated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hash = generated.hashHex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Image.memory(
                  generated.imageBytes,
                  key: const ValueKey('generated_qr_image'),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _InfoRow(label: 'ファイル名', value: generated.fileName),
        _InfoRow(label: 'スキーム', value: generated.schemeLabel),
        _InfoRow(label: 'GeoJSONタイプ', value: generated.info.type),
        if (generated.info.featureCount != null)
          _InfoRow(
            label: 'フィーチャ数',
            value: generated.info.featureCount.toString(),
          ),
        _InfoRow(label: '最小化サイズ', value: '${generated.minimizedBytes} bytes'),
        _InfoRow(label: 'QRテキスト長', value: '${generated.qrTextBytes} chars'),
        if (hash != null)
          _InfoRow(
            label: 'ハッシュ',
            value: hash,
            monospace: true,
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: monospace ? 'monospace' : null,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratedQr {
  const _GeneratedQr({
    required this.fileName,
    required this.imageBytes,
    required this.info,
    required this.schemeLabel,
    required this.hashHex,
    required this.minimizedBytes,
    required this.qrTextBytes,
  });

  final String fileName;
  final Uint8List imageBytes;
  final GeoJsonInfo info;
  final String schemeLabel;
  final String? hashHex;
  final int minimizedBytes;
  final int qrTextBytes;

  String get outputBaseName {
    final withoutExtension = path.basenameWithoutExtension(fileName);
    final normalized =
        withoutExtension.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final safeName = normalized.isEmpty ? 'geojson' : normalized;
    return 'argus_qr_$safeName';
  }
}

// coverage:ignore-start
// These default adapters call platform plugins. Widget tests cover the
// surrounding behavior by injecting file picker, gallery saver, and share
// handlers instead of invoking real platform channels.
Future<fs.XFile?> _pickGeoJsonFile() {
  return fs.openFile();
}

Future<void> _saveQrToGallery(Uint8List bytes, String name) async {
  var hasAccess = await Gal.hasAccess();
  if (!hasAccess) {
    hasAccess = await Gal.requestAccess();
  }
  if (!hasAccess) {
    throw Exception('写真へのアクセスが許可されていません。');
  }
  await Gal.putImageBytes(bytes, name: name);
}

Future<void> _shareQrImage(
  Uint8List bytes,
  String fileName,
  BuildContext context,
) async {
  final box = context.findRenderObject() as RenderBox?;
  final tempDir = await getTemporaryDirectory();
  final file = File(path.join(tempDir.path, fileName));
  await file.writeAsBytes(bytes, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      title: 'ARGUS GeoJSON QR code',
      files: [XFile(file.path, mimeType: 'image/png')],
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}
// coverage:ignore-end

String _displayFileName(fs.XFile file) {
  if (file.name.isNotEmpty) {
    return file.name;
  }
  return path.basename(file.path); // coverage:ignore-line
}

String _schemeLabel(String qrText) {
  final separator = qrText.indexOf(':');
  if (separator <= 0) {
    return '-';
  }
  return qrText.substring(0, separator);
}
