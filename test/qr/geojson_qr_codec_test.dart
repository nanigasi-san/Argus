import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sampleGeoJson;

  setUpAll(() async {
    final file = File('assets/geojson/map.geojson');
    sampleGeoJson = file.readAsStringSync();
  });

  test('minifyGeoJson removes whitespace and keeps structure', () {
    final result = minifyGeoJson(sampleGeoJson);
    expect(result.minimized.contains('\n'), isFalse);
    expect(result.info.type, 'FeatureCollection');
    expect(result.info.featureCount, 1);
  });

  test('default encode and decode gjz1 round trip with hash succeeds',
      () async {
    final bundle =
        await encodeGeoJson(GeoJsonQrEncodeInput(geoJson: sampleGeoJson));

    expect(bundle.qrTexts, hasLength(1));
    expect(bundle.qrTexts, hasLength(1));
    expect(bundle.qrTexts.first.startsWith('gjz1:'), isTrue);
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

  test('agz1 round trip preserves six-digit coordinates and filename',
      () async {
    final bundle = await encodeGeoJson(
      const GeoJsonQrEncodeInput(
        geoJson: _agzGeoJson,
        sourceFileName: r'C:\courses\hoge.json',
        scheme: GeoJsonQrScheme.agz1,
        generatePng: false,
      ),
    );

    expect(bundle.qrTexts.single, startsWith('agz1:'));
    expect(bundle.hashHex, isNull);
    final payload = bundle.qrTexts.single.substring('agz1:'.length);
    final diffText = utf8.decode(gzipDecompress(base64UrlDecodeNoPad(payload)));
    expect(diffText, startsWith('a3:6:'));

    final restored = await decodeGeoJsonWithMetadata(
      GeoJsonQrDecodeInput(qrTexts: bundle.qrTexts),
    );
    expect(restored.fileName, 'hoge.geojson');
    final decoded = jsonDecode(restored.geoJson) as Map<String, dynamic>;
    final ring = ((decoded['features'] as List).single['geometry']
            ['coordinates'] as List)
        .single as List;
    expect(
      ring,
      const [
        [140.123456, 35.123456],
        [140.223456, 35.123456],
        [140.223456, 35.223456],
        [140.123456, 35.123456],
      ],
    );
  });

  test('agz1 is smaller than the sample GeoJSON and is recognized', () async {
    final bundle = await encodeGeoJson(
      GeoJsonQrEncodeInput(
        geoJson: sampleGeoJson,
        sourceFileName: 'map.geojson',
        scheme: GeoJsonQrScheme.agz1,
        generatePng: false,
      ),
    );

    expect(bundle.qrTexts.single.length,
        lessThan(utf8.encode(sampleGeoJson).length));
    expect(isSupportedGeoJsonQrText(bundle.qrTexts.single), isTrue);
    expect(isSupportedGeoJsonQrText('gjz1:test'), isTrue);
  });

  test('agz1 rejects unsupported geometry shapes', () async {
    Future<void> expectUnsupported(String geoJson) async {
      await expectLater(
        encodeGeoJson(
          GeoJsonQrEncodeInput(
            geoJson: geoJson,
            sourceFileName: 'hoge.geojson',
            scheme: GeoJsonQrScheme.agz1,
            generatePng: false,
          ),
        ),
        throwsA(isA<UnsupportedGeometryException>()),
      );
    }

    await expectUnsupported(
        _agzGeoJson.replaceFirst('"Polygon"', '"MultiPolygon"'));
    await expectUnsupported(_featureCollectionWithFeatures('[{},{}]'));
    await expectUnsupported(
      _agzGeoJson.replaceFirst(
        '[[[140.123456',
        '[[[0,0],[1,0],[0,0]],[[140.123456',
      ),
    );
  });

  test('agz1 rejects missing filename, too few points, and open polygon',
      () async {
    await expectLater(
      encodeGeoJson(
        const GeoJsonQrEncodeInput(
          geoJson: _agzGeoJson,
          scheme: GeoJsonQrScheme.agz1,
          generatePng: false,
        ),
      ),
      throwsA(isA<InvalidFileNameException>()),
    );
    await expectLater(
      encodeGeoJson(
        const GeoJsonQrEncodeInput(
          geoJson: _tooFewPointsGeoJson,
          sourceFileName: 'hoge.geojson',
          scheme: GeoJsonQrScheme.agz1,
          generatePng: false,
        ),
      ),
      throwsA(isA<TooFewPointsException>()),
    );
    await expectLater(
      encodeGeoJson(
        const GeoJsonQrEncodeInput(
          geoJson: _openPolygonGeoJson,
          sourceFileName: 'hoge.geojson',
          scheme: GeoJsonQrScheme.agz1,
          generatePng: false,
        ),
      ),
      throwsA(isA<PolygonNotClosedException>()),
    );
  });

  test('agz1 reports corrupt payload categories', () async {
    await expectLater(
      decodeGeoJsonWithMetadata(
        const GeoJsonQrDecodeInput(qrTexts: ['agz1:@@@@']),
      ),
      throwsA(isA<Base64DecodeFailedException>()),
    );
    await expectLater(
      decodeGeoJsonWithMetadata(
        GeoJsonQrDecodeInput(
          qrTexts: ['agz1:${base64UrlEncodeNoPad(utf8.encode('not gzip'))}'],
        ),
      ),
      throwsA(isA<GzipDecompressFailedException>()),
    );
    await expectLater(
      decodeGeoJsonWithMetadata(
        GeoJsonQrDecodeInput(qrTexts: [_agzQrText('a2:6:x:1,1|1,1')]),
      ),
      throwsA(isA<InvalidDiffTextException>()),
    );
    await expectLater(
      decodeGeoJsonWithMetadata(
        GeoJsonQrDecodeInput(
            qrTexts: [_agzQrText('a3:x:aG9nZS5nZW9qc29u:1,1|1,1;1,1;-2,-2')]),
      ),
      throwsA(isA<InvalidScaleException>()),
    );
    await expectLater(
      decodeGeoJsonWithMetadata(
        GeoJsonQrDecodeInput(
            qrTexts: [_agzQrText('a3:6:aG9nZS5nZW9qc29u:1,x|1,1;1,1;-2,-2')]),
      ),
      throwsA(isA<InvalidCoordinateException>()),
    );
    await expectLater(
      decodeGeoJsonWithMetadata(
        GeoJsonQrDecodeInput(qrTexts: [_agzQrText('a3:6::1,1|1,1;1,1;-2,-2')]),
      ),
      throwsA(isA<InvalidFileNameException>()),
    );
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
      decodeGeoJson(const GeoJsonQrDecodeInput(qrTexts: ['abc1:@@@@'])),
      throwsA(isA<UnsupportedSchemeException>()),
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
    expect(bundle.qrTexts.single, startsWith('gjz1:'));
    expect(bundle.qrTexts.single.contains('#'), isFalse);
  });

  test('decode rejects empty input and empty gjz1 payload', () async {
    await expectLater(
      decodeGeoJson(const GeoJsonQrDecodeInput(qrTexts: [])),
      throwsA(isA<UnsupportedSchemeException>()),
    );
    await expectLater(
      decodeGeoJson(const GeoJsonQrDecodeInput(qrTexts: ['gjz1:'])),
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
        const GeoJsonQrDecodeInput(qrTexts: ['abc1:payload#xyz']),
      ),
      throwsA(isA<UnsupportedSchemeException>()),
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

const _agzGeoJson = '{"type":"FeatureCollection","features":[{"type":"Feature",'
    '"properties":{"ignored":true},"geometry":{"type":"Polygon",'
    '"coordinates":[[[140.123456,35.123456],[140.223456,35.123456],'
    '[140.223456,35.223456],[140.123456,35.123456]]]}}]}';

const _tooFewPointsGeoJson =
    '{"type":"FeatureCollection","features":[{"type":"Feature",'
    '"properties":{},"geometry":{"type":"Polygon",'
    '"coordinates":[[[0,0],[1,0],[0,0]]]}}]}';

const _openPolygonGeoJson =
    '{"type":"FeatureCollection","features":[{"type":"Feature",'
    '"properties":{},"geometry":{"type":"Polygon",'
    '"coordinates":[[[0,0],[1,0],[1,1],[0,1]]]}}]}';

String _featureCollectionWithFeatures(String features) =>
    '{"type":"FeatureCollection","features":$features}';

String _agzQrText(String diffText) {
  final compressed = gzipCompress(Uint8List.fromList(utf8.encode(diffText)));
  return 'agz1:${base64UrlEncodeNoPad(compressed)}';
}
