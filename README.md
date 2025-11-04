# Argus
![App icon](./icon.png)

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

**全体カバレッジ: 50.1%** (341/680 lines)

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
| `lib/state_machine/state_machine.dart`      | 92.2%      | 95/103 |
| `lib/state_machine/state.dart`              | 63.6%      | 7/11   |
| `lib/platform/notifier.dart`                | 51.1%      | 24/47  |
| `lib/app_controller.dart`                   | 25.5%      | 53/208 |
| `lib/io/log_entry.dart`                     | 7.7%       | 1/13   |
| `lib/io/config.dart`                        | 3.4%       | 1/29   |
| `lib/io/logger.dart`                        | 2.8%       | 1/36   |
| `lib/platform/location_service.dart`        | 2.3%       | 1/43   |
| `lib/io/file_manager.dart`                  | 0.0%       | 0/32   |

詳細なカバレッジレポートは `coverage/html/index.html` で確認できます。