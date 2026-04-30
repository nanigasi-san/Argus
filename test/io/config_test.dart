import 'package:flutter_test/flutter_test.dart';

import 'package:argus/io/config.dart';

import '../support/platform_mocks.dart';

void main() {
  setUpAll(() async {
    await mockDefaultConfigAsset();
  });

  tearDownAll(() async {
    await clearDefaultConfigAssetMock();
  });

  test('fromJson parses values and toJson preserves fields', () {
    final config = AppConfig.fromJson(<String, dynamic>{
      'inner_buffer_m': 12.5,
      'leave_confirm_samples': 4,
      'leave_confirm_seconds': 8,
      'gps_accuracy_bad_m': 33.3,
      'sample_interval_s': <String, dynamic>{'fast': 2, 'slow': 5},
      'alarm_volume': 0.8,
    });

    expect(config.innerBufferM, 12.5);
    expect(config.leaveConfirmSamples, 4);
    expect(config.leaveConfirmSeconds, 8);
    expect(config.gpsAccuracyBadMeters, 33.3);
    expect(config.sampleIntervalS, {'fast': 2, 'slow': 5});
    expect(config.alarmVolume, 0.8);
    expect(config.toJson(), <String, dynamic>{
      'inner_buffer_m': 12.5,
      'leave_confirm_samples': 4,
      'leave_confirm_seconds': 8,
      'gps_accuracy_bad_m': 33.3,
      'sample_interval_s': <String, int>{'fast': 2, 'slow': 5},
      'alarm_volume': 0.8,
    });
  });

  test('fromJson falls back to default volume value', () {
    final config = AppConfig.fromJson(<String, dynamic>{
      'inner_buffer_m': 5,
      'leave_confirm_samples': 1,
      'leave_confirm_seconds': 2,
      'gps_accuracy_bad_m': 10,
      'sample_interval_s': <String, dynamic>{'fast': 3},
    });

    expect(config.alarmVolume, 0.5);
  });

  test('fromJson clamps unsafe values to practical ranges', () {
    final config = AppConfig.fromJson(<String, dynamic>{
      'inner_buffer_m': -5,
      'leave_confirm_samples': 99,
      'leave_confirm_seconds': 0,
      'gps_accuracy_bad_m': 1000,
      'sample_interval_s': <String, dynamic>{'fast': 0},
      'alarm_volume': 9,
    });

    expect(config.innerBufferM, AppConfig.minInnerBufferM);
    expect(config.leaveConfirmSamples, AppConfig.maxLeaveConfirmSamples);
    expect(config.leaveConfirmSeconds, AppConfig.minLeaveConfirmSeconds);
    expect(config.gpsAccuracyBadMeters, AppConfig.maxGpsAccuracyBadMeters);
    expect(config.sampleIntervalS['fast'], AppConfig.minSampleIntervalS);
    expect(config.alarmVolume, AppConfig.maxAlarmVolume);
  });

  test('loadDefault reads bundled config asset', () async {
    final config = await AppConfig.loadDefault();

    expect(config.innerBufferM, greaterThan(0));
    expect(config.leaveConfirmSamples, greaterThan(0));
    expect(config.leaveConfirmSeconds, greaterThan(0));
    expect(config.sampleIntervalS, isNotEmpty);
  });
}
