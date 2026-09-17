import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outputDir = Directory('build/integration_test/screenshots')
    ..createSync(recursive: true);

  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final reportDir = Platform.environment['E2E_REPORT_DIR'];
      if (reportDir != null) {
        final counts = data?['e2eSuiteCounts'];
        await File('$reportDir/test-results.json').writeAsString(
          const JsonEncoder.withIndent('  ')
              .convert({'e2eSuiteCounts': counts}),
        );
        final suites = await File('$reportDir/suites.txt').readAsLines();
        if (counts is! Map ||
            suites.any((suite) => counts[suite] is! int || counts[suite] < 1)) {
          throw StateError(
              'Not every discovered E2E suite completed; see test-results.json');
        }
        stdout.writeln('E2E suite counts: $counts');
      }
      await writeResponseData(data);
    },
    onScreenshot: (String name, List<int> screenshot,
        [Map<String, Object?>? _]) async {
      final file = File('${outputDir.path}/$name.png');
      await file.writeAsBytes(screenshot, flush: true);
      return true;
    },
  );
}
