class HysteresisCounter {
  HysteresisCounter({
    required this.requiredSamples,
    required this.requiredDuration,
  });

  final int requiredSamples;
  final Duration requiredDuration;

  int _sampleCount = 0;
  DateTime? _firstSampleAt;

  /// Adds a new sample and returns true if the hysteresis threshold is met.
  bool addSample(DateTime timestamp) {
    _sampleCount += 1;
    _firstSampleAt ??= timestamp;
    return isSatisfied(timestamp);
  }

  /// Returns true when both sample count and elapsed duration thresholds meet.
  bool isSatisfied(DateTime now) {
    if (_firstSampleAt == null) {
      return false;
    }
    final elapsed = now.difference(_firstSampleAt!);
    return _sampleCount >= requiredSamples &&
        elapsed >= requiredDuration;
  }

  void reset() {
    _sampleCount = 0;
    _firstSampleAt = null;
  }
}
