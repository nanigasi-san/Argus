# Argus テスト仕様書

本書は `Argus` アプリケーションのテストスイートの詳細な説明を提供します。

---

## テストファイル一覧

| ファイル名 | 対象クラス/機能 | テスト数 |
| --------- | -------------- | ------- |
| `state_machine_test.dart` | `StateMachine`, ��ԑJ�� | 11 |
| `hysteresis_counter_test.dart` | `HysteresisCounter` | 7 |
| `point_in_polygon_test.dart` | `PointInPolygon`, 内外判定 | 9 |
| `geo_model_test.dart` | `GeoModel`, `GeoPolygon`, GeoJSONパース | 13 |
| `app_controller_test.dart` | `AppController` | 3 |
| **���v** | | **43** |

---

## 1. state_machine_test.dart

状態マシンの動作を検証するテストです。`StateMachine` は位置情報から現在の状態（`INNER`, `NEAR`, `OUTER`, `GPS_BAD`, `WAIT_GEOJSON` など）を判定します。

### テストケース

#### 1.1 `returns INNER when fix is inside with healthy accuracy`
- **目的**: ポリゴン内部で精度が良好な位置情報が `INNER` 状態になることを確認
- **前提条件**: GeoJSONがロード済み、精度 < 40m
- **期待結果**: `LocationStateStatus.inner`

#### 1.2 `returns NEAR when inside but close to boundary`
- **目的**: ポリゴン内部だが境界から30m以内の場合に `NEAR` 状態になることを確認
- **前提条件**: ポリゴン内部、境界距離 < `innerBufferM` (30m)
- **期待結果**: `LocationStateStatus.near`

#### 1.3 `transitions to OUTER after hysteresis when outside`
- **目的**: ポリゴン外部でヒステリシス条件（サンプル数 + 経過時間）を満たすと `OUTER` に遷移することを確認
- **前提条件**: ポリゴン外部、`leaveConfirmSamples=3`, `leaveConfirmSeconds=10`
- **手順**:
  1. 外部の位置で評価 → `OUTER_PENDING`
  2. 3回のサンプルを追加（各10秒以上経過）
- **期待結果**: 最終的に `LocationStateStatus.outer`

#### 1.4 `returns WAIT_GEOJSON when GeoJSON is not loaded`
- **目的**: GeoJSON未ロード時に `WAIT_GEOJSON` 状態になることを確認
- **前提条件**: `StateMachine` にGeoJSONが設定されていない
- **期待結果**: `LocationStateStatus.waitGeoJson`, `hasGeoJson = false`

#### 1.5 `returns GPS_BAD when accuracy is too low`
- **目的**: GPS精度が設定値（40m）を超える場合に `GPS_BAD` 状態になることを確認
- **前提条件**: `accuracyMeters > gpsAccuracyBadMeters` (40m)
- **期待結果**: `LocationStateStatus.gpsBad`

#### 1.6 `returns GPS_BAD when accuracy is null`
- **目的**: GPS精度情報が欠損している場合に `GPS_BAD` 状態になることを確認
- **前提条件**: `accuracyMeters = null`
- **期待結果**: `LocationStateStatus.gpsBad`

#### 1.7 `resets hysteresis and transitions to INNER when recovering from OUTER`
- **目的**: `OUTER` 状態から `INNER` に復帰する際、ヒステリシスカウンタがリセットされることを確認
- **手順**:
  1. 外部で `OUTER` 状態になる
  2. 内部の位置情報を評価
- **期待結果**: `LocationStateStatus.inner`、ヒステリシスがリセット

#### 1.8 `recovers from GPS_BAD to INNER when accuracy improves`
- **目的**: GPS精度が改善した際に `GPS_BAD` から正常状態に復帰することを確認
- **手順**:
  1. 精度不良（50m）で `GPS_BAD`
  2. 精度良好（5m）で再評価
- **期待結果**: `LocationStateStatus.inner`

#### 1.9 `resets hysteresis when moving from OUTER_PENDING to INNER`
- **目的**: `OUTER_PENDING` 状態から内部に戻った際、ヒステリシスがリセットされることを確認
- **手順**:
  1. 外部で `OUTER_PENDING`
  2. 内部に移動して `INNER`
  3. 再度外部に移動
- **期待結果**: 再度外部に移動した際、`OUTER_PENDING` からヒステリシスを再開

#### 1.10 `transitions from OUTER to INNER even with bad GPS when inside`
- **狙い**: OUTER 維持中でも測位精度が悪いまま内側へ戻った際に即座に inner へ復帰することを確認
- **期待結果**: 状態が `LocationStateStatus.inner` へ遷移し、ヒステリシスがリセットされる

