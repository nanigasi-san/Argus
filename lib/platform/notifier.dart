import 'package:flutter/foundation.dart';

import '../state_machine/state.dart';

class Notifier {
  Notifier();

  final ValueNotifier<LocationStateStatus> badgeState =
      ValueNotifier<LocationStateStatus>(
    LocationStateStatus.waitGeoJson,
  );

  Future<void> notifyOuter() async {
    debugPrint('Argus: outer boundary crossed');
  }

  Future<void> notifyRecover() async {
    debugPrint('Argus: re-entered safe zone');
  }

  Future<void> updateBadge(LocationStateStatus status) async {
    badgeState.value = status;
  }
}
