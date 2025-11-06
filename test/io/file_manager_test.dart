import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:argus/io/config.dart';
import 'package:argus/io/file_manager.dart';

void main() {
  group('FileManager', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('argus_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('pickGeoJsonFile delegates to file selector with filters', () async {
      List<XTypeGroup>? capturedGroups;
      final manager = FileManager(
        filePicker: ({acceptedTypeGroups}) async {
          capturedGroups = acceptedTypeGroups;
          return XFile.fromData(
            Uint8List(0),
            name: 'example.geojson',
          );
        },
      );

      final file = await manager.pickGeoJsonFile();

      expect(file, isNotNull);
      expect(file!.name, 'example.geojson');
      expect(capturedGroups, isNotNull);
      expect(capturedGroups!.single.extensions,
          containsAll(const ['geojson', 'json', 'bin']));
    });

    test('getConfigFile creates file with default config', () async {
      final defaultConfig = AppConfig(
        innerBufferM: 10,
        leaveConfirmSamples: 2,
        leaveConfirmSeconds: 3,
        gpsAccuracyBadMeters: 25,
        sampleIntervalS: const {'fast': 2},
        sampleDistanceM: const {'fast': 5},
        screenWakeOnLeave: true,
      );

      final manager = FileManager(
        documentsDirectoryProvider: () async => tempDir,
        defaultConfigLoader: () async => defaultConfig,
      );

      final file = await manager.getConfigFile();
      expect(await file.exists(), isTrue);

      final contents = await file.readAsString();
      final decoded = jsonDecode(contents) as Map<String, dynamic>;
      expect(decoded['inner_buffer_m'], 10);
      expect(decoded['screen_wake_on_leave'], isTrue);
    });

    test('saveConfig overwrites existing file', () async {
      final manager = FileManager(
        documentsDirectoryProvider: () async => tempDir,
        defaultConfigLoader: () async => AppConfig(
          innerBufferM: 1,
          leaveConfirmSamples: 1,
          leaveConfirmSeconds: 1,
          gpsAccuracyBadMeters: 1,
          sampleIntervalS: const {'fast': 1},
          sampleDistanceM: const {'fast': 1},
          screenWakeOnLeave: false,
        ),
      );

      final newConfig = AppConfig(
        innerBufferM: 42,
        leaveConfirmSamples: 5,
        leaveConfirmSeconds: 7,
        gpsAccuracyBadMeters: 13,
        sampleIntervalS: const {'fast': 4},
        sampleDistanceM: const {'fast': 9},
        screenWakeOnLeave: true,
      );

      final file = await manager.getConfigFile();
      await manager.saveConfig(newConfig);

      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(decoded['inner_buffer_m'], 42);
      expect(decoded['leave_confirm_samples'], 5);
      expect(decoded['screen_wake_on_leave'], isTrue);
    });

    test('readConfig falls back to default on malformed file', () async {
      final manager = FileManager(
        documentsDirectoryProvider: () async => tempDir,
        defaultConfigLoader: () async => AppConfig(
          innerBufferM: 3,
          leaveConfirmSamples: 2,
          leaveConfirmSeconds: 9,
          gpsAccuracyBadMeters: 12,
          sampleIntervalS: const {'fast': 3},
          sampleDistanceM: const {'fast': 8},
          screenWakeOnLeave: false,
        ),
      );

      final file = File('${tempDir.path}/config.json');
      await file.writeAsString('not json');

      final config = await manager.readConfig();
      expect(config.innerBufferM, 3);
      expect(config.leaveConfirmSeconds, 9);
    });

    test('openLogFile creates log file when missing', () async {
      final manager = FileManager(
        documentsDirectoryProvider: () async => tempDir,
        defaultConfigLoader: () async => AppConfig(
          innerBufferM: 1,
          leaveConfirmSamples: 1,
          leaveConfirmSeconds: 1,
          gpsAccuracyBadMeters: 1,
          sampleIntervalS: const {'fast': 1},
          sampleDistanceM: const {'fast': 1},
          screenWakeOnLeave: false,
        ),
      );

      final logFile = await manager.openLogFile();
      expect(await logFile.exists(), isTrue);
      expect(logFile.path, endsWith('argus.log'));
    });
  });
}
