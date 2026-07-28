import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS project configuration', () {
    test('declares the required permissions and background modes', () {
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(infoPlist, contains('<key>NSCameraUsageDescription</key>'));
      expect(infoPlist, contains('<key>ITSAppUsesNonExemptEncryption</key>'));
      expect(infoPlist,
          contains('<key>NSLocationWhenInUseUsageDescription</key>'));
      expect(
        infoPlist,
        contains('<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>'),
      );
      expect(
          infoPlist, contains('<key>NSPhotoLibraryAddUsageDescription</key>'));
      expect(infoPlist, contains('<string>audio</string>'));
      expect(infoPlist, contains('<string>location</string>'));
      expect(infoPlist, contains('監視開始時に現在地と競技エリアの位置関係を確認'));
      expect(infoPlist, contains('画面ロック中や他のアプリ使用中でも競技エリアからの離脱を検知'));
      expect(infoPlist, contains('<key>UIApplicationSceneManifest</key>'));
      expect(infoPlist,
          contains('<key>UIApplicationSupportsMultipleScenes</key>'));
      expect(infoPlist, contains('<false/>'));
      expect(infoPlist, contains('<string>FlutterSceneDelegate</string>'));
      expect(infoPlist, contains('<string>Main</string>'));
      expect(infoPlist, isNot(contains('<string>armv7</string>')));
    });

    test('enables only the permission_handler features used by ARGUS', () {
      final podfile = File('ios/Podfile').readAsStringSync();

      expect(podfile, contains("platform :ios, '15.0'"));
      expect(podfile, contains("'PERMISSION_CAMERA=1'"));
      expect(podfile, contains("'PERMISSION_LOCATION=1'"));
      expect(podfile, contains("'PERMISSION_NOTIFICATIONS=1'"));
      expect(podfile, isNot(contains("'PERMISSION_CRITICAL_ALERTS=1'")));
    });

    test('bundles a valid CAF alarm and time-sensitive entitlement', () {
      final alarm = File('ios/Runner/Resources/alarm.caf');
      final bytes = alarm.readAsBytesSync();
      final entitlements =
          File('ios/Runner/Runner.entitlements').readAsStringSync();
      final project =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

      expect(ascii.decode(bytes.take(4).toList()), 'caff');
      expect(project, contains('alarm.caf in Resources'));
      expect(project, contains('Runner/Runner.entitlements'));
      expect(
        entitlements,
        contains('com.apple.developer.usernotifications.time-sensitive'),
      );
    });

    test('uses an ARGUS launch image instead of Flutter placeholders', () {
      final launchImages = [
        File('ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png'),
        File(
          'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png',
        ),
        File(
          'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
        ),
      ];
      final launchScreen = File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
          .readAsStringSync();

      for (final image in launchImages) {
        expect(image.lengthSync(), greaterThan(10000));
      }
      expect(launchScreen, contains('contentMode="scaleAspectFit"'));
      expect(launchScreen, contains('constant="168"'));
    });

    test('bundles the app privacy manifest in Runner resources', () {
      final privacyManifest =
          File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
      final project =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

      expect(project, contains('PrivacyInfo.xcprivacy in Resources'));
      expect(privacyManifest, contains('<key>NSPrivacyTracking</key>'));
      expect(privacyManifest, contains('<false/>'));
      expect(
        privacyManifest,
        contains('<key>NSPrivacyCollectedDataTypes</key>'),
      );
      expect(
        privacyManifest,
        contains('NSPrivacyAccessedAPICategoryUserDefaults'),
      );
      expect(privacyManifest, contains('<string>CA92.1</string>'));
    });

    test('registers the iOS native alarm method channel', () {
      final appDelegate =
          File('ios/Runner/AppDelegate.swift').readAsStringSync();

      expect(appDelegate, contains('name: "argus/alarm"'));
      expect(appDelegate, contains('AVAudioPlayer'));
      expect(appDelegate, contains('player.numberOfLoops = -1'));
      expect(appDelegate, contains('AVAudioSession.sharedInstance()'));
      expect(appDelegate, contains('session.setCategory(.playback'));
      expect(appDelegate, contains('AVAudioSession.interruptionNotification'));
      expect(appDelegate, contains('guard isAlarming else'));
      expect(appDelegate, contains('AudioServicesPlaySystemSound'));
      expect(appDelegate, contains('kSystemSoundID_Vibrate'));
      expect(appDelegate, contains('case "startVibration"'));
      expect(appDelegate, contains('case "stopVibration"'));
      expect(appDelegate, contains('case "getAlarmVolumeState"'));
      expect(appDelegate, contains('"supported": false'));
      expect(appDelegate, contains('case "openSoundSettings"'));
      expect(appDelegate, contains('UIApplication.openSettingsURLString'));
      expect(
        RegExp(
          r'case "stop":\s+alarmPlayer\.stop\(\)\s+vibrationPlayer\.stop\(\)',
        ).hasMatch(appDelegate),
        isTrue,
      );
      expect(
        appDelegate,
        isNot(contains('options.contains(.shouldResume)')),
      );
      final notifier = File('lib/platform/notifier.dart').readAsStringSync();
      expect(notifier, contains("sound: 'alarm.caf'"));
      expect(appDelegate, contains('FlutterImplicitEngineDelegate'));
      expect(appDelegate, contains('didInitializeImplicitFlutterEngine'));
      expect(appDelegate,
          contains('engineBridge.applicationRegistrar.messenger()'));
      expect(appDelegate, isNot(contains('rootViewController')));
      expect(
        appDelegate,
        contains('UNUserNotificationCenter.current().delegate = self'),
      );
    });

    test('uses the release bundle identifier and iOS 15 deployment target', () {
      final project =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      final frameworkInfo =
          File('ios/Flutter/AppFrameworkInfo.plist').readAsStringSync();

      expect(
        project,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.argus.orienteering;'),
      );
      expect(project, contains('TARGETED_DEVICE_FAMILY = 1;'));
      expect(project, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2";')));
      expect(project, isNot(contains('com.argus.argus')));
      expect(project, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;')));
      expect(frameworkInfo, contains('<string>15.0</string>'));
    });

    test('uses the 0.6.0 release version and update-check dependencies', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(pubspec, contains('version: 0.6.0+1008'));
      expect(pubspec, contains('package_info_plus: ^10.1.0'));
      expect(pubspec, contains('upgrader: ^13.5.0'));
      expect(pubspec, contains('share_plus: ^13.1.0'));
    });

    test('keeps Podfile.lock trackable and executes native XCTests in CI', () {
      final gitignore = File('.gitignore').readAsStringSync();
      final workflow = File('.github/workflows/ios_ci.yml').readAsStringSync();

      expect(gitignore, contains('!/ios/Podfile.lock'));
      expect(workflow, contains('xcodebuild test \\'));
    });

    test('does not depend on flutter_ringtone_player fallback', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final podfileLock = File('ios/Podfile.lock').readAsStringSync();

      expect(pubspec, isNot(contains('flutter_ringtone_player')));
      expect(podfileLock, isNot(contains('flutter_ringtone_player')));
    });

    test('does not depend on vibration plugin fallback', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final podfileLock = File('ios/Podfile.lock').readAsStringSync();

      expect(pubspec, isNot(contains('vibration:')));
      expect(podfileLock, isNot(contains('vibration')));
    });
  });
}
