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

    test('uses native vibration playback without plugin dependency', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/argus/orienteering/MainActivity.kt',
      ).readAsStringSync();
      final notifier = File('lib/platform/notifier.dart').readAsStringSync();

      expect(manifest, contains('android.permission.VIBRATE'));
      expect(mainActivity, contains('"stopAlarm"'));
      expect(mainActivity, contains('"startVibration"'));
      expect(mainActivity, contains('"pulseVibration"'));
      expect(mainActivity, contains('"stopVibration"'));
      expect(mainActivity, contains('"getAlertPlaybackState"'));
      expect(mainActivity, contains('"vibrationPatternActive"'));
      expect(mainActivity, contains('NativeVibrationPlayer'));
      expect(mainActivity, contains('VibrationEffect.createWaveform'));
      expect(mainActivity, contains('VibrationEffect.createOneShot'));
      expect(
        RegExp(
          r'fun stop\(context: Context\? = null\)[\s\S]*?^    }',
          multiLine: true,
        ).firstMatch(mainActivity)?.group(0),
        isNot(contains('NativeVibrationPlayer.stop')),
      );
      expect(notifier, contains('NativeVibrationPlayer'));
      expect(notifier, isNot(contains("package:vibration")));
    });

    test('exposes alarm volume checks and the Android sound settings route',
        () {
      final mainActivity = File(
        'android/app/src/main/kotlin/com/argus/orienteering/MainActivity.kt',
      ).readAsStringSync();

      expect(mainActivity, contains('"getAlarmVolumeState"'));
      expect(mainActivity, contains('AudioManager.STREAM_ALARM'));
      expect(mainActivity, contains('"openSoundSettings"'));
      expect(mainActivity, contains('Settings.ACTION_SOUND_SETTINGS'));
      expect(mainActivity, contains('Settings.ACTION_SETTINGS'));
    });

    test('keeps Android alert notifications visual-only', () {
      final notifier = File('lib/platform/notifier.dart').readAsStringSync();

      expect(notifier, contains("_channelId = 'argus_alerts_visual_v2'"));
      expect(notifier, contains('playSound: false'));
      expect(notifier, contains('enableVibration: false'));
      expect(notifier, isNot(contains('audioAttributesUsage:')));
      expect(notifier, isNot(contains("fromAsset: 'assets/sounds/alarm.mp3'")));
    });

    test('does not depend on flutter_ringtone_player fallback', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final lockfile = File('pubspec.lock').readAsStringSync();

      expect(pubspec, isNot(contains('flutter_ringtone_player')));
      expect(lockfile, isNot(contains('flutter_ringtone_player')));
    });

    test('uses current Android build tooling compatibility versions', () {
      final settings = File('android/settings.gradle.kts').readAsStringSync();
      final wrapper = File('android/gradle/wrapper/gradle-wrapper.properties')
          .readAsStringSync();
      final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
      final gradleProperties =
          File('android/gradle.properties').readAsStringSync();

      expect(settings, contains('com.android.application") version "8.11.1"'));
      expect(
        settings,
        contains('org.jetbrains.kotlin.android") version "2.2.20"'),
      );
      expect(wrapper, contains('gradle-8.14-all.zip'));
      expect(appBuild, isNot(contains('id("kotlin-android")')));
      expect(appBuild, isNot(contains('kotlinOptions')));
      expect(appBuild, contains('JvmTarget.JVM_17'));
      expect(gradleProperties, contains('android.builtInKotlin=true'));
      expect(gradleProperties, contains('android.newDsl=false'));
    });

    test('does not depend on vibration plugin fallback', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final lockfile = File('pubspec.lock').readAsStringSync();

      expect(pubspec, isNot(contains('vibration:')));
      expect(lockfile, isNot(contains('vibration_platform_interface')));
      expect(lockfile, isNot(contains('name: vibration')));
    });

    test('runs device integration through native alert and location channels',
        () {
      final workflow =
          File('.github/workflows/android_emulator_ci.yml').readAsStringSync();
      final integration = File(
        'integration_test/monitoring_review_geojson_test.dart',
      ).readAsStringSync();

      expect(workflow, contains('adb emu geo fix'));
      expect(workflow, contains('ACCESS_BACKGROUND_LOCATION'));
      expect(workflow, contains('--use-application-binary='));
      expect(integration, contains('GeolocatorLocationService()'));
      expect(integration, contains('MethodChannelAlertDiagnosticsClient'));
    });
  });
}
