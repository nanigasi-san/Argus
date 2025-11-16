import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class AppConfig {
  AppConfig({
    required this.innerBufferM,
    required this.leaveConfirmSamples,
    required this.leaveConfirmSeconds,
    required this.gpsAccuracyBadMeters,
    required this.sampleIntervalS,
    required this.sampleDistanceM,
    required this.screenWakeOnLeave,
    required this.alarmVolume,
  });

  final double innerBufferM;
  final int leaveConfirmSamples;
  final int leaveConfirmSeconds;
  final double gpsAccuracyBadMeters;
  final Map<String, int> sampleIntervalS;
  final Map<String, int> sampleDistanceM;
  final bool screenWakeOnLeave;
  final double alarmVolume;

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      innerBufferM: (json['inner_buffer_m'] as num).toDouble(),
      leaveConfirmSamples: (json['leave_confirm_samples'] as num).toInt(),
      leaveConfirmSeconds: (json['leave_confirm_seconds'] as num).toInt(),
      gpsAccuracyBadMeters: (json['gps_accuracy_bad_m'] as num).toDouble(),
      sampleIntervalS: (json['sample_interval_s'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          (value as num).toInt(),
        ),
      ),
      sampleDistanceM: (json['sample_distance_m'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          (value as num).toInt(),
        ),
      ),
      screenWakeOnLeave: json['screen_wake_on_leave'] as bool? ?? false,
      alarmVolume: (json['alarm_volume'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'inner_buffer_m': innerBufferM,
        'leave_confirm_samples': leaveConfirmSamples,
        'leave_confirm_seconds': leaveConfirmSeconds,
        'gps_accuracy_bad_m': gpsAccuracyBadMeters,
        'sample_interval_s': sampleIntervalS,
        'sample_distance_m': sampleDistanceM,
        'screen_wake_on_leave': screenWakeOnLeave,
        'alarm_volume': alarmVolume,
      };

  static Future<AppConfig> loadDefault() async {
    final text =
        await rootBundle.loadString('assets/config/default_config.json');
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    return AppConfig.fromJson(decoded);
  }
}
