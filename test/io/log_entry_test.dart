import 'package:flutter_test/flutter_test.dart';

import 'package:argus/io/log_entry.dart';

void main() {
  group('AppLogEntry', () {
    test('debug factory sets level and preserves timestamp', () {
      final timestamp = DateTime.utc(2024, 1, 2, 3, 4, 5);

      final entry = AppLogEntry.debug(
        tag: 'TEST',
        message: 'hello',
        timestamp: timestamp,
      );

      expect(entry.level, AppLogLevel.debug);
      expect(entry.timestamp, timestamp);
      expect(entry.tag, 'TEST');
      expect(entry.message, 'hello');
    });

    test('info factory assigns current timestamp when omitted', () {
      final entry = AppLogEntry.info(tag: 'TEST', message: 'world');

      expect(entry.level, AppLogLevel.info);
      expect(entry.timestamp.isBefore(DateTime.now().add(const Duration(seconds: 1))), isTrue);
      expect(entry.message, 'world');
    });
  });
}
