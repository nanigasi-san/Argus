import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:brotli/brotli.dart' as brotli;
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

/// 入力GeoJSONをQRへ変換する際の設定値。
class GeoJsonQrEncodeInput {
  const GeoJsonQrEncodeInput({
    required this.geoJson,
    this.enableHash = true,
    this.maxQrTextLength = 2500,
    this.eccLevel = QrErrorCorrectionLevel.quartile,
    this.generatePng = true,
    this.modulePixelSize = 8,
    this.quietZoneModules = 4,
  })  : assert(maxQrTextLength > 0, 'maxQrTextLength must be positive'),
        assert(modulePixelSize > 0, 'modulePixelSize must be positive'),
        assert(quietZoneModules >= 0, 'quietZoneModules must be >= 0');

  final String geoJson;
  final bool enableHash;
  final int maxQrTextLength;
  final QrErrorCorrectionLevel eccLevel;
  final bool generatePng;
  final int modulePixelSize;
  final int quietZoneModules;
}

/// QRテキストをGeoJSONへ復元する際の設定値。
class GeoJsonQrDecodeInput {
  const GeoJsonQrDecodeInput({
    required this.qrTexts,
    this.verifyHash = true,
  });

  final List<String> qrTexts;
  final bool verifyHash;
}

/// GeoJSONエンコード結果の束。
class GeoJsonQrBundle {
  GeoJsonQrBundle({
    required List<String> qrTexts,
    required List<Uint8List> pngImages,
    required this.minimizedGeoJson,
    required this.hashHex,
    required this.info,
  })  : qrTexts = List.unmodifiable(qrTexts),
        pngImages = List.unmodifiable(pngImages);

  final List<String> qrTexts;
  final List<Uint8List> pngImages;
  final String minimizedGeoJson;
  final String? hashHex;
  final GeoJsonInfo info;

  int get chunkCount => qrTexts.length;
  bool get isSplit => qrTexts.length > 1;
}

/// GeoJSONの概要情報。
class GeoJsonInfo {
  const GeoJsonInfo({required this.type, this.featureCount});

  final String type;
  final int? featureCount;
}

/// 共通の例外クラス。
abstract class GeoJsonQrException implements Exception {
  GeoJsonQrException(this.code, this.message, [this.cause]);

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => '$code: $message${cause != null ? ' ($cause)' : ''}';
}

class GeoJsonValidationException extends GeoJsonQrException {
  GeoJsonValidationException(String message, [Object? cause])
      : super('E_INVALID_GEOJSON', message, cause);
}

class CompressFailedException extends GeoJsonQrException {
  CompressFailedException(String message, [Object? cause])
      : super('E_COMPRESS_FAILED', message, cause);
}

class DecompressFailedException extends GeoJsonQrException {
  DecompressFailedException(String message, [Object? cause])
      : super('E_DECOMPRESS_FAILED', message, cause);
}

class DecodeFailedException extends GeoJsonQrException {
  DecodeFailedException(String message, [Object? cause])
      : super('E_DECODE_FAILED', message, cause);
}

class UnsupportedSchemeException extends GeoJsonQrException {
  UnsupportedSchemeException(String message)
      : super('E_UNSUPPORTED_SCHEME', message);
}

class ChunkMismatchException extends GeoJsonQrException {
  ChunkMismatchException(String message) : super('E_CHUNK_MISMATCH', message);
}

class HashMismatchException extends GeoJsonQrException {
  HashMismatchException(String message) : super('E_HASH_MISMATCH', message);
}

class PayloadTooLargeException extends GeoJsonQrException {
  PayloadTooLargeException(String message)
      : super('E_PAYLOAD_TOO_LARGE', message);
}

class QrGenerationException extends GeoJsonQrException {
  QrGenerationException(String message, [Object? cause])
      : super('E_QR_GENERATION', message, cause);
}

/// QR誤り訂正レベル。
enum QrErrorCorrectionLevel {
  low,
  medium,
  quartile,
  high,
}

