import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS project configuration', () {
    test('declares the required permissions and background modes', () {
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(infoPlist, contains('<key>NSCameraUsageDescription</key>'));
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

    test('registers the iOS native alarm method channel', () {
      final appDelegate =
          File('ios/Runner/AppDelegate.swift').readAsStringSync();

      expect(appDelegate, contains('name: "argus/alarm"'));
      expect(appDelegate, contains('AVAudioPlayer'));
      expect(appDelegate, contains('player.numberOfLoops = -1'));
      expect(appDelegate, contains('AVAudioSession.sharedInstance()'));
      expect(appDelegate, contains('session.setCategory(.playback'));
      expect(appDelegate, contains('AVAudioSession.interruptionNotification'));
      expect(appDelegate, contains('InterruptionOptions'));
      expect(appDelegate, contains('AudioServicesPlaySystemSound'));
      expect(appDelegate, contains('kSystemSoundID_Vibrate'));
      expect(appDelegate, contains('case "startVibration"'));
      expect(appDelegate, contains('case "stopVibration"'));
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
      expect(project, isNot(contains('com.argus.argus')));
      expect(project, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;')));
      expect(frameworkInfo, contains('<string>15.0</string>'));
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
