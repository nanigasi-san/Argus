import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:argus/ui/qr_generator_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List qrPng;

  setUpAll(() {
    qrPng = generateQrPng('gjz1:test', QrErrorCorrectionLevel.quartile);
  });

  testWidgets('generates single QR and enables save and share actions',
      (tester) async {
    var saved = false;
    var shared = false;
    GeoJsonQrScheme? requestedScheme;

    await tester.pumpWidget(
      MaterialApp(
        home: QrGeneratorPage(
          filePicker: () async => XFile.fromData(
            utf8.encode(_squareGeoJson),
            name: 'course.geojson',
            mimeType: 'application/geo+json',
            path: 'course.geojson',
          ),
          encoder: (input) async {
            requestedScheme = input.scheme;
            return GeoJsonQrBundle(
              qrTexts: const ['gjz1:test'],
              pngImages: [qrPng],
              minimizedGeoJson: '{"type":"FeatureCollection","features":[]}',
              hashHex: 'a' * 64,
              info: const GeoJsonInfo(
                type: 'FeatureCollection',
                featureCount: 0,
              ),
            );
          },
          gallerySaver: (bytes, name) async {
            saved = true;
          },
          shareHandler: (bytes, fileName, context) async {
            shared = true;
          },
        ),
      ),
    );

    expect(find.text('GeoJSONを選択'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    expect(find.text('共有'), findsNothing);

    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('generated_qr_image')), findsOneWidget);
    expect(requestedScheme, GeoJsonQrScheme.gjz1);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('共有'), findsOneWidget);
    expect(find.text('course.geojson'), findsOneWidget);
    expect(find.text('gjz1'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(find.text('写真に保存しました'), findsOneWidget);

    await tester.tap(find.text('共有'));
    await tester.pumpAndSettle();
    expect(shared, isTrue);
  });

  testWidgets('rejects split QR output and disables generated actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrGeneratorPage(
          filePicker: () async => XFile.fromData(
            utf8.encode(_squareGeoJson),
            name: 'large.geojson',
            mimeType: 'application/geo+json',
            path: 'large.geojson',
          ),
          encoder: (input) async => GeoJsonQrBundle(
            qrTexts: const ['gjz1p:1/2:a', 'gjz1p:2/2:b'],
            pngImages: [qrPng, qrPng],
            minimizedGeoJson: '{"type":"FeatureCollection","features":[]}',
            hashHex: null,
            info: const GeoJsonInfo(
              type: 'FeatureCollection',
              featureCount: 0,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1枚のQRに収まりません'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated_qr_image')), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(find.text('共有'), findsNothing);
  });

  testWidgets('surfaces save and share failures with SnackBars',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrGeneratorPage(
          filePicker: () async => XFile.fromData(
            utf8.encode(_squareGeoJson),
            name: 'course.geojson',
            mimeType: 'application/geo+json',
            path: 'course.geojson',
          ),
          encoder: (input) async => GeoJsonQrBundle(
            qrTexts: const ['gjz1:test'],
            pngImages: [qrPng],
            minimizedGeoJson: '{"type":"FeatureCollection","features":[]}',
            hashHex: null,
            info: const GeoJsonInfo(
              type: 'FeatureCollection',
              featureCount: 0,
            ),
          ),
          gallerySaver: (bytes, name) async => throw Exception('save failed'),
          shareHandler: (bytes, fileName, context) async =>
              throw Exception('share failed'),
        ),
      ),
    );

    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存に失敗しました'), findsOneWidget);

    ScaffoldMessenger.of(
      tester.element(find.byType(QrGeneratorPage)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('共有'));
    await tester.pumpAndSettle();
    expect(find.textContaining('共有に失敗しました'), findsOneWidget);
  });
}

const String _squareGeoJson = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {"name": "Test Area"},
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[0,0],[1,0],[1,1],[0,1],[0,0]]]
      }
    }
  ]
}
''';
