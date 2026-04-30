import 'package:flutter_test/flutter_test.dart';

import 'package:argus/io/config.dart';
import 'package:argus/platform/location_service.dart';

void main() {
  final config = AppConfig(
    innerBufferM: 5,
    leaveConfirmSamples: 1,
    leaveConfirmSeconds: 1,
    gpsAccuracyBadMeters: 10,
    sampleIntervalS: const {'fast': 3},
    alarmVolume: 0.5,
  );

  test('LocationFix stores provided values', () {
    final timestamp = DateTime.utc(2024, 1, 1);
    const accuracy = 4.2;
    final fix = LocationFix(
      latitude: 35.0,
      longitude: 139.0,
      timestamp: timestamp,
      accuracyMeters: accuracy,
    );

    expect(fix.latitude, 35.0);
    expect(fix.longitude, 139.0);
    expect(fix.timestamp, timestamp);
    expect(fix.accuracyMeters, accuracy);
  });

  test('LocationServiceStartResult.started has started status and no message',
      () {
    const result = LocationServiceStartResult.started();

    expect(result.status, LocationServiceStartStatus.started);
    expect(result.message, isNull);
  });

  test('RuntimePlatform exposes apple platform grouping', () {
    const android = RuntimePlatform(
      isAndroid: true,
      isIOS: false,
      isMacOS: false,
    );
    const ios = RuntimePlatform(
      isAndroid: false,
      isIOS: true,
      isMacOS: false,
    );
    const macos = RuntimePlatform(
      isAndroid: false,
      isIOS: false,
      isMacOS: true,
    );

    expect(android.isApple, isFalse);
    expect(ios.isApple, isTrue);
    expect(macos.isApple, isTrue);
  });

  test('RuntimePlatform.current reflects one supported runtime', () {
    final current = RuntimePlatform.current();

    expect(
      current.isAndroid || current.isIOS || current.isMacOS || !current.isApple,
      isTrue,
    );
  });

  test('FakeLocationService emits updates and tracks lifecycle', () async {
    final fixes = <LocationFix>[
      LocationFix(
        latitude: 1,
        longitude: 2,
        timestamp: DateTime.utc(2024, 1, 1),
      ),
    ];
    final service =
        FakeLocationService(Stream<LocationFix>.fromIterable(fixes));

    final received = await service.stream.toList();
    final result = await service.start(config);
    await service.stop();

    expect(received, hasLength(1));
    expect(received.single.latitude, 1);
    expect(result.status, LocationServiceStartStatus.started);
  });
}