/// GeoJSON文字列をQRテキスト(とPNG)へ変換する。
Future<GeoJsonQrBundle> encodeGeoJson(GeoJsonQrEncodeInput input) async {
  final minifyResult = minifyGeoJson(input.geoJson);
  final minimizedBytes =
      Uint8List.fromList(utf8.encode(minifyResult.minimized));
  final compressedBytes = await brotliCompress(minimizedBytes);
  final payload = base64UrlEncodeNoPad(compressedBytes);
  final hashHex = input.enableHash ? computeSha256Hex(minimizedBytes) : null;

  var qrTexts = _buildQrTexts(payload, hashHex, input.maxQrTextLength);
  var pngImages = <Uint8List>[];

  if (input.generatePng) {
    var retriedSplit = false;
    while (true) {
      try {
        pngImages = [
          for (final text in qrTexts)
            generateQrPng(
              text,
              input.eccLevel,
              modulePixelSize: input.modulePixelSize,
              quietZoneModules: input.quietZoneModules,
            ),
        ];
        break;
      } on PayloadTooLargeException catch (e) {
        if (qrTexts.length == 1 && !retriedSplit) {
          retriedSplit = true;
          qrTexts = buildGjB1pTexts(
            payload,
            hash: hashHex,
            maxLength: input.maxQrTextLength,
          );
          continue;
        }
        throw QrGenerationException(e.message, e);
      }
    }
  }

  return GeoJsonQrBundle(
    qrTexts: qrTexts,
    pngImages: pngImages,
    minimizedGeoJson: minifyResult.minimized,
    hashHex: hashHex,
    info: minifyResult.info,
  );
}

/// QRテキストからGeoJSON文字列を復元する。
Future<String> decodeGeoJson(GeoJsonQrDecodeInput input) async {
  final normalized = input.qrTexts
      .map((e) => e.trim())
      .where((element) => element.isNotEmpty)
      .toList(growable: false);

  if (normalized.isEmpty) {
    throw UnsupportedSchemeException('No QR text supplied');
  }

  final payload = _parseGjB1Payload(normalized);
  final compressedBytes = base64UrlDecodeNoPad(payload.payload);
  final minimizedBytes = brotliDecompress(compressedBytes);
  final minimized = utf8.decode(minimizedBytes);

  validateGeoJsonStructure(jsonDecode(minimized));

  if (input.verifyHash && payload.hashHex != null) {
    final currentHash = computeSha256Hex(minimizedBytes);
    if (!_constantTimeEquals(payload.hashHex!, currentHash)) {
      throw HashMismatchException('Hash mismatch detected');
    }
  }

  return minimized;
}

/// GeoJSON最小化と検証。
GeoJsonMinifyResult minifyGeoJson(String input) {
  try {
    final dynamic decoded = jsonDecode(input);
    final info = validateGeoJsonStructure(decoded);
    final minimized = jsonEncode(decoded);
    return GeoJsonMinifyResult(minimized, info);
  } on GeoJsonQrException {
    rethrow;
  } on FormatException catch (e) {
    throw GeoJsonValidationException('Invalid JSON format', e);
  }
}

class GeoJsonMinifyResult {
  const GeoJsonMinifyResult(this.minimized, this.info);

  final String minimized;
  final GeoJsonInfo info;
}

GeoJsonInfo validateGeoJsonStructure(dynamic decoded) {
  if (decoded is! Map<String, dynamic>) {
    throw GeoJsonValidationException('GeoJSON root must be an object');
  }
  final type = decoded['type'];
  if (type is! String) {
    throw GeoJsonValidationException('GeoJSON must contain a string "type"');
  }

  const allowed = <String>{
    'FeatureCollection',
    'Feature',
    'GeometryCollection',
    'Point',
    'LineString',
    'Polygon',
    'MultiPoint',
    'MultiLineString',
    'MultiPolygon',
  };

  if (!allowed.contains(type)) {
    throw GeoJsonValidationException('Unsupported GeoJSON type: $type');
  }

  int? featureCount;
  if (type == 'FeatureCollection') {
    final features = decoded['features'];
    if (features is! List) {
      throw GeoJsonValidationException(
          'FeatureCollection.features must be a list');
    }
    featureCount = features.length;
  }

  return GeoJsonInfo(type: type, featureCount: featureCount);
}

