import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:argus/qr/geojson_qr_codec.dart';
import 'package:argus/geo/geojson_validator.dart';
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
    String? savedName;
    String? sharedName;
    GeoJsonQrScheme? requestedScheme;
    String? requestedFileName;

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
            requestedFileName = input.sourceFileName;
            return GeoJsonQrBundle(
              qrTexts: const ['agz1:test'],
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
            savedName = name;
          },
          shareHandler: (bytes, fileName, context) async {
            shared = true;
            sharedName = fileName;
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
    expect(requestedScheme, GeoJsonQrScheme.agz1);
    expect(requestedFileName, 'course.geojson');
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('共有'), findsOneWidget);
    expect(find.text('course'), findsOneWidget);
    expect(find.text('agz1'), findsNothing);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(savedName, 'QR_course.png');
    expect(find.text('写真に保存しました'), findsOneWidget);

    await tester.tap(find.text('共有'));
    await tester.pumpAndSettle();
    expect(shared, isTrue);
    expect(sharedName, 'QR_course.png');
  });

  testWidgets('101-vertex QR remains available with a Garmin warning',
      (tester) async {
    final raw = File('test/fixtures/geojson_validation/vertices-101.geojson')
        .readAsStringSync();
    await tester.pumpWidget(MaterialApp(
      home: QrGeneratorPage(
        filePicker: () async => XFile.fromData(
          utf8.encode(raw),
          name: 'vertices-101.geojson',
          path: 'vertices-101.geojson',
        ),
      ),
    ));

    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('generated_qr_image')), findsOneWidget);
    expect(find.textContaining('Garmin非対応'), findsOneWidget);
    expect(find.textContaining('101点'), findsOneWidget);
    expect(find.text('スマホで使えます'), findsOneWidget);
    expect(find.text('頂点数が101点です。Garmin上限は100点です。'), findsNothing);
  });

  testWidgets(
      'QR rounding shows a short compatibility reason with details hidden',
      (tester) async {
    final raw = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [139.00000051, 35],
                [139.00001149, 35],
                [139.00001149, 35.00005],
                [139.00000051, 35.00005],
                [139.00000051, 35],
              ]
            ],
          },
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(
        home: QrGeneratorPage(
      filePicker: () async => XFile.fromData(utf8.encode(raw),
          name: 'narrow.geojson', path: 'narrow.geojson'),
    )));
    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('generated_qr_image')), findsOneWidget);
    expect(find.text('スマホで使えます'), findsOneWidget);
    expect(find.text('スマホ・Garminで使えます'), findsNothing);
    expect(
        find.text('Garmin非対応: 細い部分があるため、Garminでは範囲を再現できません。'), findsOneWidget);
    expect(find.textContaining('1m座標'), findsNothing);
    expect(find.textContaining('Feature 1'), findsNothing);
    expect(find.text('スキーム'), findsNothing);
    await tester.ensureVisible(find.text('詳細'));
    await tester.tap(find.text('詳細'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1m座標'), findsOneWidget);
    expect(find.text('形状の警告'), findsWidgets);
  });

  testWidgets('compatible QR shows one device summary', (tester) async {
    final raw = File('test/fixtures/geojson_validation/valid-square.geojson')
        .readAsStringSync();
    await tester.pumpWidget(MaterialApp(
        home: QrGeneratorPage(
      filePicker: () async => XFile.fromData(utf8.encode(raw),
          name: 'square.geojson', path: 'square.geojson'),
    )));
    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();
    expect(find.text('スマホ・Garminで使えます'), findsOneWidget);
    expect(find.textContaining('Garmin非対応'), findsNothing);
    expect(find.text('スキーム'), findsNothing);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('共有'), findsOneWidget);
  });

  testWidgets('rejects encoder output without a single PNG image',
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
            qrTexts: const ['gjz1:test'],
            pngImages: const [],
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

  testWidgets('cancelled file selection clears generating state',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrGeneratorPage(
          filePicker: () async => null,
        ),
      ),
    );

    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(find.text('GeoJSONを選択'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated_qr_image')), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(find.text('共有'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('surfaces GeoJSON QR generation errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrGeneratorPage(
          filePicker: () async => XFile.fromData(
            utf8.encode(_squareGeoJson),
            name: 'course.geojson',
            mimeType: 'application/geo+json',
            path: 'course.geojson',
          ),
          encoder: (input) async => throw QrGenerationException('too large'),
        ),
      ),
    );

    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(find.textContaining('QRコードの生成に失敗しました'), findsOneWidget);
    expect(find.textContaining('too large'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated_qr_image')), findsNothing);
  });

  testWidgets('self-intersection errors identify the feature, ring and edges',
      (tester) async {
    final raw = File('test/fixtures/geojson_validation/bow-tie.geojson')
        .readAsStringSync();
    await tester.pumpWidget(MaterialApp(
      home: QrGeneratorPage(
        filePicker: () async => XFile.fromData(utf8.encode(raw),
            name: 'bow-tie.geojson', path: 'bow-tie.geojson'),
      ),
    ));
    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Feature 1 / Polygon 1 / ring 1 / 辺 1 / 辺 3'),
        findsOneWidget);
    expect(find.textContaining('自己交差または接触'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated_qr_image')), findsNothing);
  });

  testWidgets('vertex limit errors display actual and maximum counts',
      (tester) async {
    final count = GeoJsonValidator.maxVertices + 1;
    final decoded = jsonDecode(_squareGeoJson) as Map<String, dynamic>;
    final ring = List.generate(count, (index) {
      final angle = index * 2 * math.pi / count;
      return [139 + 0.001 * math.cos(angle), 35 + 0.001 * math.sin(angle)];
    });
    ring.add(ring.first);
    decoded['features'][0]['geometry']['coordinates'] = [ring];
    await tester.pumpWidget(MaterialApp(
      home: QrGeneratorPage(
        filePicker: () async => XFile.fromData(utf8.encode(jsonEncode(decoded)),
            name: 'large.geojson', path: 'large.geojson'),
      ),
    ));
    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(find.textContaining('頂点数が$count点'), findsOneWidget);
    expect(find.textContaining('上限${GeoJsonValidator.maxVertices}点'),
        findsOneWidget);
    expect(find.textContaining('?点'), findsNothing);
    expect(find.byKey(const ValueKey('generated_qr_image')), findsNothing);
  });

  testWidgets('surfaces GeoJSON format errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrGeneratorPage(
          filePicker: () async => XFile.fromData(
            utf8.encode(_squareGeoJson),
            name: 'course.geojson',
            mimeType: 'application/geo+json',
            path: 'course.geojson',
          ),
          encoder: (input) async => throw const FormatException('bad json'),
        ),
      ),
    );

    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(find.textContaining('GeoJSONの形式が正しくありません'), findsOneWidget);
    expect(find.textContaining('bad json'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated_qr_image')), findsNothing);
  });

  testWidgets('surfaces unexpected generation errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrGeneratorPage(
          filePicker: () async => XFile.fromData(
            utf8.encode(_squareGeoJson),
            name: 'course.geojson',
            mimeType: 'application/geo+json',
            path: 'course.geojson',
          ),
          encoder: (input) async => throw Exception('boom'),
        ),
      ),
    );

    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('QRコードの生成中にエラーが発生しました'),
      findsOneWidget,
    );
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated_qr_image')), findsNothing);
  });

  testWidgets('renders preview without optional hash and feature count',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrGeneratorPage(
          filePicker: () async => XFile.fromData(
            utf8.encode(_squareGeoJson),
            name: '',
            mimeType: 'application/geo+json',
            path: 'fallback.geojson',
          ),
          encoder: (input) async => GeoJsonQrBundle(
            qrTexts: const ['payload-without-prefix'],
            pngImages: [qrPng],
            minimizedGeoJson: '{"type":"Point","coordinates":[0,0]}',
            hashHex: null,
            info: const GeoJsonInfo(type: 'Point'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('GeoJSONを選択'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('generated_qr_image')), findsOneWidget);
    expect(find.text('fallback'), findsOneWidget);
    await tester.ensureVisible(find.text('詳細'));
    await tester.tap(find.text('詳細'));
    await tester.pumpAndSettle();
    expect(find.text('Point'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('ハッシュ'), findsNothing);
    expect(find.text('フィーチャ数'), findsNothing);
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
