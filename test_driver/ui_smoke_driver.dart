import 'dart:async';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outputDir =
      Directory('build/integration_test/screenshots')..createSync(recursive: true);

  await integrationDriver(
    onScreenshot: (String name, List<int> screenshot, [Map<String, Object?>? _]) async {
      final file = File('${outputDir.path}/$name.png');
      await file.writeAsBytes(screenshot, flush: true);
      return true;
    },
  );
}
