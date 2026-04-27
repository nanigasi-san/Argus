import 'dart:convert';
import 'dart:io';

import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sampleGeoJson;

  setUpAll(() async {
    final file = File('assets/geojson/map.geojson');
    sampleGeoJson = file.readAsStringSync();
    await _ensureBrotliCli();
  });

  test('minifyGeoJson removes whitespace and keeps structure', () {
    final result = minifyGeoJson(sampleGeoJson);
    expect(result.minimized.contains('\n'), isFalse);
    expect(result.info.type, 'FeatureCollection');
    expect(result.info.featureCount, 1);
  });

  test('encode and decode gjb1 round trip with hash succeeds', () async {
    final bundle =
        await encodeGeoJson(GeoJsonQrEncodeInput(geoJson: sampleGeoJson));

    expect(bundle.qrTexts, hasLength(1));
    expect(bundle.qrTexts, hasLength(1));
    expect(bundle.qrTexts.first.startsWith('gjb1:'), isTrue);
    final payloadSection =
        bundle.qrTexts.first.substring(bundle.qrTexts.first.indexOf(':') + 1);
    final payload = payloadSection.split('#').first;
    expect(payload.contains('='), isFalse);
    expect(payload, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(bundle.hashHex, isNotNull);
    if (bundle.pngImages.isNotEmpty) {
      expect(bundle.pngImages.first, isNotEmpty);
    }

    final restored =
        await decodeGeoJson(GeoJsonQrDecodeInput(qrTexts: bundle.qrTexts));
    expect(restored, bundle.minimizedGeoJson);
  });

  test('encode and decode gjz1 round trip with hash succeeds', () async {
    final bundle = await encodeGeoJson(
      GeoJsonQrEncodeInput(
        geoJson: sampleGeoJson,
        scheme: GeoJsonQrScheme.gjz1,
      ),
    );

    expect(bundle.qrTexts, hasLength(1));
    expect(bundle.qrTexts, hasLength(1));
    expect(bundle.qrTexts.first.startsWith('gjz1:'), isTrue);
    final payloadSection =
        bundle.qrTexts.first.substring(bundle.qrTexts.first.indexOf(':') + 1);
    final payload = payloadSection.split('#').first;
    expect(payload.contains('='), isFalse);
    expect(payload, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(bundle.hashHex, isNotNull);
    expect(bundle.pngImages.first, isNotEmpty);

    final restored =
        await decodeGeoJson(GeoJsonQrDecodeInput(qrTexts: bundle.qrTexts));
    expect(restored, bundle.minimizedGeoJson);
  });

  test('gjz1 helper exposes wire name', () {
    expect(GeoJsonQrScheme.gjz1.wireName, 'gjz1');
  });

  test('encode rejects payloads that exceed max text length', () async {
    await expectLater(
      encodeGeoJson(
        GeoJsonQrEncodeInput(
          geoJson: sampleGeoJson,
          scheme: GeoJsonQrScheme.gjz1,
          maxQrTextLength: 20,
          generatePng: false,
        ),
      ),
      throwsA(isA<PayloadTooLargeException>()),
    );
  });

  test('decode fails on hash mismatch', () async {
    final bundle =
        await encodeGeoJson(GeoJsonQrEncodeInput(geoJson: sampleGeoJson));
    final tampered = List<String>.from(bundle.qrTexts);

    final indexWithHash = tampered.indexWhere((text) => text.contains('#'));
    expect(indexWithHash, isNot(-1));

    final text = tampered[indexWithHash];
    final separatorIndex = text.lastIndexOf('#');
    final base = text.substring(0, separatorIndex + 1);
    final hash = text.substring(separatorIndex + 1);
    final firstChar = hash.startsWith('0') ? '1' : '0';
    tampered[indexWithHash] = '$base$firstChar${hash.substring(1)}';

    await expectLater(
      decodeGeoJson(GeoJsonQrDecodeInput(qrTexts: tampered)),
      throwsA(isA<HashMismatchException>()),
    );
  });

  test('decode gjz1 fails on hash mismatch', () async {
    final bundle = await encodeGeoJson(
      GeoJsonQrEncodeInput(
        geoJson: sampleGeoJson,
        scheme: GeoJsonQrScheme.gjz1,
      ),
    );
    final tampered = List<String>.from(bundle.qrTexts);

    final text = tampered.single;
    final separatorIndex = text.lastIndexOf('#');
    final base = text.substring(0, separatorIndex + 1);
    final hash = text.substring(separatorIndex + 1);
    final firstChar = hash.startsWith('0') ? '1' : '0';
    tampered[0] = '$base$firstChar${hash.substring(1)}';

    await expectLater(
      decodeGeoJson(GeoJsonQrDecodeInput(qrTexts: tampered)),
      throwsA(isA<HashMismatchException>()),
    );
  });

  test('decode gjz1 rejects empty payload and malformed hash suffix', () async {
    await expectLater(
      decodeGeoJson(const GeoJsonQrDecodeInput(qrTexts: ['gjz1:'])),
      throwsA(isA<DecodeFailedException>()),
    );
    await expectLater(
      decodeGeoJson(
        const GeoJsonQrDecodeInput(qrTexts: ['gjz1:payload#xyz']),
      ),
      throwsA(isA<DecodeFailedException>()),
    );
  });

  test('decode gjz1 rejects payloads that are not gzip data', () async {
    final payload = base64UrlEncodeNoPad(utf8.encode('not gzip data'));

    await expectLater(
      decodeGeoJson(GeoJsonQrDecodeInput(qrTexts: ['gjz1:$payload'])),
      throwsA(isA<DecompressFailedException>()),
    );
  });

  test('decode rejects unsupported scheme', () async {
    await expectLater(
      decodeGeoJson(const GeoJsonQrDecodeInput(qrTexts: ['abc1:payload'])),
      throwsA(isA<UnsupportedSchemeException>()),
    );
  });

  test('decode rejects invalid base64 payload', () async {
    await expectLater(
      decodeGeoJson(const GeoJsonQrDecodeInput(qrTexts: ['gjb1:@@@@'])),
      throwsA(isA<DecodeFailedException>()),
    );
    await expectLater(
      decodeGeoJson(const GeoJsonQrDecodeInput(qrTexts: ['gjz1:@@@@'])),
      throwsA(isA<DecodeFailedException>()),
    );
  });

  test('bundle getters and exception toString expose metadata', () {
    final bundle = GeoJsonQrBundle(
      qrTexts: const ['a'],
      pngImages: const [],
      minimizedGeoJson: '{}',
      hashHex: null,
      info: const GeoJsonInfo(type: 'FeatureCollection', featureCount: 0),
    );

    final validation = GeoJsonValidationException('bad json');
    final compress = CompressFailedException('compress failed', 'cli');
    final decompress = DecompressFailedException('decompress failed');
    final payload = PayloadTooLargeException('too large');
    final qr = QrGenerationException('render failed');

    expect(bundle.qrTexts, const ['a']);
    expect(validation.toString(), contains('E_INVALID_GEOJSON'));
    expect(compress.toString(), contains('cli'));
    expect(decompress.code, 'E_DECOMPRESS_FAILED');
    expect(payload.code, 'E_PAYLOAD_TOO_LARGE');
    expect(qr.code, 'E_QR_GENERATION');
  });

  test('encode without hash omits hash suffix', () async {
    final bundle = await encodeGeoJson(
      GeoJsonQrEncodeInput(
        geoJson: sampleGeoJson,
        enableHash: false,
        generatePng: false,
      ),
    );

    expect(bundle.hashHex, isNull);
    expect(bundle.qrTexts, hasLength(1));
    expect(bundle.qrTexts.single, startsWith('gjb1:'));
    expect(bundle.qrTexts.single.contains('#'), isFalse);
  });

  test('decode rejects empty input and empty gjb1 payload', () async {
    await expectLater(
      decodeGeoJson(const GeoJsonQrDecodeInput(qrTexts: [])),
      throwsA(isA<UnsupportedSchemeException>()),
    );
    await expectLater(
      decodeGeoJson(const GeoJsonQrDecodeInput(qrTexts: ['gjb1:'])),
      throwsA(isA<DecodeFailedException>()),
    );
  });

  test('minify and validate reject malformed GeoJSON structures', () {
    expect(
      () => minifyGeoJson('{invalid'),
      throwsA(isA<GeoJsonValidationException>()),
    );
    expect(
      () => validateGeoJsonStructure(const ['not-an-object']),
      throwsA(isA<GeoJsonValidationException>()),
    );
    expect(
      () => validateGeoJsonStructure(const {'features': []}),
      throwsA(isA<GeoJsonValidationException>()),
    );
    expect(
      () => validateGeoJsonStructure(const {'type': 'Circle'}),
      throwsA(isA<GeoJsonValidationException>()),
    );
    expect(
      () => validateGeoJsonStructure(
        const {'type': 'FeatureCollection', 'features': 'oops'},
      ),
      throwsA(isA<GeoJsonValidationException>()),
    );
  });

  test('decode rejects malformed hash suffix', () async {
    await expectLater(
      decodeGeoJson(
        const GeoJsonQrDecodeInput(qrTexts: ['gjb1:payload#xyz']),
      ),
      throwsA(isA<DecodeFailedException>()),
    );
    await expectLater(
      decodeGeoJson(
        const GeoJsonQrDecodeInput(qrTexts: ['gjz1:payload#xyz']),
      ),
      throwsA(isA<DecodeFailedException>()),
    );
  });

  test('generateQrPng supports high ECC and rejects oversized payloads', () {
    final png = generateQrPng('hello', QrErrorCorrectionLevel.high);

    expect(png, isNotEmpty);
    expect(
      () => generateQrPng('x' * 5000, QrErrorCorrectionLevel.high),
      throwsA(isA<PayloadTooLargeException>()),
    );
  });
}

Future<void> _ensureBrotliCli() async {
  final candidates = <String?>[
    Platform.environment['BROTLI_CLI'],
    if (Platform.isWindows)
      'C:\\Program Files\\QGIS 3.40.5\\bin\\brotli.exe'
    else
      '/usr/bin/brotli',
    if (Platform.isWindows) await _which('brotli.exe') else null,
    await _which('brotli'),
  ];

  for (final candidate in candidates) {
    if (candidate == null || candidate.isEmpty) {
      continue;
    }
    final file = File(candidate);
    if (await file.exists()) {
      configureBrotliCliPath(file.path);
      return;
    }
  }

  fail(
    'Brotli CLI not found. Install the "brotli" command or set BROTLI_CLI.',
  );
}

Future<String?> _which(String command) async {
  try {
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      [command],
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      return null;
    }
    final stdout = result.stdout is String
        ? result.stdout as String
        : String.fromCharCodes(result.stdout as List<int>);
    final path = stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return path.isEmpty ? null : path;
  } catch (_) {
    return null;
  }
}
