import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android project configuration', () {
    test('bundles the offline alarm sound resource', () {
      final alarm = File('android/app/src/main/res/raw/alarm.mp3');

      expect(alarm.existsSync(), isTrue);
      expect(alarm.lengthSync(), greaterThan(0));
    });

    test('uses native alarm playback with audio focus', () {
      final mainActivity = File(
        'android/app/src/main/kotlin/com/argus/orienteering/MainActivity.kt',
      ).readAsStringSync();

      expect(mainActivity, contains('MethodChannel'));
      expect(mainActivity, contains('ALARM_CHANNEL = "argus/alarm"'));
      expect(mainActivity, contains('MediaPlayer'));
      expect(mainActivity, contains('AudioFocusRequest'));
      expect(mainActivity, contains('requestAudioFocus'));
      expect(mainActivity, contains('abandonAudioFocusRequest'));
      expect(mainActivity, contains('AudioAttributes.USAGE_ALARM'));
      expect(mainActivity, contains('CONTENT_TYPE_SONIFICATION'));
      expect(mainActivity, contains('result.error'));
    });

    test('keeps Android alert notifications visual-only', () {
      final notifier = File('lib/platform/notifier.dart').readAsStringSync();

      expect(notifier, contains("_channelId = 'argus_alerts_visual'"));
      expect(notifier, contains('playSound: false'));
      expect(notifier, isNot(contains('audioAttributesUsage:')));
      expect(notifier, isNot(contains("fromAsset: 'assets/sounds/alarm.mp3'")));
    });

    test('does not depend on flutter_ringtone_player fallback', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final lockfile = File('pubspec.lock').readAsStringSync();

      expect(pubspec, isNot(contains('flutter_ringtone_player')));
      expect(lockfile, isNot(contains('flutter_ringtone_player')));
    });
  });
}
