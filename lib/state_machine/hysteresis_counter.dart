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
  Duration? _firstSampleAt;

  int get sampleCount => _sampleCount;

  Duration elapsedAt(Duration now) {
    final firstSampleAt = _firstSampleAt;
    if (firstSampleAt == null || now < firstSampleAt) {
      return Duration.zero;
    }
    return now - firstSampleAt;
  }

  /// 新しいサンプルを追加し、ヒステリシス閾値を満たしている場合はtrueを返します。
  bool addSample(Duration observedAt) {
    _sampleCount += 1;
    final firstSampleAt = _firstSampleAt;
    if (firstSampleAt == null || observedAt < firstSampleAt) {
      // 基準時刻より前のサンプルが来た場合は基準を貼り直す。
      // elapsedAt() の 0 クランプに任せると、クロックが巻き戻ったときに
      // 経過時間が永久に閾値を満たさず、実際にエリア外にいるのに
      // OUTER が確定しなくなる（警報が鳴らない）。
      // 貼り直しなら確定が最大 requiredDuration だけ遅れるだけで済む。
      _firstSampleAt = observedAt;
    }
    return isSatisfied(observedAt);
  }

  /// サンプル数と経過時間の両方の閾値を満たしている場合にtrueを返します。
  bool isSatisfied(Duration now) {
    if (_firstSampleAt == null) {
      return false;
    }
    final elapsed = elapsedAt(now);
    return _sampleCount >= requiredSamples && elapsed >= requiredDuration;
  }

  /// カウンタをリセットします。
  void reset() {
    _sampleCount = 0;
    _firstSampleAt = null;
  }
}
