import 'package:flutter_test/flutter_test.dart';
import 'package:argus/platform/notifier.dart';
import '../support/notifier_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notifier', () {
    test('outer -> inner -> outer toggles alarm playback', () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final vibration = FakeVibrationPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
        vibrationPlayer: vibration,
      );

      await notifier.notifyOuter();
      expect(notifications.shownIds.single, 1001);
      expect(alarm.playCount, 1);
      expect(alarm.stopCount, 0);
      expect(vibration.startCount, 1);
      expect(vibration.stopCount, 0);

      await notifier.notifyRecover();
      expect(notifications.cancelledIds.single, 1001);
      expect(alarm.stopCount, 1);
      expect(vibration.stopCount, 1);

      await notifier.notifyOuter();
      expect(alarm.playCount, 2);
      expect(vibration.startCount, 2);
    });
  });
}
