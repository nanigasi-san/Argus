import 'package:argus/platform/garmin_transfer_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reset monitoring sends a disable command to the selected watch',
      () async {
    const channel = MethodChannel('argus/garmin');
    MethodCall? sent;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return <String, Object>{'deviceName': 'ForeAthlete 55', 'elapsedMs': 42};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final result = await const GarminTransferClient(channel: channel)
        .resetMonitoring(const GarminDevice(
            id: 'watch-1', name: 'ForeAthlete 55', connected: true));

    expect(sent?.method, 'resetMonitoring');
    expect(sent?.arguments, <String, Object>{
      'deviceId': 'watch-1',
      'type': 'argus-control',
      'v': 1,
      'action': 'disable',
    });
    expect(result.deviceName, 'ForeAthlete 55');
    expect(result.elapsedMs, 42);
  });
}
