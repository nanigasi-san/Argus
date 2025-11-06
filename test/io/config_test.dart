import 'package:flutter_test/flutter_test.dart';

import 'package:argus/io/config.dart';

void main() {
  group('AppConfig', () {
    test('fromJson parses numeric values and maps', () {
      final config = AppConfig.fromJson({
        'inner_buffer_m': 12,
        'leave_confirm_samples': 4,
        'leave_confirm_seconds': 8,
        'gps_accuracy_bad_m': 30.5,
        'sample_interval_s': {'fast': 3, 'slow': 10.9},
        'sample_distance_m': {'fast': 5.2},
        'screen_wake_on_leave': true,
      });

      expect(config.innerBufferM, 12.0);
      expect(config.leaveConfirmSamples, 4);
      expect(config.leaveConfirmSeconds, 8);
      expect(config.gpsAccuracyBadMeters, 30.5);
      expect(config.sampleIntervalS['slow'], 10);
      expect(config.sampleDistanceM['fast'], 5);
      expect(config.screenWakeOnLeave, isTrue);
    });

    test('toJson round-trips configuration data', () {
      final config = AppConfig(
        innerBufferM: 20,
        leaveConfirmSamples: 2,
        leaveConfirmSeconds: 6,
        gpsAccuracyBadMeters: 15.5,
        sampleIntervalS: const {'fast': 2, 'slow': 12},
        sampleDistanceM: const {'fast': 3, 'slow': 30},
        screenWakeOnLeave: false,
      );

      final json = config.toJson();

      expect(json['inner_buffer_m'], 20);
      expect(json['leave_confirm_samples'], 2);
      expect(json['leave_confirm_seconds'], 6);
      expect(json['gps_accuracy_bad_m'], 15.5);
      expect(json['sample_interval_s'], {'fast': 2, 'slow': 12});
      expect(json['sample_distance_m'], {'fast': 3, 'slow': 30});
      expect(json['screen_wake_on_leave'], isFalse);
    });
  });
}
