enum AppLogLevel { debug, info, warning, error }

class AppLogEntry {
  AppLogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.level = AppLogLevel.info,
  });

  final DateTime timestamp;
  final String tag;
  final String message;
  final AppLogLevel level;

  factory AppLogEntry.debug({
    required String tag,
    required String message,
    DateTime? timestamp,
  }) =>
      AppLogEntry(
        tag: tag,
        message: message,
        level: AppLogLevel.debug,
        timestamp: timestamp ?? DateTime.now(),
      );

  factory AppLogEntry.info({
    required String tag,
    required String message,
    DateTime? timestamp,
  }) =>
      AppLogEntry(
        tag: tag,
        message: message,
        level: AppLogLevel.info,
        timestamp: timestamp ?? DateTime.now(),
      );

  factory AppLogEntry.warning({
    required String tag,
    required String message,
    DateTime? timestamp,
  }) =>
      AppLogEntry(
        tag: tag,
        message: message,
        level: AppLogLevel.warning,
        timestamp: timestamp ?? DateTime.now(),
      );

  factory AppLogEntry.error({
    required String tag,
    required String message,
    DateTime? timestamp,
  }) =>
      AppLogEntry(
        tag: tag,
        message: message,
        level: AppLogLevel.error,
        timestamp: timestamp ?? DateTime.now(),
      );
}