#### 1.11 `maintains OUTER with bad GPS when still outside`
- **狙い**: OUTER 継続中に精度が悪化しても位置が依然として外側なら OUTER を維持することを確認
- **期待結果**: 状態は `LocationStateStatus.outer` のまま継続し、距離情報が保持される

---

## 2. hysteresis_counter_test.dart

ヒステリシスカウンタの動作を検証するテストです。`HysteresisCounter` は退出判定のための遅延機構を提供します。

### テストケース

#### 2.1 `starts with no samples`
- **目的**: 初期状態でサンプル数が0であることを確認
- **期待結果**: `isSatisfied()` が `false` を返す

#### 2.2 `requires both sample count and duration`
- **目的**: サンプル数と経過時間の両方が条件を満たす必要があることを確認
- **手順**: サンプルを追加するが、時間が不十分な場合は条件未達成
- **期待結果**: 両方の条件を満たした時のみ `true`

#### 2.3 `requires both sample count and duration - time first`
- **目的**: 時間が先に満たされても、サンプル数が不足している場合は条件未達成であることを確認

#### 2.4 `resets counter`
- **目的**: `reset()` メソッドがカウンタを正しくリセットすることを確認
- **期待結果**: リセット後、再度条件判定から開始

#### 2.5 `handles zero samples requirement`
- **目的**: サンプル数要件が0の場合の動作を確認
- **期待結果**: 時間要件のみで判定

#### 2.6 `handles zero duration requirement`
- **目的**: 時間要件が0の場合の動作を確認
- **期待結果**: サンプル数のみで判定

#### 2.7 `first sample timestamp is preserved`
- **目的**: 最初のサンプルのタイムスタンプが保持され、経過時間計算の基準になることを確認
- **期待結果**: 最初のサンプルからの経過時間で判定

---

## 3. point_in_polygon_test.dart

点とポリゴンの関係を判定する機能を検証するテストです。レイキャスト法による内外判定と境界距離計算をテストします。

### テストケース

#### 3.1 `correctly identifies point inside polygon`
- **目的**: ポリゴン内部の点を正しく識別できることを確認
- **期待結果**: `contains = true`, `distanceToBoundaryM > 0`

#### 3.2 `correctly identifies point outside polygon`
- **目的**: ポリゴン外部の点を正しく識別できることを確認
- **期待結果**: `contains = false`

#### 3.3 `correctly identifies point on boundary`
- **目的**: 境界上の点の処理を確認
- **期待結果**: レイキャスト法の実装により判定は変動する可能性があるが、距離は0に近い値（< 100m）になる

#### 3.4 `calculates distance to boundary for inside point`
- **目的**: 内部点から境界までの距離計算の正確性を確認
- **期待結果**: 中心点の距離 > 境界近くの点の距離

#### 3.5 `calculates distance to boundary for outside point`
- **目的**: 外部点から境界までの距離計算の正確性を確認
- **期待結果**: 遠い点の距離 > 近い点の距離

#### 3.6 `handles complex polygon shape`
- **目的**: L字型など複雑な形状のポリゴンでも正しく動作することを確認
- **テスト**: L字型ポリゴンでの内外判定（内部点と外部点の両方を検証）

#### 3.7 `handles triangle polygon`
- **目的**: 三角形ポリゴンでも正しく動作することを確認

#### 3.8 `raycast handles edge cases`
- **目的**: 頂点上や辺上の点などエッジケースの処理を確認
- **期待結果**: クラッシュしない、妥当な結果を返す

#### 3.9 `distance calculation for point near corner`
- **目的**: 角付近の点での距離計算の正確性を確認

---

## 4. geo_model_test.dart

GeoJSONのパースとポリゴン生成を検証するテストです。

### GeoPolygon テスト

#### 4.1 `creates polygon with valid points`
- **目的**: 有効な点からポリゴンを作成できることを確認
- **期待結果**: ポリゴンが自動的に閉じられる（4点入力 → 5点出力）、境界（bounds）が正しく計算される

#### 4.2 `closes polygon if not already closed`
- **目的**: 閉じていないポリゴンを自動的に閉じることを確認
- **期待結果**: 最初の点と最後の点が一致する

#### 4.3 `does not duplicate closing point if already closed`
- **目的**: 既に閉じているポリゴンに重複ポイントを追加しないことを確認

#### 4.4 `calculates bounds correctly`
- **目的**: バウンディングボックスの計算が正確であることを確認

### GeoModel テスト

