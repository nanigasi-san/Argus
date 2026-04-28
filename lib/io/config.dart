import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class AppConfig {
  AppConfig({
    required this.innerBufferM,
    required this.leaveConfirmSamples,
    required this.leaveConfirmSeconds,
    required this.gpsAccuracyBadMeters,
    required this.sampleIntervalS,
    required this.alarmVolume,
  });

  static const defaultInnerBufferM = 30.0;
  static const minInnerBufferM = 1.0;
  static const maxInnerBufferM = 300.0;

  static const defaultLeaveConfirmSamples = 3;
  static const minLeaveConfirmSamples = 1;
  static const maxLeaveConfirmSamples = 10;

  static const defaultLeaveConfirmSeconds = 10;
  static const minLeaveConfirmSeconds = 1;
  static const maxLeaveConfirmSeconds = 60;

  static const defaultGpsAccuracyBadMeters = 40.0;
  static const minGpsAccuracyBadMeters = 5.0;
  static const maxGpsAccuracyBadMeters = 200.0;

  static const defaultFastSampleIntervalS = 3;
  static const minSampleIntervalS = 1;
  static const maxSampleIntervalS = 60;

  static const defaultAlarmVolume = 0.5;
  static const minAlarmVolume = 0.0;
  static const maxAlarmVolume = 1.0;

  final double innerBufferM;
  final int leaveConfirmSamples;
  final int leaveConfirmSeconds;
  final double gpsAccuracyBadMeters;
  final Map<String, int> sampleIntervalS;
  final double alarmVolume;

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      innerBufferM: _readDouble(
        json,
        'inner_buffer_m',
        defaultInnerBufferM,
      ),
      leaveConfirmSamples: _readInt(
        json,
        'leave_confirm_samples',
        defaultLeaveConfirmSamples,
      ),
      leaveConfirmSeconds: _readInt(
        json,
        'leave_confirm_seconds',
        defaultLeaveConfirmSeconds,
      ),
      gpsAccuracyBadMeters: _readDouble(
        json,
        'gps_accuracy_bad_m',
        defaultGpsAccuracyBadMeters,
      ),
      sampleIntervalS: _readIntMap(
        json['sample_interval_s'],
        fallback: const <String, int>{'fast': defaultFastSampleIntervalS},
      ),
      alarmVolume: _readDouble(json, 'alarm_volume', defaultAlarmVolume),
    ).normalized();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'inner_buffer_m': innerBufferM,
        'leave_confirm_samples': leaveConfirmSamples,
        'leave_confirm_seconds': leaveConfirmSeconds,
        'gps_accuracy_bad_m': gpsAccuracyBadMeters,
        'sample_interval_s': sampleIntervalS,
        'alarm_volume': alarmVolume,
      };

  AppConfig normalized() {
    return AppConfig(
      innerBufferM: _clampDouble(
        innerBufferM,
        minInnerBufferM,
        maxInnerBufferM,
      ),
      leaveConfirmSamples: _clampInt(
        leaveConfirmSamples,
        minLeaveConfirmSamples,
        maxLeaveConfirmSamples,
      ),
      leaveConfirmSeconds: _clampInt(
        leaveConfirmSeconds,
        minLeaveConfirmSeconds,
        maxLeaveConfirmSeconds,
      ),
      gpsAccuracyBadMeters: _clampDouble(
        gpsAccuracyBadMeters,
        minGpsAccuracyBadMeters,
        maxGpsAccuracyBadMeters,
      ),
      sampleIntervalS: _normalizeIntMap(
        sampleIntervalS,
        defaultFastSampleIntervalS,
        minSampleIntervalS,
        maxSampleIntervalS,
      ),
      alarmVolume: _clampDouble(
        alarmVolume,
        minAlarmVolume,
        maxAlarmVolume,
      ),
    );
  }

  int get effectiveFastSampleIntervalS =>
      normalized().sampleIntervalS['fast'] ?? defaultFastSampleIntervalS;

  static Future<AppConfig> loadDefault() async {
    final text =
        await rootBundle.loadString('assets/config/default_config.json');
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    return AppConfig.fromJson(decoded);
  }

  static double _readDouble(
    Map<String, dynamic> json,
    String key,
    double fallback,
  ) {
    final value = json[key];
    return value is num ? value.toDouble() : fallback;
  }

  static int _readInt(
    Map<String, dynamic> json,
    String key,
    int fallback,
  ) {
    final value = json[key];
    return value is num ? value.toInt() : fallback;
  }

  static Map<String, int> _readIntMap(
    Object? value, {
    required Map<String, int> fallback,
  }) {
    if (value is! Map) {
      return fallback;
    }

    final mapped = <String, int>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final rawValue = entry.value;
      if (key is String && rawValue is num) {
        mapped[key] = rawValue.toInt();
      }
    }
    return mapped.isEmpty ? fallback : mapped;
  }

  static Map<String, int> _normalizeIntMap(
    Map<String, int> source,
    int defaultFastValue,
    int min,
    int max,
  ) {
    final normalized = source.map(
      (key, value) => MapEntry(key, _clampInt(value, min, max)),
    );
    normalized['fast'] =
        _clampInt(normalized['fast'] ?? defaultFastValue, min, max);
    return normalized;
  }

  static double _clampDouble(double value, double min, double max) {
    if (value.isNaN || value.isInfinite) {
      return min;
    }
    return value.clamp(min, max);
  }

  static int _clampInt(int value, int min, int max) {
    return value.clamp(min, max);
  }
}
