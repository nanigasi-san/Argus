# FOR AI
Dont change this file.

# Argus リファクタリング方針と規約

本ドキュメントは、Argusプロジェクトにおけるコードリファクタリング時の方針と規約を定義します。コードベースの一貫性を保ち、保守性とテスト容易性を向上させることを目的としています。

---

## 1. 抽象化と依存性注入

### 1.1 抽象クラスの使用

プラットフォーム固有の実装や外部依存関係を持つ機能は、抽象クラスを通じてアクセスします。

**良い例:**
```dart
abstract class LocationService {
  Stream<LocationFix> get stream;
  Future<void> start(AppConfig config);
  Future<void> stop();
}

abstract class AlarmPlayer {
  Future<void> start();
  Future<void> stop();
}

abstract class VibrationPlayer {
  Future<void> start();
  Future<void> stop();
}
```

### 1.2 依存性注入パターン

クラスはコンストラクタで依存関係を受け取り、テスト可能にします。デフォルト実装も提供します。

**良い例:**
```dart
class Notifier {
  Notifier({
    FlutterLocalNotificationsPlugin? plugin,
    LocalNotificationsClient? notificationsClient,
    AlarmPlayer? alarmPlayer,
    VibrationPlayer? vibrationPlayer,
  })  : _notifications = notificationsClient ??
            FlutterLocalNotificationsClient(
              plugin ?? FlutterLocalNotificationsPlugin(),
            ),
        _alarmPlayer = alarmPlayer ?? const RingtoneAlarmPlayer(),
        _vibrationPlayer = vibrationPlayer ?? RepeatingVibrationPlayer();
  
  final LocalNotificationsClient _notifications;
  final AlarmPlayer _alarmPlayer;
  final VibrationPlayer _vibrationPlayer;
}
```

**悪い例:**
```dart
class Notifier {
  final _plugin = FlutterLocalNotificationsPlugin(); // 直接インスタンス化
  final _alarmPlayer = RingtoneAlarmPlayer(); // テスト不可能
}
```

---

## 2. 命名規則

### 2.1 プライベートメンバー

プライベートフィールド、メソッド、変数は`_`で始めます。

```dart
class StateMachine {
  bool _initialized = false;
  GeoModel _geoModel = GeoModel.empty();
  
  void _evaluateInternal(LocationFix fix) {
    // 内部処理
  }
}
```

### 2.2 ブール値の命名

ブール値は`is`、`has`、`should`などのプレフィックスを使用します。

**良い例:**
```dart
bool _isAlarming = false;
bool _isRunning = false;
bool _shouldContinue = false;
bool hasGeoJson => _geoModel.hasGeometry;
```

**悪い例:**
```dart
bool _alarming = false; // 状態が不明確
bool _running = false;
```

### 2.3 定数の命名

クラス定数は`static const`で定義し、`UPPER_SNAKE_CASE`または`_camelCase`を使用します。

```dart
class Notifier {
  static const _channelId = 'argus_alerts';
  static const _channelName = 'Argus警告';
  static const _channelDescription = 'ジオフェンスの安全エリアから離れたときに通知します。';
  static const int _outerNotificationId = 1001;
}
```

### 2.4 クラスとファイル名

- クラス名: `PascalCase`（例: `AppController`, `StateMachine`）
- ファイル名: `snake_case.dart`（例: `app_controller.dart`, `state_machine.dart`）
- 1ファイル1クラスを原則とし、ファイル名はクラス名に対応させます

---

## 3. 定数と不変性

### 3.1 定数の使用

変更されない値は`const`または`static const`で定義します。

```dart
class RepeatingVibrationPlayer {
  static const _vibrationDurationSeconds = 5;
  static const _pauseDurationSeconds = 2;
}
```

### 3.2 不変性の推奨

可能な限り`final`を使用し、状態の変更を明示的にします。

**良い例:**
```dartをして
class AppController {
  final StateMachine stateMachine;
  final LocationService locationService;
  final FileManager fileManager;
  
  AppConfig? _config; // 変更可能な場合のみ非final
}
```

---

## 4. 非同期処理

### 4.1 async/awaitの使用

`Future`を返すメソッドでは`async/await`を使用します。`.then()`やコールバックは避けます。

**良い例:**
```dart
Future<void> initialize() async {
  if (_initialized) {
    return;
  }
  await _notifications.initialize(initSettings);
  await _notifications.requestPermissions();
  _initialized = true;
}
```

### 4.2 エラーハンドリング

