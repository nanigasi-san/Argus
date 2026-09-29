import 'dart:convert';

import 'package:argus/garmin/garmin_course_selection.dart';
import 'package:argus/geo/geo_model.dart';
import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

const _courseGeoJson = '''
{"type":"FeatureCollection","features":[{"type":"Feature","properties":{},
"geometry":{"type":"Polygon","coordinates":[[[139,35],[139.001,35],[139,35.001],[139,35]]]}}]}
''';

void main() {
  test('file selection reads and validates a transfer course', () async {
    final file = XFile.fromData(
      utf8.encode(_courseGeoJson),
      name: 'area.geojson',
      path: 'area.geojson',
      mimeType: 'application/geo+json',
    );
    final selected = await GarminCourseSelection.fromFile(file);
    expect(selected.fileName, 'area.geojson');
    expect(selected.model.polygons, hasLength(1));
    expect(
        selected.hasSameGeometry(GeoModel.fromGeoJson(_courseGeoJson)), isTrue);
  });

  test('QR selection preserves the embedded filename', () async {
    final bundle = await encodeGeoJson(const GeoJsonQrEncodeInput(
      geoJson: _courseGeoJson,
      sourceFileName: 'race.geojson',
      scheme: GeoJsonQrScheme.agz1,
      generatePng: false,
    ));
    final selected =
        await GarminCourseSelection.fromQrText(bundle.qrTexts.single);
    expect(selected.fileName, 'race.geojson');
    expect(selected.model.polygons, hasLength(1));
  });

  test('invalid QR leaves the phone model untouched', () async {
    final phoneModel = GeoModel.fromGeoJson(_courseGeoJson);
    await expectLater(
      GarminCourseSelection.fromQrText('gjz1:invalid_payload'),
      throwsA(isA<GeoJsonQrException>()),
    );
    expect(phoneModel.polygons, hasLength(1));
  });
}
