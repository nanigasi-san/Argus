# Argus
![App icon](./icon.png)

[![codecov](https://codecov.io/gh/nanigasi-san/Argus/branch/main/graph/badge.svg)](https://codecov.io/gh/YOUR_USERNAME/Argus)
[![CI](https://github.com/nanigasi-san/Argus/workflows/CI/badge.svg)](https://github.com/YOUR_USERNAME/Argus/actions)

## ビルド手順

### Android

```bash
# 依存関係のインストール
flutter pub get

# APKのビルド
flutter build apk

# リリースAPKのビルド
flutter build apk --release
```

### iOS

**前提条件:**
- macOS環境が必要です
- Xcodeがインストールされている必要があります
- CocoaPodsがインストールされている必要があります

```bash
# 依存関係のインストール
flutter pub get

# iOS依存関係のインストール
cd ios
pod install
cd ..

# iOSシミュレータで実行
flutter run

# リリースビルド
flutter build ios --release
```

**iOSで必要な権限:**
- **位置情報（常時）**: バックグラウンド実行中も安全エリアを監視するため
- **位置情報（使用中）**: アプリを使用中に安全エリアを監視するため
- **カメラ**: QRコードをスキャンしてGeoJSONを読み込むため
- **通知**: 安全エリアからの離脱を通知するため

これらの権限は`ios/Runner/Info.plist`に設定されており、初回起動時にユーザーに許可を求めます。

## テストカバレッジ

```bash
# カバレッジを取得
flutter test --coverage

# カバレッジ率を確認
python scripts/parse_coverage.py

# カバレッジレポートをHTML形式で生成（lcovが必要）
genhtml coverage/lcov.info -o coverage/html
```

### 現在のカバレッジ

**全体カバレッジ: 65.7%** (1006/1532 lines)

#### テスト統計
- **総テスト数**: 105件
- **テストファイル数**: 複数ファイル
  - `state_machine_test.dart`: 11テスト
  - `state_machine_transitions_test.dart`: 28テスト（全状態遷移をカバー）
  - `hysteresis_counter_test.dart`: 7テスト
  - `point_in_polygon_test.dart`: 9テスト
  - `geo_model_test.dart`: 13テスト
  - `app_controller_test.dart`: 3テスト
  - `platform/notifier_test.dart`: 2テスト（iOS通知設定のテストを含む）
  - `platform/location_service_test.dart`: iOS/Android設定のテストを含む

#### ファイル別カバレッジ

| ファイル                                    | カバレッジ | 行数   |
| ------------------------------------------- | ---------- | ------ |
| `lib/geo/geo_model.dart`                    | 100.0%     | 59/59  |
| `lib/geo/area_index.dart`                   | 100.0%     | 20/20  |
| `lib/geo/point_in_polygon.dart`             | 100.0%     | 66/66  |
| `lib/state_machine/hysteresis_counter.dart` | 100.0%     | 13/13  |
| `lib/state_machine/state_machine.dart`      | 94.1%      | 95/101 |
| `lib/io/config.dart`                        | 72.4%      | 21/29  |
| `lib/main.dart`                             | 63.6%      | 7/11   |
| `lib/state_machine/state.dart`              | 63.6%      | 7/11   |
| `lib/platform/notifier.dart`                | 55.9%      | 38/68  |
| `lib/ui/home_page.dart`                     | 33.7%      | 82/243 |
| `lib/app_controller.dart`                   | 28.3%      | 56/198 |
| `lib/io/log_entry.dart`                     | 7.7%       | 1/13   |
| `lib/platform/location_service.dart`        | 2.3%       | 1/43   |
| `lib/io/logger.dart`                        | 2.8%       | 1/36   |
| `lib/ui/settings_page.dart`                 | 0.6%       | 1/164  |
| `lib/io/file_manager.dart`                  | 0.0%       | 0/22   |

詳細なカバレッジレポートは `coverage/html/index.html` で確認できます。