Future<Uint8List> brotliCompress(Uint8List bytes, {int quality = 11}) async {
  try {
    final executable = await _BrotliCli.instance.resolve();
    final process = await Process.start(
      executable,
      ['--quality=$quality', '--stdout'],
      runInShell: false,
    );

    final stdoutFuture = process.stdout.fold<List<int>>(
      <int>[],
      (previous, element) => previous..addAll(element),
    );
    final stderrFuture = process.stderr.fold<List<int>>(
      <int>[],
      (previous, element) => previous..addAll(element),
    );

    process.stdin.add(bytes);
    await process.stdin.close();

    final exitCode = await process.exitCode;
    final stdoutBytes = Uint8List.fromList(await stdoutFuture);
    final stderrBytes = Uint8List.fromList(await stderrFuture);

    if (exitCode != 0) {
      final message = stderrBytes.isEmpty
          ? 'exit code $exitCode'
          : utf8.decode(stderrBytes, allowMalformed: true);
      throw CompressFailedException('Brotli CLI failed: $message');
    }

    return stdoutBytes;
  } on GeoJsonQrException {
    rethrow;
  } catch (e) {
    throw CompressFailedException('Brotli compression failed', e);
  }
}

Uint8List brotliDecompress(Uint8List bytes) {
  try {
    const decoder = brotli.BrotliDecoder();
    final decompressed = decoder.convert(bytes);
    return Uint8List.fromList(decompressed);
  } catch (e) {
    throw DecompressFailedException('Brotli decompression failed', e);
  }
}

String base64UrlEncodeNoPad(Uint8List bytes) {
  final encoded = base64Url
      .encode(bytes)
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '');
  return encoded;
}

Uint8List base64UrlDecodeNoPad(String text) {
  try {
    final paddingNeeded = (4 - text.length % 4) % 4;
    final normalized = paddingNeeded == 0
        ? text
        : text.padRight(text.length + paddingNeeded, '=');
    return Uint8List.fromList(base64Url.decode(normalized));
  } catch (e) {
    throw DecodeFailedException('Failed to decode Base64URL payload', e);
  }
}

String computeSha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

List<String> _buildQrTexts(String payload, String? hashHex, int maxLength) {
  final single = _buildGjB1Text(payload, hashHex);
  if (single.length <= maxLength) {
    return [single];
  }
  return buildGjB1pTexts(payload, hash: hashHex, maxLength: maxLength);
}

String _buildGjB1Text(String payload, String? hashHex) {
  if (hashHex == null) {
    return 'gjb1:$payload';
  }
  return 'gjb1:$payload#$hashHex';
}

List<String> buildGjB1pTexts(
  String payload, {
  String? hash,
  required int maxLength,
}) {
  if (maxLength <= 12) {
    throw PayloadTooLargeException(
        'maxQrTextLength too small to hold metadata');
  }
  final payloadWithHash = hash == null ? payload : '$payload#$hash';
  var total = max(1, (payloadWithHash.length / (maxLength - 12)).ceil());

  while (true) {
    final digitsTotal = _digits(total);
    final maxChunkPayloadLength = maxLength - (8 + 2 * digitsTotal);
    if (maxChunkPayloadLength <= 0) {
      throw PayloadTooLargeException('maxQrTextLength too small for gjb1p');
    }

    final chunks = <String>[];
    var offset = 0;
    while (offset < payloadWithHash.length) {
      final end = min(offset + maxChunkPayloadLength, payloadWithHash.length);
      chunks.add(payloadWithHash.substring(offset, end));
      offset = end;
    }

    if (chunks.length != total) {
      total = chunks.length;
      continue;
    }

    final totalStr = total.toString();
    var overflow = false;
    for (var i = 0; i < chunks.length; i++) {
      final indexStr = (i + 1).toString();
      final projectedLength =
          6 + indexStr.length + 1 + totalStr.length + 1 + chunks[i].length;
      if (projectedLength > maxLength) {
        overflow = true;
        break;
      }
    }

    if (overflow) {
      total += 1;
      continue;
    }

    final result = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final indexStr = (i + 1).toString();
      result.add('gjb1p:$indexStr/$totalStr:${chunks[i]}');
    }
    return result;
  }
}

