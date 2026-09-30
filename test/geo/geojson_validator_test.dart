import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:argus/garmin/garmin_course_selection.dart';
import 'package:argus/garmin/garmin_course_validator.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/geo/geojson_validator.dart';
import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) =>
    File('test/fixtures/geojson_validation/$name.geojson').readAsStringSync();

Set<String> codes(GeoJsonValidationResult result) =>
    result.issues.map((issue) => issue.code).toSet();

void main() {
  const phone = GeoJsonValidator();
  const garmin = GarminCourseValidator();

  test(
      'decimal backtracking and zero-area rings are rejected in either winding',
      () {
    final rings = [
      [
        [139.1, 35.1],
        [139.3, 35.3],
        [139.2, 35.2],
        [139.0, 35.4],
      ],
      [
        [139.001, 35.001],
        [139.002, 35.002],
        [139.003, 35.003],
      ],
    ];
    for (final vertices in rings) {
      for (var start = 0; start < vertices.length; start++) {
        final rotated = [...vertices.skip(start), ...vertices.take(start)];
        for (final ordered in [rotated, rotated.reversed.toList()]) {
          final result = phone.validate(_document([
            [...ordered, ordered.first]
          ]));
          expect(result.validForPhone, isFalse);
          expect(codes(result), contains('E_SELF_INTERSECTION'));
          if (vertices.length == 3) {
            expect(codes(result), contains('E_ZERO_AREA'));
          }
        }
      }
    }
  });

  test('decimal non-adjacent vertex contact is rejected', () {
    final result = phone.validate(_document([
      [
        [139.1, 35.1],
        [139.3, 35.3],
        [139.1, 35.4],
        [139.2, 35.2],
        [139.0, 35.3],
        [139.1, 35.1],
      ],
    ]));
    expect(result.validForPhone, isFalse);
    expect(codes(result), contains('E_SELF_INTERSECTION'));
  });

  test('roundoff handling preserves small non-collinear geometry', () {
    final result = phone.validate(fixture('qr-precision-loss'));
    expect(result.validForPhone, isTrue);
    expect(codes(result), isNot(contains('E_ZERO_AREA')));
  });

  test('phone vertex limit excludes the closing point', () {
    expect(
        phone.validate(_document([_regularRing(1000)])).validForPhone, isTrue);
    for (final rings in [
      [_regularRing(1001)],
      [_regularRing(50000)],
    ]) {
      final result = phone.validate(_document(rings));
      expect(result.validForPhone, isFalse);
      expect(result.errors.single.code, 'E_PHONE_TOO_MANY_VERTICES');
      expect(result.errors.single.limit, 1000);
    }
  });

  test('phone, file and QR reject multiple features and even one MultiPolygon',
      () async {
    final singleMultiPolygon =
        jsonDecode(_document([_regularRing(3)])) as Map<String, dynamic>;
    final geometry =
        singleMultiPolygon['features'][0]['geometry'] as Map<String, dynamic>;
    geometry['type'] = 'MultiPolygon';
    geometry['coordinates'] = [geometry['coordinates']];
    for (final raw in [
      _document([_regularRing(3), _regularRing(3)]),
      jsonEncode(singleMultiPolygon),
    ]) {
      final result = phone.validate(raw);
      expect(result.validForPhone, isFalse);
      expect(codes(result), contains('E_SINGLE_FEATURE_POLYGON_REQUIRED'));
      expect(() => GeoModel.fromGeoJson(raw), throwsFormatException);
      await expectLater(
          GarminCourseSelection.fromFile(
              XFile.fromData(utf8.encode(raw), name: 'multiple.geojson')),
          throwsFormatException);
      for (final scheme in GeoJsonQrScheme.values) {
        await expectLater(
          encodeGeoJson(GeoJsonQrEncodeInput(
              geoJson: raw,
              sourceFileName: 'multiple.geojson',
              scheme: scheme,
              generatePng: false)),
          throwsA(isA<UnsupportedGeometryException>()),
        );
      }
      final legacyQr =
          'gjz1:${base64UrlEncodeNoPad(gzipCompress(Uint8List.fromList(utf8.encode(raw))))}';
      await expectLater(
          GarminCourseSelection.fromQrText(legacyQr), throwsFormatException);
    }
  });

  test('QR compatibility follows the restored geometry after AGZ1 rounding',
      () async {
    final raw = _document([
      [
        [139.00000051, 35],
        [139.00001149, 35],
        [139.00001149, 35.00005],
        [139.00000051, 35.00005],
        [139.00000051, 35],
      ],
    ]);
    expect(garmin.validate(phone.validate(raw)).validForGarmin, isTrue);
    final bundle = await encodeGeoJson(GeoJsonQrEncodeInput(
        geoJson: raw,
        sourceFileName: 'narrow.geojson',
        scheme: GeoJsonQrScheme.agz1,
        generatePng: false));
    final restored =
        await GarminCourseSelection.fromQrText(bundle.qrTexts.single);
    expect(bundle.validation!.validForPhone, isTrue);
    expect(garmin.validate(bundle.validation!).validForGarmin, isFalse);
    expect(garmin.validate(bundle.validation!).issues.single.code,
        restored.garminValidation.issues.single.code);
    expect(restored.garminValidation.issues.single.code,
        'E_GARMIN_QUANTIZED_GEOMETRY');
  });

  test('saved GeoJSON cases have the expected phone and Garmin decisions', () {
    const expected =
        <String, ({bool phoneValid, bool garminValid, String? code})>{
      'valid-square': (phoneValid: true, garminValid: true, code: null),
      'vertices-3': (phoneValid: true, garminValid: true, code: null),
      'long-edge': (phoneValid: true, garminValid: true, code: 'W_LONG_EDGE'),
      'hole': (
        phoneValid: false,
        garminValid: false,
        code: 'E_HOLES_UNSUPPORTED'
      ),
      'empty-inner-ring': (
        phoneValid: false,
        garminValid: false,
        code: 'E_HOLES_UNSUPPORTED'
      ),
      'bow-tie': (
        phoneValid: false,
        garminValid: false,
        code: 'E_SELF_INTERSECTION'
      ),
      'vertex-touch': (
        phoneValid: false,
        garminValid: false,
        code: 'E_SELF_INTERSECTION'
      ),
      'overlapping-edge': (
        phoneValid: false,
        garminValid: false,
        code: 'E_SELF_INTERSECTION'
      ),
      'duplicate-consecutive': (
        phoneValid: false,
        garminValid: false,
        code: 'E_DUPLICATE_CONSECUTIVE_POINT'
      ),
      'open-ring': (
        phoneValid: false,
        garminValid: false,
        code: 'E_POLYGON_NOT_CLOSED'
      ),
      'collinear': (
        phoneValid: false,
        garminValid: false,
        code: 'E_SELF_INTERSECTION'
      ),
      'multi-polygon': (
        phoneValid: false,
        garminValid: false,
        code: 'E_SINGLE_FEATURE_POLYGON_REQUIRED'
      ),
      'tiny-area': (phoneValid: true, garminValid: true, code: 'W_TINY_AREA'),
      'qr-precision-loss': (
        phoneValid: true,
        garminValid: false,
        code: 'W_SHORT_EDGE'
      ),
      'invalid-coordinate': (
        phoneValid: false,
        garminValid: false,
        code: 'E_INVALID_COORDINATE'
      ),
      'vertices-100': (phoneValid: true, garminValid: true, code: null),
      'vertices-101': (
        phoneValid: true,
        garminValid: false,
        code: 'E_TOO_MANY_VERTICES'
      ),
    };
    for (final entry in expected.entries) {
      final result = phone.validate(fixture(entry.key));
      final watch = garmin.validate(result);
      expect(result.validForPhone, entry.value.phoneValid, reason: entry.key);
      expect(watch.validForGarmin, entry.value.garminValid, reason: entry.key);
      if (entry.value.code != null) {
        expect(
          {...codes(result), ...watch.issues.map((issue) => issue.code)},
          contains(entry.value.code),
          reason: entry.key,
        );
      }
    }
  });

  test('holes and intersections are rejected before GeoModel can discard them',
      () {
    for (final name in [
      'hole',
      'empty-inner-ring',
      'bow-tie',
      'vertex-touch',
      'overlapping-edge'
    ]) {
      expect(() => GeoModel.fromGeoJson(fixture(name)), throwsFormatException,
          reason: name);
    }
    expect(
        codes(phone.validate(fixture('collinear'))), contains('E_ZERO_AREA'));
  });

  test('same phone validator is used by file and QR creation/restoration',
      () async {
    final raw = fixture('valid-square');
    final direct = phone.validate(raw);
    final file = XFile.fromData(utf8.encode(raw),
        name: 'valid-square.geojson', path: 'valid-square.geojson');
    final fromFile = await GarminCourseSelection.fromFile(file);
    final bundle = await encodeGeoJson(GeoJsonQrEncodeInput(
        geoJson: raw,
        sourceFileName: 'valid-square.geojson',
        scheme: GeoJsonQrScheme.agz1,
        generatePng: false));
    final decoded = await decodeGeoJsonWithMetadata(
        GeoJsonQrDecodeInput(qrTexts: bundle.qrTexts));
    final fromQr =
        await GarminCourseSelection.fromQrText(bundle.qrTexts.single);
    expect(direct.validForPhone, isTrue);
    expect(bundle.validation!.validForPhone, isTrue);
    expect(phone.validate(decoded.geoJson).validForPhone, isTrue);
    expect(fromFile.validation!.validForPhone, isTrue);
    expect(fromQr.validation!.validForPhone, isTrue);
    expect(fromFile.garminValidation.validForGarmin, isTrue);
    expect(fromQr.garminValidation.validForGarmin, isTrue);
  });

  test('invalid source never produces a QR and precision loss is caught',
      () async {
    for (final name in ['hole', 'bow-tie', 'open-ring']) {
      await expectLater(
        encodeGeoJson(GeoJsonQrEncodeInput(
            geoJson: fixture(name),
            sourceFileName: '$name.geojson',
            scheme: GeoJsonQrScheme.agz1,
            generatePng: false)),
        throwsA(isA<GeoJsonQrException>()),
        reason: name,
      );
    }
    await expectLater(
      encodeGeoJson(GeoJsonQrEncodeInput(
          geoJson: fixture('qr-precision-loss'),
          sourceFileName: 'qr-precision-loss.geojson',
          scheme: GeoJsonQrScheme.agz1,
          generatePng: false)),
      throwsA(isA<GeoJsonQrException>()),
    );
  });

  test('101 vertices can be QR encoded but not sent to Garmin', () async {
    final raw = fixture('vertices-101');
    final result = phone.validate(raw);
    expect(result.validForPhone, isTrue);
    expect(garmin.validate(result).issues.single.code, 'E_TOO_MANY_VERTICES');
    final bundle = await encodeGeoJson(GeoJsonQrEncodeInput(
        geoJson: raw,
        sourceFileName: 'vertices-101.geojson',
        scheme: GeoJsonQrScheme.agz1,
        generatePng: false));
    expect(bundle.qrTexts, hasLength(1));
  });

  test('every saved case is exercised through AGZ1 creation and restoration',
      () async {
    const qrValid = {
      'valid-square',
      'vertices-3',
      'vertices-100',
      'vertices-101',
      'tiny-area',
      'long-edge',
    };
    final names = Directory('test/fixtures/geojson_validation')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last.replaceFirst('.geojson', ''));
    for (final name in names) {
      final future = encodeGeoJson(GeoJsonQrEncodeInput(
          geoJson: fixture(name),
          sourceFileName: '$name.geojson',
          scheme: GeoJsonQrScheme.agz1,
          generatePng: false));
      if (!qrValid.contains(name)) {
        await expectLater(future, throwsA(isA<GeoJsonQrException>()),
            reason: name);
        continue;
      }
      final bundle = await future;
      expect(bundle.qrTexts, hasLength(1), reason: name);
      final decoded = await decodeGeoJsonWithMetadata(
          GeoJsonQrDecodeInput(qrTexts: bundle.qrTexts));
      expect(phone.validate(decoded.geoJson).validForPhone, isTrue,
          reason: name);
    }
  });

  test('Garmin int16 projection boundary is checked before AGW encoding', () {
    String rectangle(double radiusMeters) {
      final lonScale = 111320 * math.cos(35 * math.pi / 180);
      final dx = radiusMeters / lonScale;
      return jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [139 - dx, 34.999],
                  [139 + dx, 34.999],
                  [139 + dx, 35.001],
                  [139 - dx, 35.001],
                  [139 - dx, 34.999]
                ]
              ]
            }
          }
        ]
      });
    }

    final inside = phone.validate(rectangle(32766));
    final outside = phone.validate(rectangle(32769));
    expect(inside.validForPhone, isTrue);
    expect(outside.validForPhone, isTrue);
    expect(garmin.validate(inside).validForGarmin, isTrue);
    expect(
        garmin.validate(outside).issues.single.code, 'E_LOCAL_COORD_OVERFLOW');
  });

  test('opposite ring winding alone does not invalidate the polygon', () {
    final document =
        jsonDecode(fixture('valid-square')) as Map<String, dynamic>;
    final feature =
        (document['features'] as List).single as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final ring = (geometry['coordinates'] as List).single as List;
    geometry['coordinates'] = [ring.reversed.toList()];

    final result = phone.validate(jsonEncode(document));
    expect(result.validForPhone, isTrue);
    expect(garmin.validate(result).validForGarmin, isTrue);
  });
}

String _document(List<List<List<num>>> rings) => jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final ring in rings)
          {
            'type': 'Feature',
            'properties': {},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [ring]
            },
          },
      ],
    });

List<List<num>> _regularRing(int count) {
  final vertices = List.generate(
      count,
      (i) => <num>[
            139 + 0.01 * math.cos(2 * math.pi * i / count),
            35 + 0.01 * math.sin(2 * math.pi * i / count),
          ]);
  return [...vertices, vertices.first];
}