例外を適切に捕捉し、ユーザーに分かりやすいメッセージを提供します。

**良い例:**
```dart
try {
  final model = GeoModel.fromGeoJson(geoJsonString);
  _geoModel = model;
} on FormatException catch (e) {
  _lastErrorMessage = 'Failed to parse GeoJSON: ${e.message}';
  _logError('APP', _lastErrorMessage!);
  notifyListeners();
} catch (e) {
  // 予期しない例外の処理
  final errorMessage = e.toString().toLowerCase();
  if (errorMessage.contains('cancel') || errorMessage.contains('user')) {
    return; // ユーザーキャンセルはエラーとして扱わない
  }
  _lastErrorMessage = 'Unable to open file: ${e.toString()}';
  _logError('APP', _lastErrorMessage!);
  notifyListeners();
}
```

### 4.3 非同期ループの制御

長時間実行される非同期ループでは、停止フラグと`try-finally`を使用してリソースを確実に解放します。

**良い例:**
```dart
class RepeatingVibrationPlayer {
  bool _shouldContinue = false;
  bool _isRunning = false;

  Future<void> _vibrationLoop() async {
    try {
      while (_shouldContinue) {
        await Vibration.vibrate(duration: _vibrationDurationSeconds * 1000);
        
        if (!_shouldContinue) break;
        
        await Future.delayed(const Duration(seconds: _pauseDurationSeconds));
      }
    } finally {
      _isRunning = false; // 必ず実行される
    }
  }

  Future<void> stop() async {
    _shouldContinue = false;
    await Vibration.cancel();
  }
}
```

---

## 5. 状態管理

### 5.1 ChangeNotifierとValueNotifier

UI更新が必要な状態は`ChangeNotifier`または`ValueNotifier`を使用します。

```dart
class AppController extends ChangeNotifier {
  StateSnapshot _snapshot = StateSnapshot(/* ... */);
  
  StateSnapshot get snapshot => _snapshot;
  
  void _updateSnapshot(StateSnapshot newSnapshot) {
    _snapshot = newSnapshot;
    notifyListeners(); // UI更新を通知
  }
}

class Notifier {
  final ValueNotifier<LocationStateStatus> badgeState =
      ValueNotifier<LocationStateStatus>(LocationStateStatus.waitGeoJson);
}
```

### 5.2 不変なスナップショット

状態のスナップショットは不変オブジェクトとして管理します。

```dart
class StateSnapshot {
  const StateSnapshot({
    required this.status,
    required this.timestamp,
    this.notes,
    // ...
  });
  
  final LocationStateStatus status;
  final DateTime timestamp;
  final String? notes;
}
```

---

## 6. ファクトリコンストラクタ

### 6.1 オブジェクト構築の制御

複雑な初期化や複数の構築パターンがある場合は、ファクトリコンストラクタを使用します。

**良い例:**
```dart
class GeoPolygon {
  factory GeoPolygon({
    required List<LatLng> points,
    String? name,
    int? version,
  }) {
    final sealed = _ensureClosed(points);
    final bounds = _Bounds.fromPoints(sealed);
    return GeoPolygon._(
      points: sealed,
      name: name,
      version: version,
      minLat: bounds.minLat,
      maxLat: bounds.maxLat,
      minLon: bounds.minLon,
      maxLon: bounds.maxLon,
    );
  }

  const GeoPolygon._({/* ... */}); // プライベートコンストラクタ

  factory GeoPolygon.empty() => GeoPolygon(points: const []);
}
```

---

## 7. コメントとドキュメント

### 7.1 ドキュメントコメント

公開API（クラス、メソッド）には`///`を使用したドキュメントコメントを付けます。

```dart
/// 5秒振動→2秒休止を繰り返すバイブレーションパターンを提供します。
class RepeatingVibrationPlayer implements VibrationPlayer {
  /// 5秒振動→2秒休止のパターンを繰り返すループを実行します。
  Future<void> _vibrationLoop() async {
    // ...
  }
}
```

### 7.2 インラインコメント

複雑なロジックや意図が明確でない箇所には説明コメントを追加します。

```dart
// outer になった場合は GPS_BAD の精度チェックでは取り消さない。
// ただし、実際に内側に戻ったかどうかはチェックする必要がある
if (fix.accuracyMeters == null || 
    fix.accuracyMeters! > _config.gpsAccuracyBadMeters) {
  // ...
}
```

---

## 8. テスト

### 8.1 モックとフェイクの命名