/// `gjb1` / `gjb1p`テキストを解析してペイロードとハッシュを取り出す。
GjB1Payload _parseGjB1Payload(List<String> texts) {
  if (texts.length == 1 && texts.first.startsWith('gjb1:')) {
    return _parseGjB1Single(texts.first);
  }
  if (texts.every((element) => element.startsWith('gjb1p:'))) {
    final merged = _mergeGjB1Chunks(texts);
    return _parseGjB1Single('gjb1:$merged');
  }
  throw UnsupportedSchemeException('Unsupported QR scheme');
}

GjB1Payload _parseGjB1Single(String text) {
  if (!text.startsWith('gjb1:')) {
    throw UnsupportedSchemeException('Expected gjb1 scheme');
  }
  final payloadWithHash = text.substring('gjb1:'.length);
  if (payloadWithHash.isEmpty) {
    throw DecodeFailedException('Empty gjb1 payload');
  }
  return _splitPayloadAndHash(payloadWithHash);
}

String _mergeGjB1Chunks(List<String> texts) {
  final chunkRegExp = RegExp(r'^gjb1p:(\d+)/(\d+):(.*)$', dotAll: true);
  final Map<int, String> chunks = {};
  int? expectedTotal;

  for (final text in texts) {
    final match = chunkRegExp.firstMatch(text);
    if (match == null) {
      throw UnsupportedSchemeException('Malformed gjb1p chunk');
    }
    final index = int.parse(match.group(1)!);
    final total = int.parse(match.group(2)!);
    final payload = match.group(3)!;

    if (index < 1 || total < 1) {
      throw ChunkMismatchException('Chunk index/total must be positive');
    }
    expectedTotal ??= total;
    if (expectedTotal != total) {
      throw ChunkMismatchException('Inconsistent total count in chunks');
    }
    if (chunks.containsKey(index)) {
      throw ChunkMismatchException('Duplicate chunk index: $index');
    }
    chunks[index] = payload;
  }

  final total = expectedTotal ?? chunks.length;
  for (var i = 1; i <= total; i++) {
    if (!chunks.containsKey(i)) {
      throw ChunkMismatchException('Missing chunk index: $i');
    }
  }

  final buffer = StringBuffer();
  for (var i = 1; i <= total; i++) {
    buffer.write(chunks[i]);
  }
  return buffer.toString();
}

GjB1Payload _splitPayloadAndHash(String payloadWithHash) {
  final hashIndex = payloadWithHash.lastIndexOf('#');
  if (hashIndex == -1) {
    return GjB1Payload(payloadWithHash, null);
  }

  final payload = payloadWithHash.substring(0, hashIndex);
  final hash = payloadWithHash.substring(hashIndex + 1);

  if (!_isValidHashHex(hash)) {
    throw DecodeFailedException('Malformed hash suffix');
  }

  return GjB1Payload(payload, hash);
}

class GjB1Payload {
  const GjB1Payload(this.payload, this.hashHex);

  final String payload;
  final String? hashHex;
}

