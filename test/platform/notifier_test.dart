import 'package:flutter_test/flutter_test.dart';
import 'package:argus/platform/notifier.dart';
import '../support/notifier_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notifier', () {
    test('outer -> inner -> outer toggles alarm playback', () async {
      final notifications = FakeLocalNotificationsClient();
      final alarm = FakeAlarmPlayer();
      final notifier = Notifier(
        notificationsClient: notifications,
        alarmPlayer: alarm,
      );

      await notifier.notifyOuter();
      expect(notifications.shownIds.single, 1001);
      expect(alarm.playCount, 1);
      expect(alarm.stopCount, 0);

      await notifier.notifyRecover();
      expect(notifications.cancelledIds.single, 1001);
      expect(alarm.stopCount, 1);

      await notifier.notifyOuter();
      expect(alarm.playCount, 2);
    });
  });
}
