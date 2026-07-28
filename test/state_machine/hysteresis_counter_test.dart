import 'package:flutter_test/flutter_test.dart';

import 'package:argus/state_machine/hysteresis_counter.dart';

void main() {
  group('HysteresisCounter', () {
    test('requires both sample count and monotonic duration', () {
      final counter = HysteresisCounter(
        requiredSamples: 3,
        requiredDuration: const Duration(seconds: 5),
      );

      expect(counter.addSample(Duration.zero), isFalse);
      expect(counter.addSample(const Duration(seconds: 1)), isFalse);
      expect(counter.addSample(const Duration(seconds: 2)), isFalse);
      expect(counter.sampleCount, 3);
      expect(counter.elapsedAt(const Duration(seconds: 2)),
          const Duration(seconds: 2));
      expect(counter.isSatisfied(const Duration(seconds: 5)), isTrue);
    });

    test('duration alone is insufficient', () {
      final counter = HysteresisCounter(
        requiredSamples: 3,
        requiredDuration: const Duration(seconds: 5),
      );

      expect(counter.addSample(Duration.zero), isFalse);
      expect(counter.addSample(const Duration(seconds: 5)), isFalse);
    });

    test('sample count alone is insufficient', () {
      final counter = HysteresisCounter(
        requiredSamples: 3,
        requiredDuration: const Duration(seconds: 5),
      );

      expect(counter.addSample(Duration.zero), isFalse);
      expect(counter.addSample(const Duration(seconds: 1)), isFalse);
      expect(counter.addSample(const Duration(seconds: 2)), isFalse);
    });

    test('reset clears count and elapsed origin', () {
      final counter = HysteresisCounter(
        requiredSamples: 2,
        requiredDuration: const Duration(seconds: 5),
      );

      counter.addSample(Duration.zero);
      counter.addSample(const Duration(seconds: 5));
      counter.reset();

      expect(counter.sampleCount, 0);
      expect(counter.elapsedAt(const Duration(seconds: 10)), Duration.zero);
      expect(counter.addSample(const Duration(seconds: 10)), isFalse);
    });

    test('backwards observations never create negative elapsed time', () {
      final counter = HysteresisCounter(
        requiredSamples: 1,
        requiredDuration: const Duration(seconds: 5),
      );

      counter.addSample(const Duration(seconds: 10));
      expect(counter.elapsedAt(const Duration(seconds: 2)), Duration.zero);
      expect(counter.isSatisfied(const Duration(seconds: 2)), isFalse);
    });
  });
}