#### 4.5 `creates empty model`
- **目的**: 空のモデルが正しく作成されることを確認
- **期待結果**: `hasGeometry = false`

#### 4.6 `creates model with polygons`
- **目的**: 複数のポリゴンを含むモデルを作成できることを確認

#### 4.7 `parses GeoJSON FeatureCollection with Polygon`
- **目的**: 標準的なGeoJSONのPolygonを正しくパースできることを確認
- **期待結果**: プロパティ（name, version）も正しく読み込まれる

#### 4.8 `parses GeoJSON FeatureCollection with MultiPolygon`
- **目的**: MultiPolygonを正しくパースし、複数のポリゴンに分解できることを確認

#### 4.9 `handles empty FeatureCollection`
- **目的**: 空のFeatureCollectionを正しく処理できることを確認

#### 4.10 `handles GeoJSON with unsupported geometry types`
- **目的**: サポートされていないジオメトリタイプ（Point等）をスキップできることを確認
- **期待結果**: Polygonのみがパースされる

#### 4.11 `handles polygons with insufficient points`
- **目的**: 点が不足しているポリゴン（3点未満）をスキップできることを確認

#### 4.12 `handles missing properties`
- **目的**: プロパティが欠損しているGeoJSONでもパースできることを確認

#### 4.13 `handles empty MultiPolygon`
- **目的**: 空のMultiPolygonを正しく処理できることを確認

---

## 5. app_controller_test.dart

AppController の動作とログ出力をカバーするテストセット。開発者モードの振る舞いを確認する。

### テストケース

#### 5.1 `loading new GeoJSON resets to init and stops alarm`
 - **狙い**: GeoJSON を再ロードした際に状態が init に戻り、アラームが停止することを確認
 - **期待結果**: LocationStateStatus.init / stateMachine.current = init / アラーム停止

#### 5.2 `describeSnapshot hides navigation details before OUTER`
 - **狙い**: 開発者モード OFF では INNER/NEAR 中に距離・方角が伏せられることを検証
 - **期待結果**: ログ文字列に dist=- と earing=- が含まれる

#### 5.3 `describeSnapshot reveals navigation details in developer mode`
 - **狙い**: 開発者モード ON で距離・方角・ターゲット座標が露出することを確認
 - **期待結果**: ログ文字列に距離と方角 (deg)・座標が含まれる
---

## テスト実行方法

すべてのテストを実行:
```bash
flutter test
```

特定のテストファイルを実行:
```bash
flutter test test/state_machine_test.dart
```

特定のテストケースを実行:
```bash
flutter test test/state_machine_test.dart --name "returns INNER"
```

---

## テストカバレッジ

現在のテストスイート（全39件）は以下の機能をカバーしています:

✅ **状態管理** (9件)
- すべての状態遷移（WAIT_GEOJSON, GPS_BAD, INNER, NEAR, OUTER_PENDING, OUTER）
- ヒステリシス機構と条件チェック
- 状態復帰とリセット動作
- GPS精度による状態遷移

✅ **地理空間計算** (9件)
- 内外判定（レイキャスト法）
- 境界距離計算（ハバースイン距離）
- 複雑な形状（L字型、三角形）の処理
- エッジケース（境界上、頂点上）の処理

✅ **GeoJSON処理** (13件)
- Polygon/MultiPolygonパース
- プロパティ（name, version）の読み込み
- エラーハンドリング（空のFeatureCollection、未対応ジオメトリタイプ、点不足など）
- ポリゴンの自動閉鎖機能

✅ **ヒステリシス** (7件)
- サンプル数カウント
- 経過時間チェック
- 両方の条件を満たす必要があることの検証
- リセット機能
- エッジケース（ゼロ要件）の処理

---

## テスト統計

- **総テスト数**: 39件
- **テストファイル数**: 5ファイル
- **成功率**: 100% (すべてのテストが通過)
- **主要カバレッジ**: 状態管理、地理空間計算、GeoJSON処理、ヒステリシス機構

## 今後の拡張予定

以下の機能について追加のテストケースを検討中:

- [ ] `AppController` の統合テスト
- [ ] `EventLogger` のログ出力テスト
- [ ] `AreaIndex` のインデックス機能テスト
- [ ] より複雑なGeoJSONファイルのパーステスト
- [ ] エッジケースの追加（極端な座標値、ポリゴンの自己交差など）
- [ ] パフォーマンステスト（大量のポリゴン、高頻度の評価）

---

## 参考資料

- [技術仕様書 (spec.md)](./spec.md)
- [Flutter Testing Guide](https://docs.flutter.dev/testing)