Uint8List generateQrPng(
  String text,
  QrErrorCorrectionLevel ecc, {
  int modulePixelSize = 8,
  int quietZoneModules = 4,
}) {
  try {
    final qrCode = QrCode.fromData(
      data: text,
      errorCorrectLevel: ecc._toQrErrorCorrectLevel(),
    );
    final qrImage = QrImage(qrCode);

    final moduleCount = qrImage.moduleCount;
    final totalModules = moduleCount + (quietZoneModules * 2);
    final imageSize = totalModules * modulePixelSize;
    final image = img.Image(width: imageSize, height: imageSize);
    final white = img.ColorRgba8(255, 255, 255, 255);
    final black = img.ColorRgba8(0, 0, 0, 255);

    image.clear(white);

    for (var r = 0; r < moduleCount; r++) {
      for (var c = 0; c < moduleCount; c++) {
        if (!qrImage.isDark(r, c)) {
          continue;
        }
        final startX = (c + quietZoneModules) * modulePixelSize;
        final startY = (r + quietZoneModules) * modulePixelSize;
        for (var dy = 0; dy < modulePixelSize; dy++) {
          for (var dx = 0; dx < modulePixelSize; dx++) {
            image.setPixel(startX + dx, startY + dy, black);
          }
        }
      }
    }

    final encoded = img.encodePng(image);
    return Uint8List.fromList(encoded);
  } on InputTooLongException {
    throw PayloadTooLargeException(
        'QR payload too large for the selected configuration');
  } catch (e) {
    throw QrGenerationException('Failed to render QR image', e);
  }
}

extension on QrErrorCorrectionLevel {
  int _toQrErrorCorrectLevel() {
    switch (this) {
      case QrErrorCorrectionLevel.low:
        return QrErrorCorrectLevel.L;
      case QrErrorCorrectionLevel.medium:
        return QrErrorCorrectLevel.M;
      case QrErrorCorrectionLevel.quartile:
        return QrErrorCorrectLevel.Q;
      case QrErrorCorrectionLevel.high:
        return QrErrorCorrectLevel.H;
    }
  }
}

/// Brotli CLI の検索パスを明示的に設定する。`null`でリセット。
void configureBrotliCliPath(String? path) {
  _BrotliCli.instance.override(path);
}

class _BrotliCli {
  _BrotliCli._();

  static final _BrotliCli instance = _BrotliCli._();

  String? _overridePath;
  String? _cachedPath;

  void override(String? path) {
    final normalized = path?.trim();
    _overridePath =
        (normalized != null && normalized.isNotEmpty) ? normalized : null;
    _cachedPath = null;
  }

  Future<String> resolve() async {
    final candidates = <String?>[
      _overridePath,
      Platform.environment['BROTLI_CLI'],
      if (_cachedPath != null) _cachedPath,
      if (Platform.isWindows) ...[
        await _which('brotli.exe'),
        await _which('brotli'),
        'C:\\Program Files\\QGIS 3.40.5\\bin\\brotli.exe',
      ] else ...[
        await _which('brotli'),
      ],
    ];

    for (final candidate in candidates) {
      if (candidate == null || candidate.isEmpty) {
        continue;
      }
      final file = File(candidate);
      if (await file.exists()) {
        _cachedPath = file.path;
        return file.path;
      }
    }

    throw CompressFailedException(
      'Brotli CLI not found. Install "brotli" command or set BROTLI_CLI.',
    );
  }

  Future<String?> _which(String command) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [command],
        runInShell: Platform.isWindows,
      );
      if (result.exitCode == 0) {
        final stdout = result.stdout is String
            ? result.stdout as String
            : utf8.decode(result.stdout as List<int>, allowMalformed: true);
        final candidate = stdout
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '');
        if (candidate.isNotEmpty) {
          return candidate;
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }
}

bool _isValidHashHex(String value) {
  final hashRegExp = RegExp(r'^[0-9a-fA-F]{64}$');
  return hashRegExp.hasMatch(value);
}

int _digits(int value) => max(1, value.toString().length);

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}
