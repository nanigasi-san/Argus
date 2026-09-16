import 'dart:async';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final simulator = Platform.environment['ARGUS_SIMULATOR_ID'];
  var tick = 0;
  if (simulator != null) {
    for (final permission in ['location', 'location-always']) {
      final result = await Process.run('xcrun', [
        'simctl',
        'privacy',
        simulator,
        'grant',
        permission,
        'com.argus.orienteering',
      ]);
      if (result.exitCode != 0) throw StateError('${result.stderr}');
    }
  }
  Future<void> updateLocation() async {
    if (simulator == null) return;
    // Screenshots are delivered only after mobile tests finish. Alternate
    // twenty-second route legs independently of screenshot callbacks.
    final inside = (tick ~/ 10).isOdd;
    final longitude = inside ? 0.5 : 1.001 + (tick % 2) * 0.00001;
    tick++;
    final result = await Process.run('xcrun', [
      'simctl',
      'location',
      simulator,
      'set',
      '0.5,$longitude',
    ]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
  }

  await updateLocation();
  final timer = simulator == null
      ? null
      : Timer.periodic(const Duration(seconds: 2), (_) async {
          await updateLocation();
        });
  Future<void> cleanup() async {
    timer?.cancel();
    if (simulator != null) {
      await Process.run('xcrun', ['simctl', 'location', simulator, 'clear']);
    }
  }

  try {
    await integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final output = File('build/integration_test/screenshots/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes);
        return true;
      },
      writeResponseOnFailure: true,
      // integrationDriver exits the process, so clean up before it exits.
      responseDataCallback: (_) async => cleanup(),
    );
  } finally {
    await cleanup();
  }
}
