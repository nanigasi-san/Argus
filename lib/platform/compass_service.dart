import 'package:flutter_compass/flutter_compass.dart';

/// 端末の磁気コンパスを読み取るための抽象インターフェース。
abstract class CompassService {
  /// 北を 0 度として時計回りに表した端末の方位を発行します。
  ///
  /// センサーが方位を算出できない端末では null を発行することがあります。
  Stream<double?> get headings;
}

/// flutter_compass を使う実機向けの [CompassService] 実装。
class FlutterCompassService implements CompassService {
  const FlutterCompassService();

  @override
  Stream<double?> get headings {
    final events = FlutterCompass.events;
    if (events == null) {
      return const Stream<double?>.empty();
    }
    return events.map((event) => event.heading);
  }
}
