/// ヒステリシス機構を実装するカウンタ。
///
/// 連続サンプル数と経過時間の両方の条件を満たした場合にtrueを返します。
/// 状態遷移の振動を防ぐために使用されます。
class HysteresisCounter {
  HysteresisCounter({
    required this.requiredSamples,
    required this.requiredDuration,
  });

  final int requiredSamples;
  final Duration requiredDuration;

  int _sampleCount = 0;
  DateTime? _firstSampleAt;

  /// 新しいサンプルを追加し、ヒステリシス閾値を満たしている場合はtrueを返します。
  bool addSample(DateTime timestamp) {
    _sampleCount += 1;
    _firstSampleAt ??= timestamp;
    return isSatisfied(timestamp);
  }

  /// サンプル数と経過時間の両方の閾値を満たしている場合にtrueを返します。
  bool isSatisfied(DateTime now) {
    if (_firstSampleAt == null) {
      return false;
    }
    final elapsed = now.difference(_firstSampleAt!);
    return _sampleCount >= requiredSamples && elapsed >= requiredDuration;
  }

  /// カウンタをリセットします。
  void reset() {
    _sampleCount = 0;
    _firstSampleAt = null;
  }
}
