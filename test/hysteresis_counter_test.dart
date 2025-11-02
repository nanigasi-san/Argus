import 'package:flutter_test/flutter_test.dart';

import 'package:argus/state_machine/hysteresis_counter.dart';

void main() {
  group('HysteresisCounter', () {
    test('starts with no samples', () {
      final counter = HysteresisCounter(
        requiredSamples: 3,
        requiredDuration: Duration(seconds: 10),
      );

      final baseTime = DateTime.now();
      expect(counter.isSatisfied(baseTime), false);
    });

    test('requires both sample count and duration', () {
      final counter = HysteresisCounter(
        requiredSamples: 3,
        requiredDuration: Duration(seconds: 10),
      );

      final baseTime = DateTime.now();

      // Add samples but not enough time
      expect(counter.addSample(baseTime), false);
      expect(counter.addSample(baseTime.add(Duration(seconds: 1))), false);
      expect(counter.addSample(baseTime.add(Duration(seconds: 2))), false);

      // Still not enough time (only 2 seconds elapsed)
      expect(counter.isSatisfied(baseTime.add(Duration(seconds: 2))), false);

      // Enough time but check via addSample with new timestamp
      expect(counter.addSample(baseTime.add(Duration(seconds: 11))), true);
    });

    test('requires both sample count and duration - time first', () {
      final counter = HysteresisCounter(
        requiredSamples: 3,
        requiredDuration: Duration(seconds: 10),
      );

      final baseTime = DateTime.now();

      // Add one sample and wait long time
      expect(counter.addSample(baseTime), false);
      expect(counter.isSatisfied(baseTime.add(Duration(seconds: 15))), false);

      // Add more samples
      expect(counter.addSample(baseTime.add(Duration(seconds: 16))), false);
      expect(counter.addSample(baseTime.add(Duration(seconds: 17))), true);
    });

    test('resets counter', () {
      final counter = HysteresisCounter(
        requiredSamples: 3,
        requiredDuration: Duration(seconds: 10),
      );

      final baseTime = DateTime.now();
      counter.addSample(baseTime);
      counter.addSample(baseTime.add(Duration(seconds: 1)));

      counter.reset();

      expect(counter.isSatisfied(baseTime.add(Duration(seconds: 15))), false);
      expect(counter.addSample(baseTime.add(Duration(seconds: 16))), false);
    });

    test('handles zero samples requirement', () {
      final counter = HysteresisCounter(
        requiredSamples: 0,
        requiredDuration: Duration(seconds: 10),
      );

      final baseTime = DateTime.now();
      expect(counter.isSatisfied(baseTime), false); // No sample added yet

      counter.addSample(baseTime);
      expect(counter.isSatisfied(baseTime.add(Duration(seconds: 5))), false);
      expect(counter.isSatisfied(baseTime.add(Duration(seconds: 10))), true);
    });

    test('handles zero duration requirement', () {
      final counter = HysteresisCounter(
        requiredSamples: 3,
        requiredDuration: Duration.zero,
      );

      final baseTime = DateTime.now();
      expect(counter.addSample(baseTime), false);
      expect(counter.addSample(baseTime), false);
      expect(counter.addSample(baseTime), true);
    });

    test('first sample timestamp is preserved', () {
      final counter = HysteresisCounter(
        requiredSamples: 3,
        requiredDuration: Duration(seconds: 10),
      );

      final baseTime = DateTime(2024, 1, 1, 12, 0, 0);
      counter.addSample(baseTime);

      // Add samples with much later timestamps, but check elapsed time from first
      counter.addSample(DateTime(2024, 1, 1, 12, 0, 5));
      counter.addSample(DateTime(2024, 1, 1, 12, 0, 10));

      // 10 seconds from baseTime should satisfy
      expect(counter.isSatisfied(DateTime(2024, 1, 1, 12, 0, 10)), true);
    });
  });
}

