import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
        phoneValid: true,
        garminValid: false,
        code: 'E_GARMIN_SINGLE_POLYGON'
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