テスト用のモッククラスは`Fake`または`Mock`プレフィックスを使用します。

```dart
// test/support/notifier_fakes.dart
class FakeLocalNotificationsClient implements LocalNotificationsClient {
  final List<int> shownIds = <int>[];
  // ...
}

class FakeAlarmPlayer implements AlarmPlayer {
  int playCount = 0;
  int stopCount = 0;
  // ...
}
```

### 8.2 テストの構造

テストは`group`を使用して論理的にグループ化します。

```dart
void main() {
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
      expect(alarm.playCount, 1);
      expect(vibration.startCount, 1);
      // ...
    });
  });
}
```

### 8.3 テスト可能な設計

抽象クラスを実装することで、テスト時にモックを注入できるようにします。

---

## 9. コードの整理

### 9.1 importの順序

1. Dart標準ライブラリ（`dart:`）
2. Flutter SDK（`package:flutter`）
3. 外部パッケージ（`package:`）
4. プロジェクト内のファイル（相対パス）

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../state_machine/state.dart';
```

### 9.2 メソッドの分割

長いメソッドは責任ごとに分割します。1メソッドは1つのことを行うべきです。

**良い例:**
```dart
Future<void> loadGeoJson(String path) async {
  final content = await _readFileContent(path);
  final model = _parseGeoJson(content);
  _updateModel(model);
  _updateAreaIndex(model.polygons);
}

String _extractFileName(String path) {
  // ファイル名抽出ロジック
}

String _normalizeToGeoJson(String fileName) {
  // 拡張子正規化ロジック
}
```

---

## 10. リファクタリング時のチェックリスト

コードをリファクタリングする際は、以下の項目を確認してください:

- [ ] 抽象クラスを使用してテスト可能になっているか
- [ ] 依存関係はコンストラクタインジェクションで渡されているか
- [ ] プライベートメンバーは`_`で始まっているか
- [ ] ブール値は適切なプレフィックス（`is`, `has`, `should`）を使用しているか
- [ ] 変更されない値は`const`で定義されているか
- [ ] 非同期処理は`async/await`を使用しているか
- [ ] エラーハンドリングは適切に行われているか
- [ ] 状態管理に`ChangeNotifier`または`ValueNotifier`を使用しているか
- [ ] 公開APIにはドキュメントコメントが付いているか
- [ ] テストが更新され、すべて通過しているか
- [ ] `flutter analyze`でエラーや警告がないか

---

## 11. 参考例

### 11.1 完全な例: Notifierクラス

以下の例は、本ドキュメントの原則に従った実装です:

```dart
class Notifier {
  Notifier({
    FlutterLocalNotificationsPlugin? plugin,
    LocalNotificationsClient? notificationsClient,
    AlarmPlayer? alarmPlayer,
    VibrationPlayer? vibrationPlayer,
  })  : _notifications = notificationsClient ??
            FlutterLocalNotificationsClient(
              plugin ?? FlutterLocalNotificationsPlugin(),
            ),
        _alarmPlayer = alarmPlayer ?? const RingtoneAlarmPlayer(),
        _vibrationPlayer = vibrationPlayer ?? RepeatingVibrationPlayer();

  final LocalNotificationsClient _notifications;
  final AlarmPlayer _alarmPlayer;
  final VibrationPlayer _vibrationPlayer;

  static const _channelId = 'argus_alerts';
  static const _channelName = 'Argus警告';
  static const int _outerNotificationId = 1001;

  bool _initialized = false;
  bool _isAlarming = false;

  Future<void> notifyOuter() async {
    await initialize();
    // ...
    if (!_isAlarming) {
      await _alarmPlayer.start();
      await _vibrationPlayer.start();
      _isAlarming = true;
    }
  }

  Future<void> stopAlarm() async {
    if (_isAlarming) {
      await _alarmPlayer.stop();
      await _vibrationPlayer.stop();
      _isAlarming = false;
    }
  }
}
```

---

## 12. まとめ

これらの方針と規約に従うことで、以下のメリットが得られます:

- **テスト容易性**: 依存性注入により、モックを簡単に注入できます
- **保守性**: 一貫した命名と構造により、コードの理解が容易になります
- **拡張性**: 抽象クラスにより、新しい実装を追加しやすくなります
- **信頼性**: 適切なエラーハンドリングと状態管理により、堅牢なアプリケーションを構築できます

リファクタリング時は、このドキュメントを参照し、コードベース全体の一貫性を保つようにしてください。
