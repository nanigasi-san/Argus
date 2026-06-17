import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

/// 入力GeoJSONをQRへ変換する際の設定値。
class GeoJsonQrEncodeInput {
  const GeoJsonQrEncodeInput({
    required this.geoJson,
    this.sourceFileName,
    this.scheme = GeoJsonQrScheme.gjz1,
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
  final String? sourceFileName;
  final GeoJsonQrScheme scheme;
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
}

/// QRから復元したGeoJSONと、ペイロードに含まれる元ファイル名。
class DecodedGeoJson {
  const DecodedGeoJson({required this.geoJson, this.fileName});

  final String geoJson;
  final String? fileName;
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

  DecompressFailedException.withCode(super.code, super.message, [super.cause]);
}

class DecodeFailedException extends GeoJsonQrException {
  DecodeFailedException(String message, [Object? cause])
      : super('E_DECODE_FAILED', message, cause);

  DecodeFailedException.withCode(super.code, super.message, [super.cause]);
}

class Base64DecodeFailedException extends DecodeFailedException {
  Base64DecodeFailedException(String message, [Object? cause])
      : super.withCode('E_BASE64_DECODE_FAILED', message, cause);
}

class GzipDecompressFailedException extends DecompressFailedException {
  GzipDecompressFailedException(String message, [Object? cause])
      : super.withCode('E_GZIP_DECOMPRESS_FAILED', message, cause);
}

class InvalidDiffTextException extends GeoJsonQrException {
  InvalidDiffTextException(String message, [Object? cause])
      : super('E_INVALID_DIFF_TEXT', message, cause);
}

class InvalidScaleException extends GeoJsonQrException {
  InvalidScaleException(String message, [Object? cause])
      : super('E_INVALID_SCALE', message, cause);
}

class InvalidCoordinateException extends GeoJsonQrException {
  InvalidCoordinateException(String message, [Object? cause])
      : super('E_INVALID_COORDINATE', message, cause);
}

class TooFewPointsException extends GeoJsonQrException {
  TooFewPointsException(String message) : super('E_TOO_FEW_POINTS', message);
}

class PolygonNotClosedException extends GeoJsonQrException {
  PolygonNotClosedException(String message)
      : super('E_POLYGON_NOT_CLOSED', message);
}

class UnsupportedGeometryException extends GeoJsonQrException {
  UnsupportedGeometryException(String message)
      : super('E_UNSUPPORTED_GEOMETRY', message);
}

class InvalidFileNameException extends GeoJsonQrException {
  InvalidFileNameException(String message, [Object? cause])
      : super('E_INVALID_FILENAME', message, cause);
}

class UnsupportedSchemeException extends GeoJsonQrException {
  UnsupportedSchemeException(String message)
      : super('E_UNSUPPORTED_SCHEME', message);
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

/// GeoJSON QRで使う圧縮/ペイロードスキーム。
enum GeoJsonQrScheme {
  /// gzip圧縮。Dart標準ライブラリのみで生成/復元できる。
  gjz1,

  /// ARGUSの単一Polygonに特化した差分圧縮形式。
  agz1,
}

extension GeoJsonQrSchemeName on GeoJsonQrScheme {
  String get wireName {
    switch (this) {
      case GeoJsonQrScheme.gjz1:
        return 'gjz1';
      case GeoJsonQrScheme.agz1:
        return 'agz1';
    }
  }

  String get _singlePrefix => wireName;
}

/// GeoJSON文字列をQRテキスト(とPNG)へ変換する。
Future<GeoJsonQrBundle> encodeGeoJson(GeoJsonQrEncodeInput input) async {
  final agzDiffText = input.scheme == GeoJsonQrScheme.agz1
      ? _geoJsonToAgzDiffText(input.geoJson, input.sourceFileName)
      : null;
  final minifyResult = minifyGeoJson(input.geoJson);
  final minimizedBytes =
      Uint8List.fromList(utf8.encode(minifyResult.minimized));
  final bytesToCompress = switch (input.scheme) {
    GeoJsonQrScheme.gjz1 => minimizedBytes,
    GeoJsonQrScheme.agz1 => Uint8List.fromList(
        utf8.encode(
          agzDiffText!,
        ),
      ),
  };
  final compressedBytes =
      await _compressForScheme(input.scheme, bytesToCompress);
  final payload = base64UrlEncodeNoPad(compressedBytes);
  final hashHex = input.scheme == GeoJsonQrScheme.gjz1 && input.enableHash
      ? computeSha256Hex(minimizedBytes)
      : null;

  var qrTexts =
      _buildQrTexts(input.scheme, payload, hashHex, input.maxQrTextLength);
  var pngImages = <Uint8List>[];

  if (input.generatePng) {
    try {
      pngImages = [
        generateQrPng(
          qrTexts.single,
          input.eccLevel,
          modulePixelSize: input.modulePixelSize,
          quietZoneModules: input.quietZoneModules,
        ),
      ];
      // coverage:ignore-start
    } on PayloadTooLargeException catch (e) {
      // The lower-level encoder already covers this limit; this branch keeps
      // the bundle API error type stable if PNG generation is requested.
      throw QrGenerationException(e.message, e);
    }
    // coverage:ignore-end
  }

  return GeoJsonQrBundle(
    qrTexts: qrTexts,
    pngImages: pngImages,
    minimizedGeoJson: minifyResult.minimized,
    hashHex: hashHex,
    info: minifyResult.info,
  );
}

bool isSupportedGeoJsonQrText(String text) {
  final normalized = text.trim();
  return normalized.startsWith('gjz1:') || normalized.startsWith('agz1:');
}

/// QRテキストからGeoJSON文字列を復元する。
Future<String> decodeGeoJson(GeoJsonQrDecodeInput input) async {
  final decoded = await decodeGeoJsonWithMetadata(input);
  return decoded.geoJson;
}

/// QRテキストからGeoJSON文字列と埋め込みファイル名を復元する。
Future<DecodedGeoJson> decodeGeoJsonWithMetadata(
  GeoJsonQrDecodeInput input,
) async {
  final normalized = input.qrTexts
      .map((e) => e.trim())
      .where((element) => element.isNotEmpty)
      .toList(growable: false);

  if (normalized.isEmpty) {
    throw UnsupportedSchemeException('No QR text supplied');
  }

  final payload = _parseQrPayload(normalized);
  late final Uint8List compressedBytes;
  try {
    compressedBytes = base64UrlDecodeNoPad(payload.payload);
  } on DecodeFailedException catch (e) {
    if (payload.scheme == GeoJsonQrScheme.agz1) {
      throw Base64DecodeFailedException(e.message, e.cause);
    }
    rethrow;
  }

  late final Uint8List decompressedBytes;
  try {
    decompressedBytes = _decompressForScheme(payload.scheme, compressedBytes);
  } on DecompressFailedException catch (e) {
    if (payload.scheme == GeoJsonQrScheme.agz1) {
      throw GzipDecompressFailedException(e.message, e.cause);
    }
    rethrow;
  }

  if (payload.scheme == GeoJsonQrScheme.agz1) {
    try {
      return _agzDiffTextToGeoJson(utf8.decode(decompressedBytes));
    } on GeoJsonQrException {
      rethrow;
    } on FormatException catch (e) {
      throw InvalidDiffTextException('AGZ diff text is not valid UTF-8', e);
    }
  }

  final minimized = utf8.decode(decompressedBytes);

  validateGeoJsonStructure(jsonDecode(minimized));

  if (input.verifyHash && payload.hashHex != null) {
    final currentHash = computeSha256Hex(decompressedBytes);
    if (!_constantTimeEquals(payload.hashHex!, currentHash)) {
      throw HashMismatchException('Hash mismatch detected');
    }
  }

  return DecodedGeoJson(geoJson: minimized);
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

Uint8List gzipCompress(Uint8List bytes, {int level = 9}) {
  try {
    return Uint8List.fromList(GZipCodec(level: level).encode(bytes));
  } catch (e) {
    // coverage:ignore-start
    // Dart's gzip encoder does not expose a practical deterministic failure
    // path for valid in-memory bytes.
    throw CompressFailedException('gzip compression failed', e);
    // coverage:ignore-end
  }
}

Uint8List gzipDecompress(Uint8List bytes) {
  try {
    return Uint8List.fromList(GZipCodec().decode(bytes));
  } catch (e) {
    throw DecompressFailedException('gzip decompression failed', e);
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

Future<Uint8List> _compressForScheme(
  GeoJsonQrScheme scheme,
  Uint8List bytes,
) {
  switch (scheme) {
    case GeoJsonQrScheme.gjz1:
    case GeoJsonQrScheme.agz1:
      return Future.value(gzipCompress(bytes));
  }
}

Uint8List _decompressForScheme(GeoJsonQrScheme scheme, Uint8List bytes) {
  switch (scheme) {
    case GeoJsonQrScheme.gjz1:
    case GeoJsonQrScheme.agz1:
      return gzipDecompress(bytes);
  }
}

List<String> _buildQrTexts(
  GeoJsonQrScheme scheme,
  String payload,
  String? hashHex,
  int maxLength,
) {
  final single = _buildSingleText(scheme, payload, hashHex);
  if (single.length <= maxLength) {
    return [single];
  }
  throw PayloadTooLargeException(
      'QR payload too large for maxQrTextLength: $maxLength');
}

String _buildSingleText(
  GeoJsonQrScheme scheme,
  String payload,
  String? hashHex,
) {
  final prefix = scheme._singlePrefix;
  if (hashHex == null) {
    return '$prefix:$payload';
  }
  return '$prefix:$payload#$hashHex';
}

/// `gjz1`テキストを解析する。
QrPayload _parseQrPayload(List<String> texts) {
  if (texts.length == 1) {
    final text = texts.first;
    if (text.startsWith('gjz1:')) {
      return _parseSinglePayload(GeoJsonQrScheme.gjz1, text);
    }
    if (text.startsWith('agz1:')) {
      return _parseSinglePayload(GeoJsonQrScheme.agz1, text);
    }
  }

  throw UnsupportedSchemeException('Unsupported QR scheme');
}

QrPayload _parseSinglePayload(GeoJsonQrScheme scheme, String text) {
  final prefix = scheme._singlePrefix;
  // coverage:ignore-start
  // _parseQrPayload routes by prefix before calling this helper, so this guard
  // is defensive against future private misuse rather than public behavior.
  if (!text.startsWith('$prefix:')) {
    throw UnsupportedSchemeException('Expected $prefix scheme');
  }
  // coverage:ignore-end
  final payloadWithHash = text.substring(prefix.length + 1);
  if (payloadWithHash.isEmpty) {
    throw DecodeFailedException('Empty $prefix payload');
  }
  final split = _splitPayloadAndHash(payloadWithHash);
  if (scheme == GeoJsonQrScheme.agz1 && split.hashHex != null) {
    throw DecodeFailedException('agz1 does not support a hash suffix');
  }
  return QrPayload(scheme, split.payload, split.hashHex);
}

PayloadAndHash _splitPayloadAndHash(String payloadWithHash) {
  final hashIndex = payloadWithHash.lastIndexOf('#');
  if (hashIndex == -1) {
    return PayloadAndHash(payloadWithHash, null);
  }

  final payload = payloadWithHash.substring(0, hashIndex);
  final hash = payloadWithHash.substring(hashIndex + 1);

  if (!_isValidHashHex(hash)) {
    throw DecodeFailedException('Malformed hash suffix');
  }

  return PayloadAndHash(payload, hash);
}

class PayloadAndHash {
  const PayloadAndHash(this.payload, this.hashHex);

  final String payload;
  final String? hashHex;
}

class QrPayload {
  const QrPayload(this.scheme, this.payload, this.hashHex);

  final GeoJsonQrScheme scheme;
  final String payload;
  final String? hashHex;
}

const int _agzScale = 6;

String _geoJsonToAgzDiffText(String geoJson, String? sourceFileName) {
  final fileName = _normalizeGeoJsonFileName(sourceFileName);
  final dynamic decoded = jsonDecode(geoJson);
  if (decoded is! Map<String, dynamic> ||
      decoded['type'] != 'FeatureCollection') {
    throw UnsupportedGeometryException(
      'agz1 requires a FeatureCollection',
    );
  }
  final features = decoded['features'];
  if (features is! List || features.length != 1) {
    throw UnsupportedGeometryException(
      'agz1 requires exactly one Feature',
    );
  }
  final feature = features.single;
  if (feature is! Map<String, dynamic>) {
    throw UnsupportedGeometryException('Feature must be an object');
  }
  final geometry = feature['geometry'];
  if (geometry is! Map<String, dynamic> || geometry['type'] != 'Polygon') {
    throw UnsupportedGeometryException('agz1 supports only Polygon geometry');
  }
  final coordinates = geometry['coordinates'];
  if (coordinates is! List || coordinates.length != 1) {
    throw UnsupportedGeometryException(
      'agz1 supports exactly one exterior ring and no holes',
    );
  }
  final ring = coordinates.single;
  if (ring is! List) {
    throw InvalidCoordinateException('Polygon ring must be a list');
  }
  if (ring.length < 4) {
    throw TooFewPointsException(
      'Polygon must contain at least four points including closure',
    );
  }

  final points = ring.map(_readCoordinate).toList(growable: false);
  if (points.first.lon != points.last.lon ||
      points.first.lat != points.last.lat) {
    throw PolygonNotClosedException(
      'Polygon final point must match its first point',
    );
  }

  const factor = 1000000;
  final integerPoints = points
      .map(
        (point) => _IntegerCoordinate(
          (point.lon * factor).round(),
          (point.lat * factor).round(),
        ),
      )
      .toList(growable: false);
  final first = integerPoints.first;
  final deltas = <String>[];
  var previous = first;
  for (final point in integerPoints.skip(1)) {
    deltas.add('${point.lon - previous.lon},${point.lat - previous.lat}');
    previous = point;
  }

  final fileNameToken = base64UrlEncodeNoPad(
    Uint8List.fromList(utf8.encode(fileName)),
  );
  return 'a3:$_agzScale:$fileNameToken:'
      '${first.lon},${first.lat}|${deltas.join(';')}';
}

DecodedGeoJson _agzDiffTextToGeoJson(String diffText) {
  final fields = diffText.split(':');
  if (fields.length != 4 || fields.first != 'a3') {
    throw InvalidDiffTextException(
      'Expected a3:<scale>:<filename>:<coordinates>',
    );
  }

  final scale = int.tryParse(fields[1]);
  if (scale == null || scale < 0 || scale > 9) {
    throw InvalidScaleException('AGZ scale must be an integer from 0 to 9');
  }

  final fileName = _decodeAgzFileName(fields[2]);
  final coordinateSections = fields[3].split('|');
  if (coordinateSections.length != 2 || coordinateSections[1].isEmpty) {
    throw InvalidDiffTextException(
      'AGZ coordinates must contain an absolute point and deltas',
    );
  }

  final first = _parseIntegerCoordinate(coordinateSections[0]);
  final points = <_IntegerCoordinate>[first];
  var previous = first;
  for (final deltaText in coordinateSections[1].split(';')) {
    final delta = _parseIntegerCoordinate(deltaText);
    final current = _IntegerCoordinate(
      previous.lon + delta.lon,
      previous.lat + delta.lat,
    );
    points.add(current);
    previous = current;
  }
  if (points.length < 4) {
    throw TooFewPointsException(
      'Polygon must contain at least four points including closure',
    );
  }
  if (points.first.lon != points.last.lon ||
      points.first.lat != points.last.lat) {
    throw PolygonNotClosedException(
      'Polygon final point must match its first point',
    );
  }

  var factor = 1.0;
  for (var i = 0; i < scale; i++) {
    factor *= 10;
  }
  final ring = points
      .map((point) => <double>[point.lon / factor, point.lat / factor])
      .toList(growable: false);
  final geoJson = jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [ring],
        },
      },
    ],
  });
  return DecodedGeoJson(geoJson: geoJson, fileName: fileName);
}

String _decodeAgzFileName(String token) {
  if (token.isEmpty) {
    throw InvalidFileNameException('AGZ filename is empty');
  }
  try {
    final decoded = utf8.decode(base64UrlDecodeNoPad(token));
    return _normalizeGeoJsonFileName(decoded);
  } on InvalidFileNameException {
    rethrow;
  } on Object catch (e) {
    throw InvalidFileNameException('Invalid AGZ filename', e);
  }
}

String _normalizeGeoJsonFileName(String? value) {
  if (value == null || value.trim().isEmpty) {
    throw InvalidFileNameException('A source filename is required for agz1');
  }
  var name = value.trim().replaceAll('\\', '/').split('/').last;
  final queryIndex = name.indexOf(RegExp(r'[?#]'));
  if (queryIndex >= 0) {
    name = name.substring(0, queryIndex);
  }
  final dotIndex = name.lastIndexOf('.');
  final stem = (dotIndex > 0 ? name.substring(0, dotIndex) : name).trim();
  if (stem.isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(stem)) {
    throw InvalidFileNameException('AGZ filename is invalid');
  }
  final normalized = '$stem.geojson';
  if (utf8.encode(normalized).length > 255) {
    throw InvalidFileNameException('AGZ filename is too long');
  }
  return normalized;
}

_Coordinate _readCoordinate(dynamic value) {
  if (value is! List || value.length < 2) {
    throw InvalidCoordinateException('Coordinate must contain lon and lat');
  }
  final lon = value[0];
  final lat = value[1];
  if (lon is! num || lat is! num) {
    throw InvalidCoordinateException('Coordinate values must be numbers');
  }
  final lonValue = lon.toDouble();
  final latValue = lat.toDouble();
  if (!lonValue.isFinite || !latValue.isFinite) {
    throw InvalidCoordinateException('Coordinate values must be finite');
  }
  return _Coordinate(lonValue, latValue);
}

_IntegerCoordinate _parseIntegerCoordinate(String value) {
  final parts = value.split(',');
  if (parts.length != 2) {
    throw InvalidCoordinateException('Coordinate must contain two integers');
  }
  final lon = int.tryParse(parts[0]);
  final lat = int.tryParse(parts[1]);
  if (lon == null || lat == null) {
    throw InvalidCoordinateException('Coordinate values must be integers');
  }
  return _IntegerCoordinate(lon, lat);
}

class _Coordinate {
  const _Coordinate(this.lon, this.lat);

  final double lon;
  final double lat;
}

class _IntegerCoordinate {
  const _IntegerCoordinate(this.lon, this.lat);

  final int lon;
  final int lat;
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
    // coverage:ignore-start
    // Image encoding failures are defensive; QR sizing errors are covered by
    // the InputTooLongException branch above.
    throw QrGenerationException('Failed to render QR image', e);
    // coverage:ignore-end
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

bool _isValidHashHex(String value) {
  final hashRegExp = RegExp(r'^[0-9a-fA-F]{64}$');
  return hashRegExp.hasMatch(value);
}

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
