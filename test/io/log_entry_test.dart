import 'package:flutter_test/flutter_test.dart';

import 'package:argus/io/log_entry.dart';

void main() {
  test('debug factory sets debug level and provided timestamp', () {
    final timestamp = DateTime.utc(2024, 1, 1, 12, 0);
    final entry = AppLogEntry.debug(
      tag: 'GPS',
      message: 'debug',
      timestamp: timestamp,
    );

    expect(entry.level, AppLogLevel.debug);
    expect(entry.tag, 'GPS');
    expect(entry.message, 'debug');
    expect(entry.timestamp, timestamp);
  });

  test('info factory defaults timestamp when omitted', () {
    final before = DateTime.now();
    final entry = AppLogEntry.info(tag: 'APP', message: 'info');
    final after = DateTime.now();

    expect(entry.level, AppLogLevel.info);
    expect(
      entry.timestamp.isAfter(before.subtract(const Duration(seconds: 1))),
      isTrue,
    );
    expect(
      entry.timestamp.isBefore(after.add(const Duration(seconds: 1))),
      isTrue,
    );
  });

  test('warning and error factories set matching levels', () {
    final warning = AppLogEntry.warning(tag: 'APP', message: 'warn');
    final error = AppLogEntry.error(tag: 'APP', message: 'error');

    expect(warning.level, AppLogLevel.warning);
    expect(error.level, AppLogLevel.error);
  });
}
