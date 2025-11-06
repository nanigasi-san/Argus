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

    expect(bundle.isSplit, isFalse);
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

  test('encode triggers gjb1p split when max length is low', () async {
    final bundle = await encodeGeoJson(
      GeoJsonQrEncodeInput(
        geoJson: sampleGeoJson,
        maxQrTextLength: 80,
      ),
    );

    expect(bundle.isSplit, isTrue);
    expect(bundle.qrTexts.length, greaterThan(1));
    expect(bundle.qrTexts.every((text) => text.startsWith('gjb1p:')), isTrue);

    final restored =
        await decodeGeoJson(GeoJsonQrDecodeInput(qrTexts: bundle.qrTexts));
    expect(restored, bundle.minimizedGeoJson);
  });

  test('decode fails when a gjb1p chunk is missing', () async {
    final bundle = await encodeGeoJson(
      GeoJsonQrEncodeInput(
        geoJson: sampleGeoJson,
        maxQrTextLength: 80,
      ),
    );

    final tampered = List<String>.from(bundle.qrTexts)..removeAt(0);

    await expectLater(
      decodeGeoJson(GeoJsonQrDecodeInput(qrTexts: tampered)),
      throwsA(isA<ChunkMismatchException>()),
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
