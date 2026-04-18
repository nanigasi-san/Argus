import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _assetsChannel = MethodChannel('flutter/assets');
const MethodChannel _urlLauncherChannel =
    MethodChannel('plugins.flutter.io/url_launcher');

Future<void> mockDefaultConfigAsset() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = await File('assets/config/default_config.json').readAsBytes();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final key = const StringCodec().decodeMessage(message);
    if (key == 'assets/config/default_config.json') {
      return ByteData.sublistView(Uint8List.fromList(bytes));
    }
    return null;
  });
}

Future<void> clearDefaultConfigAssetMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', null);
  return Future<void>.value();
}

Future<List<MethodCall>> mockUrlLauncher({required bool launchResult}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    _urlLauncherChannel,
    (MethodCall methodCall) async {
      calls.add(methodCall);
      return launchResult;
    },
  );
  return calls;
}

Future<void> clearUrlLauncherMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_urlLauncherChannel, null);
  return Future<void>.value();
}
