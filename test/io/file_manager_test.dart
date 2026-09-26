import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:argus/io/config.dart';
import 'package:argus/io/file_manager.dart';

void main() {
  late Directory tempDir;
  late AppConfig defaultConfig;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('argus_file_manager_test_');
    defaultConfig = AppConfig(
      innerBufferM: 5,
      leaveConfirmSamples: 2,
      leaveConfirmSeconds: 4,
      gpsAccuracyBadMeters: 30,
      sampleIntervalS: const {'fast': 3},
      alarmVolume: 0.4,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('pickGeoJsonFile opens picker without file filter', () async {
    List<XTypeGroup>? capturedGroups;
    final manager = FileManager(
      filePicker: ({acceptedTypeGroups}) async {
        capturedGroups = acceptedTypeGroups;
        return null;
      },
      documentsDirectoryProvider: () async => tempDir,
      defaultConfigLoader: () async => defaultConfig,
    );

    await manager.pickGeoJsonFile();

    expect(capturedGroups, isNull);
  });

  test('pickQrImageFile opens picker with image filter', () async {
    List<XTypeGroup>? capturedGroups;
    final manager = FileManager(
      filePicker: ({acceptedTypeGroups}) async {
        capturedGroups = acceptedTypeGroups;
        return null;
      },
      documentsDirectoryProvider: () async => tempDir,
      defaultConfigLoader: () async => defaultConfig,
    );

    await manager.pickQrImageFile();

    expect(capturedGroups, isNotNull);
    expect(capturedGroups, hasLength(1));
    expect(capturedGroups!.single.label, 'QR code image');
    expect(capturedGroups!.single.extensions,
        containsAll(<String>['png', 'jpg', 'jpeg', 'webp']));
    expect(capturedGroups!.single.mimeTypes,
        containsAll(<String>['image/png', 'image/jpeg', 'image/webp']));
    expect(
      capturedGroups!.single.uniformTypeIdentifiers,
      contains('public.image'),
    );
  });

  test('getConfigFile creates config file with default config when missing',
      () async {
    final manager = FileManager(
      documentsDirectoryProvider: () async => tempDir,
      defaultConfigLoader: () async => defaultConfig,
    );

    final file = await manager.getConfigFile();

    expect(await file.exists(), isTrue);
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['inner_buffer_m'], 5);
    expect(decoded['alarm_volume'], 0.4);
  });

  test('saveConfig persists JSON to config file', () async {
    final manager = FileManager(
      documentsDirectoryProvider: () async => tempDir,
      defaultConfigLoader: () async => defaultConfig,
    );
    final updated = AppConfig(
      innerBufferM: 12,
      leaveConfirmSamples: 3,
      leaveConfirmSeconds: 6,
      gpsAccuracyBadMeters: 22,
      sampleIntervalS: const {'fast': 1},
      alarmVolume: 0.9,
    );

    await manager.saveConfig(updated);

    final file = File('${tempDir.path}/config.json');
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['inner_buffer_m'], 12.0);
    expect(decoded['alarm_volume'], 0.9);
  });

  test('readConfig returns parsed config when file is valid', () async {
    final file = File('${tempDir.path}/config.json');
    await file.writeAsString(jsonEncode(defaultConfig.toJson()));
    final manager = FileManager(
      documentsDirectoryProvider: () async => tempDir,
      defaultConfigLoader: () async => AppConfig(
        innerBufferM: 1,
        leaveConfirmSamples: 1,
        leaveConfirmSeconds: 1,
        gpsAccuracyBadMeters: 1,
        sampleIntervalS: const {'fast': 1},
        alarmVolume: 0.1,
      ),
    );

    final config = await manager.readConfig();

    expect(config.innerBufferM, defaultConfig.innerBufferM);
    expect(config.leaveConfirmSamples, defaultConfig.leaveConfirmSamples);
  });

  test('readConfig migrates only the saved boundary buffer to zero once',
      () async {
    final file = File('${tempDir.path}/config.json');
    final legacy = defaultConfig.toJson()..remove('config_version');
    legacy['inner_buffer_m'] = 30.0;
    await file.writeAsString(jsonEncode(legacy));
    final manager = FileManager(
      documentsDirectoryProvider: () async => tempDir,
      defaultConfigLoader: () async => defaultConfig,
    );

    final migrated = await manager.readConfig();
    expect(migrated.innerBufferM, 0);
    expect(migrated.leaveConfirmSamples, defaultConfig.leaveConfirmSamples);
    expect(migrated.gpsAccuracyBadMeters, defaultConfig.gpsAccuracyBadMeters);
    expect(migrated.alarmVolume, defaultConfig.alarmVolume);
    final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(saved['config_version'], AppConfig.currentConfigVersion);
    expect(saved['inner_buffer_m'], 0);
    expect(saved['alarm_volume'], defaultConfig.alarmVolume);

    await manager.saveConfig(AppConfig(
      innerBufferM: 12,
      leaveConfirmSamples: migrated.leaveConfirmSamples,
      leaveConfirmSeconds: migrated.leaveConfirmSeconds,
      gpsAccuracyBadMeters: migrated.gpsAccuracyBadMeters,
      sampleIntervalS: migrated.sampleIntervalS,
      alarmVolume: migrated.alarmVolume,
    ));
    expect((await manager.readConfig()).innerBufferM, 12);
  });

  test('readConfig falls back to default config on invalid JSON', () async {
    final file = File('${tempDir.path}/config.json');
    await file.writeAsString('{invalid');
    final manager = FileManager(
      documentsDirectoryProvider: () async => tempDir,
      defaultConfigLoader: () async => defaultConfig,
    );

    final config = await manager.readConfig();

    expect(config.innerBufferM, defaultConfig.innerBufferM);
    expect(config.alarmVolume, defaultConfig.alarmVolume);
  });

  test('openLogFile creates log file when missing', () async {
    final manager = FileManager(
      documentsDirectoryProvider: () async => tempDir,
      defaultConfigLoader: () async => defaultConfig,
    );

    final file = await manager.openLogFile();

    expect(file.path, '${tempDir.path}/argus.log');
    expect(await file.exists(), isTrue);
  });
}
