# Argus
![App icon](./icon.png)

[![codecov](https://codecov.io/gh/YOUR_USERNAME/Argus/branch/main/graph/badge.svg)](https://codecov.io/gh/YOUR_USERNAME/Argus)
[![CI](https://github.com/YOUR_USERNAME/Argus/workflows/CI/badge.svg)](https://github.com/YOUR_USERNAME/Argus/actions)

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

**全体カバレッジ: 42.5%** (457/1076 lines)

#### テスト統計
- **総テスト数**: 73件
- **テストファイル数**: 7ファイル
  - `state_machine_test.dart`: 11テスト
  - `state_machine_transitions_test.dart`: 28テスト（全状態遷移をカバー）
  - `hysteresis_counter_test.dart`: 7テスト
  - `point_in_polygon_test.dart`: 9テスト
  - `geo_model_test.dart`: 13テスト
  - `app_controller_test.dart`: 3テスト
  - `platform/notifier_test.dart`: 2テスト

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
| `lib/platform/notifier.dart`                | 57.4%      | 27/47  |
| `lib/ui/home_page.dart`                     | 33.7%      | 82/243 |
| `lib/app_controller.dart`                   | 28.3%      | 56/198 |
| `lib/io/log_entry.dart`                     | 7.7%       | 1/13   |
| `lib/platform/location_service.dart`        | 2.3%       | 1/43   |
| `lib/io/logger.dart`                        | 2.8%       | 1/36   |
| `lib/ui/settings_page.dart`                 | 0.6%       | 1/164  |
| `lib/io/file_manager.dart`                  | 0.0%       | 0/22   |

詳細なカバレッジレポートは `coverage/html/index.html` で確認できます。