// ignore_for_file: avoid_print
// このスクリプトはデモ/テスト用であり、実行時の進捗表示が重要なためprintを使用します。

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:argus/qr/geojson_qr_codec.dart';

/// map.geojsonをQRコードにエンコードして保存し、復元してGeoJSONを保存するデモスクリプト
Future<void> main(List<String> args) async {
  try {
    // プロジェクトルートを取得
    final scriptDir = path.dirname(Platform.script.toFilePath());
    final projectRoot = path.dirname(scriptDir);

    // 入力ファイルのパス
    final inputGeoJsonPath = path.join(
      projectRoot,
      'assets',
      'geojson',
      'map.geojson',
    );

    // 出力ディレクトリ
    final outputDir = path.join(scriptDir, 'output');
    await Directory(outputDir).create(recursive: true);

    print('読み込み中: $inputGeoJsonPath');
    final inputGeoJson = await File(inputGeoJsonPath).readAsString();
    print('元のGeoJSONサイズ: ${inputGeoJson.length} bytes');

    // GeoJSONをQRコードにエンコード
    print('\nエンコード中...');
    final bundle = await encodeGeoJson(
      GeoJsonQrEncodeInput(
        geoJson: inputGeoJson,
        enableHash: true,
        maxQrTextLength: 2500,
        eccLevel: QrErrorCorrectionLevel.quartile,
        generatePng: true,
        modulePixelSize: 8,
        quietZoneModules: 4,
      ),
    );

    print('エンコード完了:');
    print('  - 最小化されたGeoJSONサイズ: ${bundle.minimizedGeoJson.length} bytes');
    print('  - QRコードテキスト数: ${bundle.chunkCount}');
    print('  - 分割QR: ${bundle.isSplit ? "はい" : "いいえ"}');
    print('  - ハッシュ: ${bundle.hashHex}');
    print('  - GeoJSONタイプ: ${bundle.info.type}');
    if (bundle.info.featureCount != null) {
      print('  - フィーチャ数: ${bundle.info.featureCount}');
    }

    // QRコードのPNG画像を保存
    print('\nQRコード画像を保存中...');
    for (var i = 0; i < bundle.pngImages.length; i++) {
      final pngPath = path.join(
        outputDir,
        bundle.chunkCount == 1 ? 'qr.png' : 'qr_${i + 1}.png',
      );
      await File(pngPath).writeAsBytes(bundle.pngImages[i]);
      print('  保存: $pngPath (${bundle.pngImages[i].length} bytes)');
    }

    // QRコードテキストを保存（デバッグ用）
    final qrTextPath = path.join(outputDir, 'qr_texts.txt');
    final qrTextsContent = bundle.qrTexts
        .asMap()
        .entries
        .map((e) => 'QR ${e.key + 1}:\n${e.value}\n')
        .join('\n---\n\n');
    await File(qrTextPath).writeAsString(qrTextsContent);
    print('  QRコードテキスト保存: $qrTextPath');

    // QRコードテキストからGeoJSONを復元
    print('\n復元中...');
    final restoredGeoJson = await decodeGeoJson(
      GeoJsonQrDecodeInput(
        qrTexts: bundle.qrTexts,
        verifyHash: true,
      ),
    );

    print('復元完了:');
    print('  - 復元されたGeoJSONサイズ: ${restoredGeoJson.length} bytes');

    // 復元したGeoJSONを整形して保存
    final restoredPath = path.join(outputDir, 'restored_map.geojson');
    final restoredJson = jsonDecode(restoredGeoJson);
    final formattedGeoJson =
        const JsonEncoder.withIndent('    ').convert(restoredJson);
    await File(restoredPath).writeAsString(formattedGeoJson);
    print('  保存: $restoredPath');

    // 検証: 元のGeoJSONと復元されたGeoJSONが一致するか確認
    final originalMinimized = minifyGeoJson(inputGeoJson).minimized;
    if (originalMinimized == restoredGeoJson) {
      print('\n✓ 検証成功: 元のGeoJSONと復元されたGeoJSONが一致しました');
    } else {
      print('\n✗ 検証失敗: 元のGeoJSONと復元されたGeoJSONが一致しません');
      print('  元のサイズ: ${originalMinimized.length} bytes');
      print('  復元のサイズ: ${restoredGeoJson.length} bytes');
    }

    print('\n完了！出力ディレクトリ: $outputDir');
  } catch (e, stackTrace) {
    print('エラーが発生しました:');
    print(e);
    print('\nスタックトレース:');
    print(stackTrace);
    exitCode = 1;
  }
}
