import 'package:flutter/services.dart';

import '../garmin/garmin_course_payload.dart';

class GarminDevice {
  const GarminDevice(
      {required this.id, required this.name, required this.connected});
  final String id;
  final String name;
  final bool connected;

  factory GarminDevice.fromMap(Map<Object?, Object?> map) => GarminDevice(
        id: map['id'] as String,
        name: map['name'] as String,
        connected: map['connected'] as bool? ?? false,
      );
}

class GarminTransferResult {
  const GarminTransferResult(
      {required this.deviceName, required this.elapsedMs});
  final String deviceName;
  final int elapsedMs;
}

class GarminTransferClient {
  const GarminTransferClient({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('argus/garmin');
  final MethodChannel _channel;

  void setDeviceChangeHandler(void Function()? handler) {
    _channel.setMethodCallHandler(handler == null
        ? null
        : (call) async {
            if (call.method == 'devicesChanged') handler();
          });
  }

  Future<List<GarminDevice>> getDevices() async {
    final raw =
        await _channel.invokeListMethod<Object?>('getDevices') ?? const [];
    return raw
        .map((item) => GarminDevice.fromMap(item as Map<Object?, Object?>))
        .toList(growable: false);
  }

  /// On iOS this opens Garmin Connect so the user can authorize paired watches.
  Future<void> selectDevices() => _channel.invokeMethod<void>('selectDevices');

  Future<GarminTransferResult> sendCourse(
      GarminDevice device, GarminCoursePayload payload) async {
    final args = <String, Object>{'deviceId': device.id, ...payload.toMap()};
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>('sendCourse', args);
    if (raw == null) {
      throw PlatformException(code: 'empty_result');
    }
    return GarminTransferResult(
      deviceName: raw['deviceName'] as String? ?? device.name,
      elapsedMs: (raw['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }
}
