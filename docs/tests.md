# Argus テスト仕様書

本書は `Argus` アプリケーションのテストスイートの詳細な説明を提供します。

---

## テストファイル一覧

| ファイル名                                          | 対象クラス/機能                         | テスト数 |
| --------------------------------------------------- | --------------------------------------- | -------- |
| `state_machine/state_machine_test.dart`             | `StateMachine`, 基本状態判定            | 11       |
| `state_machine/state_machine_transitions_test.dart` | `StateMachine`, 状態遷移                | 28       |
| `state_machine/hysteresis_counter_test.dart`        | `HysteresisCounter`                     | 7        |
| `state_machine/state_snapshot_test.dart`            | `StateSnapshot`                         | 1        |
| `geo/point_in_polygon_test.dart`                    | `PointInPolygon`, 内外判定              | 11       |
| `geo/geo_model_test.dart`                           | `GeoModel`, `GeoPolygon`, GeoJSONパース | 13       |
| `app_controller_test.dart`                          | `AppController`                         | 3        |
| `platform/notifier_test.dart`                       | `Notifier`                              | 1        |
| `io/logger_test.dart`                               | `EventLogger`                           | 4        |
| `ui/home_page_test.dart`                            | `HomePage`                              | 3        |
| `ui/settings_page_test.dart`                        | `SettingsPage`                          | 3        |
| `main_test.dart`                                    | `ArgusApp`                              | 1        |
| `widget_test.dart`                                  | Widget統合テスト                        | 1        |
| **合計**                                            |                                         | **88**   |

---

## 1. state_machine/state_machine_test.dart

状態マシンの基本動作を検証するテストです。`StateMachine` は位置情報から現在の状態（`INNER`, `NEAR`, `OUTER`, `GPS_BAD`, `WAIT_GEOJSON` など）を判定します。

### テストケース

#### 1.1 `returns INNER when fix is inside with healthy accuracy`
- **目的**: ポリゴン内部で精度が良好な位置情報が `INNER` 状態になることを確認
- **前提条件**: GeoJSONがロード済み、精度 < 40m、境界からの距離 >= innerBufferM (30m)
- **テストデータ**: 緯度35.005、経度139.005、精度5m（ポリゴン中心付近）
- **期待結果**: `LocationStateStatus.inner`

#### 1.2 `returns NEAR when inside but close to boundary`
- **目的**: ポリゴン内部だが境界から30m以内の場合に `NEAR` 状態になることを確認
- **前提条件**: ポリゴン内部、境界距離 < `innerBufferM` (30m)
- **テストデータ**: 緯度35.0、経度139.0095（境界近く）
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
- **期待結果**: `LocationStateStatus.waitGeoJson`, `geoJsonLoaded = false`

#### 1.5 `returns GPS_BAD when accuracy is too low`
- **目的**: GPS精度が設定値（40m）を超える場合に `GPS_BAD` 状態になることを確認
- **前提条件**: `accuracyMeters > gpsAccuracyBadMeters` (40m)
- **テストデータ**: 精度50m
- **期待結果**: `LocationStateStatus.gpsBad`, `horizontalAccuracyM = 50`

#### 1.6 `returns GPS_BAD when accuracy is null`
- **目的**: GPS精度情報が欠損している場合に `GPS_BAD` 状態になることを確認
- **前提条件**: `accuracyMeters = null`
- **期待結果**: `LocationStateStatus.gpsBad`

#### 1.7 `resets hysteresis and transitions to INNER when recovering from OUTER`
- **目的**: `OUTER` 状態から `INNER` に復帰する際、ヒステリシスカウンタがリセットされることを確認
- **手順**:
  1. 外部で `OUTER` 状態になる（ヒステリシス条件を満たす）
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
- **目的**: OUTER 維持中でも測位精度が悪いまま内側へ戻った際に即座に inner へ復帰することを確認
- **手順**:
  1. 外部で `OUTER` 状態になる
  2. 内部に戻るが精度が悪い（50m）
- **期待結果**: 状態が `LocationStateStatus.inner` へ遷移し、ヒステリシスがリセットされる

#### 1.11 `maintains OUTER with bad GPS when still outside`
- **目的**: OUTER 継続中に精度が悪化しても位置が依然として外側なら OUTER を維持することを確認
- **手順**:
  1. 外部で `OUTER` 状態になる
  2. 精度が悪化（50m）するが、依然として外側
- **期待結果**: 状態は `LocationStateStatus.outer` のまま継続し、距離情報が保持される

---

## 2. state_machine/state_machine_transitions_test.dart

状態マシンの詳細な状態遷移を検証するテストです。すべての可能な状態遷移パターンを網羅的にテストします。

### テストケース

#### 2.1 `waitGeoJson → waitStart (updateGeometry)`
- **目的**: GeoJSONロード時に `waitGeoJson` から `waitStart` に遷移することを確認
- **手順**: `updateGeometry()` を呼び出す
- **期待結果**: `current = LocationStateStatus.waitStart`

#### 2.2 `waitGeoJson → waitGeoJson (evaluate without geometry)`
- **目的**: GeoJSON未ロード時に `evaluate()` を呼び出しても `waitGeoJson` を維持することを確認
- **期待結果**: `status = LocationStateStatus.waitGeoJson`

#### 2.3 `waitStart → inner`
- **目的**: 監視開始後、エリア内（精度良好、distance >= innerBufferM）で `inner` に遷移することを確認

#### 2.4 `waitStart → near`
- **目的**: 監視開始後、エリア内（精度良好、distance < innerBufferM）で `near` に遷移することを確認

#### 2.5 `waitStart → outerPending`
- **目的**: 監視開始後、エリア外（精度良好、hysteresis未到達）で `outerPending` に遷移することを確認

#### 2.6 `waitStart → gpsBad`
- **目的**: 監視開始後、精度不良で `gpsBad` に遷移することを確認

#### 2.7-2.10 `inner` からの遷移
- **inner → inner (継続)**: エリア内継続（精度良好、distance >= innerBufferM）
- **inner → near**: エリア内（精度良好、distance < innerBufferM）
- **inner → outerPending**: エリア外（精度良好、hysteresis未到達）
- **inner → gpsBad**: 精度不良

#### 2.11-2.14 `near` からの遷移
- **near → inner**: エリア内（精度良好、distance >= innerBufferM）
- **near → near (継続)**: エリア内継続（精度良好、distance < innerBufferM）
- **near → outerPending**: エリア外（精度良好、hysteresis未到達）
- **near → gpsBad**: 精度不良

#### 2.15-2.19 `outerPending` からの遷移
- **outerPending → inner**: エリア内に戻る（精度良好、distance >= innerBufferM）
- **outerPending → near**: エリア内に戻る（精度良好、distance < innerBufferM）
- **outerPending → outer**: エリア外継続（精度良好、hysteresis到達）
- **outerPending → outerPending (継続)**: エリア外継続（精度良好、hysteresis未到達）
- **outerPending → gpsBad**: 精度不良

#### 2.20-2.24 `outer` からの遷移
- **outer → inner (精度良好)**: エリア内に戻る（精度良好、distance >= innerBufferM）
- **outer → near (精度良好)**: エリア内に戻る（精度良好、distance < innerBufferM）
- **outer → inner (精度不良でも内側)**: エリア内に戻る（精度不良でも内側）
- **outer → near (精度不良でも内側)**: エリア内に戻る（精度不良でも内側）
- **outer → outer (精度不良でも外側)**: エリア外継続（精度不良でも外側）

#### 2.25-2.28 `gpsBad` からの遷移
- **gpsBad → inner**: 精度改善 + エリア内（distance >= innerBufferM）
- **gpsBad → near**: 精度改善 + エリア内（distance < innerBufferM）
- **gpsBad → outerPending**: 精度改善 + エリア外（hysteresis未到達）
- **gpsBad → gpsBad (継続)**: 精度不良継続

---

## 3. state_machine/hysteresis_counter_test.dart

ヒステリシスカウンタの動作を検証するテストです。`HysteresisCounter` は退出判定のための遅延機構を提供します。

### テストケース

#### 3.1 `starts with no samples`
- **目的**: 初期状態でサンプル数が0であることを確認
- **期待結果**: `isSatisfied()` が `false` を返す

#### 3.2 `requires both sample count and duration`
- **目的**: サンプル数と経過時間の両方が条件を満たす必要があることを確認
- **手順**: サンプルを追加するが、時間が不十分な場合は条件未達成
- **期待結果**: 両方の条件を満たした時のみ `true`

#### 3.3 `requires both sample count and duration - time first`
- **目的**: 時間が先に満たされても、サンプル数が不足している場合は条件未達成であることを確認
- **手順**: 1サンプル追加後、15秒経過しても条件未達成。さらに2サンプル追加で条件達成
- **期待結果**: サンプル数と時間の両方が満たされた時のみ `true`

#### 3.4 `resets counter`
- **目的**: `reset()` メソッドがカウンタを正しくリセットすることを確認
- **手順**: サンプルを追加後、`reset()` を呼び出す
- **期待結果**: リセット後、再度条件判定から開始

#### 3.5 `handles zero samples requirement`
- **目的**: サンプル数要件が0の場合の動作を確認
- **設定**: `requiredSamples: 0`, `requiredDuration: 10秒`
- **期待結果**: 時間要件のみで判定（サンプル追加後10秒経過で条件達成）

#### 3.6 `handles zero duration requirement`
- **目的**: 時間要件が0の場合の動作を確認
- **設定**: `requiredSamples: 3`, `requiredDuration: 0`
- **期待結果**: サンプル数のみで判定（3サンプル追加で条件達成）

#### 3.7 `first sample timestamp is preserved`
- **目的**: 最初のサンプルのタイムスタンプが保持され、経過時間計算の基準になることを確認
- **手順**: 最初のサンプルを追加後、後続のサンプルを追加
- **期待結果**: 最初のサンプルからの経過時間で判定

---

## 4. state_machine/state_snapshot_test.dart

`StateSnapshot` の `copyWith` メソッドの動作を検証するテストです。

### テストケース

#### 4.1 `copyWith overrides selected fields`
- **目的**: `copyWith` メソッドが選択したフィールドのみを上書きし、他のフィールドは保持することを確認
- **手順**: 元の `StateSnapshot` から `copyWith` で一部フィールドを変更
- **期待結果**: 変更したフィールドのみが更新され、他のフィールドは元の値が保持される

---

## 5. geo/point_in_polygon_test.dart

点とポリゴンの関係を判定する機能を検証するテストです。レイキャスト法による内外判定と境界距離計算をテストします。

### テストケース

#### 5.1 `correctly identifies point inside polygon`
- **目的**: ポリゴン内部の点を正しく識別できることを確認
- **テストデータ**: 正方形ポリゴンの中心点（緯度35.005、経度139.005）
- **期待結果**: `contains = true`, `distanceToBoundaryM > 0`, `nearestPoint` と `bearingToBoundaryDeg` が設定される

#### 5.2 `correctly identifies point outside polygon`
- **目的**: ポリゴン外部の点を正しく識別できることを確認
- **テストデータ**: 正方形ポリゴンの外部（緯度35.02、経度139.02）
- **期待結果**: `contains = false`, `distanceToBoundaryM > 0`

#### 5.3 `correctly identifies point on boundary`
- **目的**: 境界上の点の処理を確認
- **テストデータ**: 正方形ポリゴンの西側の辺上（緯度35.005、経度139.0）
- **期待結果**: 距離は0に近い値（< 100m）

#### 5.4 `calculates distance to boundary for inside point`
- **目的**: 内部点から境界までの距離計算の正確性を確認
- **テストデータ**: 中心点と境界近くの点を比較
- **期待結果**: 中心点の距離 > 境界近くの点の距離

#### 5.5 `calculates distance to boundary for outside point`
- **目的**: 外部点から境界までの距離計算の正確性を確認
- **テストデータ**: 遠い点と近い点を比較
- **期待結果**: 遠い点の距離 > 近い点の距離

#### 5.6 `handles complex polygon shape`
- **目的**: L字型など複雑な形状のポリゴンでも正しく動作することを確認
- **テストデータ**: L字型ポリゴンでの内外判定（内部点と外部点の両方を検証）
- **期待結果**: 内部点は `contains = true`、外部点は `contains = false`

#### 5.7 `handles triangle polygon`
- **目的**: 三角形ポリゴンでも正しく動作することを確認
- **テストデータ**: 三角形ポリゴンでの内外判定
- **期待結果**: 内部点は `contains = true`、外部点は `contains = false`

#### 5.8 `raycast handles edge cases`
- **目的**: 頂点上や辺上の点などエッジケースの処理を確認
- **テストデータ**: 頂点上の点、水平辺上の点
- **期待結果**: クラッシュしない、妥当な結果を返す

#### 5.9 `distance calculation for point near corner`
- **目的**: 角付近の点での距離計算の正確性を確認
- **テストデータ**: 角の近くの点、正確な角の点
- **期待結果**: 距離は小さい値（< 100m）

#### 5.10 `provides reasonable bearing and nearest point`
- **目的**: 方位角と最寄り境界点の計算が妥当であることを確認
- **テストデータ**: エリアの北側の外部点
- **期待結果**: `nearestPoint` がエリアの北側境界上にあり、`bearingToBoundaryDeg` が約180度（南方向）

---

## 6. geo/geo_model_test.dart

GeoJSONのパースとポリゴン生成を検証するテストです。

### GeoPolygon テスト

#### 6.1 `creates polygon with valid points`
- **目的**: 有効な点からポリゴンを作成できることを確認
- **期待結果**: ポリゴンが自動的に閉じられる（4点入力 → 5点出力）、境界（bounds）が正しく計算される

#### 6.2 `closes polygon if not already closed`
- **目的**: 閉じていないポリゴンを自動的に閉じることを確認
- **期待結果**: 最初の点と最後の点が一致する

#### 6.3 `does not duplicate closing point if already closed`
- **目的**: 既に閉じているポリゴンに重複ポイントを追加しないことを確認
- **期待結果**: 5点のまま（重複なし）

#### 6.4 `calculates bounds correctly`
- **目的**: バウンディングボックスの計算が正確であることを確認
- **期待結果**: `minLat`, `maxLat`, `minLon`, `maxLon` が正しく計算される

### GeoModel テスト

#### 6.5 `creates empty model`
- **目的**: 空のモデルが正しく作成されることを確認
- **期待結果**: `hasGeometry = false`, `polygons` が空

#### 6.6 `creates model with polygons`
- **目的**: 複数のポリゴンを含むモデルを作成できることを確認
- **期待結果**: `polygons.length = 2`, `hasGeometry = true`

#### 6.7 `parses GeoJSON FeatureCollection with Polygon`
- **目的**: 標準的なGeoJSONのPolygonを正しくパースできることを確認
- **期待結果**: プロパティ（name, version）も正しく読み込まれる

#### 6.8 `parses GeoJSON FeatureCollection with MultiPolygon`
- **目的**: MultiPolygonを正しくパースし、複数のポリゴンに分解できることを確認
- **期待結果**: `polygons.length = 2`（MultiPolygonの各リングが個別のポリゴンになる）

#### 6.9 `handles empty FeatureCollection`
- **目的**: 空のFeatureCollectionを正しく処理できることを確認
- **期待結果**: `polygons` が空、`hasGeometry = false`

#### 6.10 `handles GeoJSON with unsupported geometry types`
- **目的**: サポートされていないジオメトリタイプ（Point等）をスキップできることを確認
- **期待結果**: Polygonのみがパースされる

#### 6.11 `handles polygons with insufficient points`
- **目的**: 点が不足しているポリゴン（3点未満）をスキップできることを確認
- **期待結果**: `polygons` が空

#### 6.12 `handles missing properties`
- **目的**: プロパティが欠損しているGeoJSONでもパースできることを確認
- **期待結果**: `name` と `version` が `null`

#### 6.13 `handles empty MultiPolygon`
- **目的**: 空のMultiPolygonを正しく処理できることを確認
- **期待結果**: `polygons` が空

---

## 7. app_controller_test.dart

AppController の動作とログ出力をカバーするテストセット。開発者モードの振る舞いを確認する。

### テストケース

#### 7.1 `loading new GeoJSON resets to init and stops alarm`
- **目的**: GeoJSON を再ロードした際に状態が `waitStart` に戻り、アラームが停止することを確認
- **手順**:
  1. アラームを開始（`notifyOuter()`）
  2. GeoJSONを再ロード（`reloadGeoJsonFromPicker()`）
- **期待結果**: 
  - `snapshot.status = LocationStateStatus.waitStart`
  - `stateMachine.current = LocationStateStatus.waitStart`
  - アラームが停止（`alarm.stopCount = 1`）

#### 7.2 `describeSnapshot hides navigation details before OUTER`
- **目的**: 開発者モード OFF では INNER/NEAR 中に距離・方角が伏せられることを検証
- **テストデータ**: `inner` 状態、距離42.5m、方位123度
- **期待結果**: ログ文字列に `dist=-` と `bearing=-` が含まれ、座標情報が含まれない

#### 7.3 `describeSnapshot reveals navigation details in developer mode`
- **目的**: 開発者モード ON で距離・方角・ターゲット座標が露出することを確認
- **テストデータ**: `inner` 状態、距離42.5m、方位123度、開発者モード有効
- **期待結果**: ログ文字列に距離（`42.50m`）、方角（`123deg`）、座標（`(1.00000,2.00000)`）が含まれる

---

## 8. platform/notifier_test.dart

通知とアラームの制御を検証するテストです。

### テストケース

#### 8.1 `outer -> inner -> outer toggles alarm playback`
- **目的**: OUTER → INNER → OUTER の遷移でアラームが適切に開始・停止・再開されることを確認
- **手順**:
  1. `notifyOuter()` を呼び出す → アラーム開始
  2. `notifyRecover()` を呼び出す → アラーム停止
  3. 再度 `notifyOuter()` を呼び出す → アラーム再開
- **期待結果**:
  - 1回目の `notifyOuter()`: 通知表示、アラーム開始、バイブレーション開始
  - `notifyRecover()`: 通知キャンセル、アラーム停止、バイブレーション停止
  - 2回目の `notifyOuter()`: アラーム再開、バイブレーション再開

---

## 9. io/logger_test.dart

イベントロガーの動作を検証するテストです。

### テストケース

#### 9.1 `exportJsonl returns empty array when no records`
- **目的**: レコードがない場合に空の配列を返すことを確認
- **期待結果**: `exportJsonl()` が空の配列 `[]` を返す

#### 9.2 `exportJsonl exports state change records`
- **目的**: 状態変化レコードが正しくエクスポートされることを確認
- **手順**: `logStateChange()` で状態変化を記録後、`exportJsonl()` を呼び出す
- **期待結果**: JSON配列に `type: 'state'`, `status: 'inner'` が含まれる

#### 9.3 `exportJsonl exports location fix records`
- **目的**: 位置情報レコードが正しくエクスポートされることを確認
- **手順**: `logLocationFix()` で位置情報を記録後、`exportJsonl()` を呼び出す
- **期待結果**: JSON配列に `type: 'location'`, `lat: 35.0`, `lon: 139.0` が含まれる

#### 9.4 `exportJsonl exports multiple records in order`
- **目的**: 複数のレコードが順序通りにエクスポートされることを確認
- **手順**: 2つの状態変化を順番に記録後、`exportJsonl()` を呼び出す
- **期待結果**: JSON配列に2つのレコードが順番に含まれ、最初が `inner`、次が `outer`

---

## 10. ui/home_page_test.dart

HomePage のUI動作を検証するテストです。

### テストケース

#### 10.1 `hides navigation details when not developer and not outer`
- **目的**: 開発者モードOFFかつOUTER状態でない場合、ナビゲーション情報が非表示になることを確認
- **テストデータ**: `inner` 状態、開発者モードOFF
- **期待結果**: 「境界までの距離」というテキストが見つからない

#### 10.2 `shows navigation details in developer mode`
- **目的**: 開発者モードONの場合、OUTER状態でなくてもナビゲーション情報が表示されることを確認
- **テストデータ**: `inner` 状態、開発者モードON、距離12.3m、方位45度
- **期待結果**: 「境界までの距離」と「方角」のテキストが見つかる

#### 10.3 `shows navigation details when state is OUTER`
- **目的**: OUTER状態の場合、開発者モードOFFでもナビゲーション情報が表示されることを確認
- **テストデータ**: `outer` 状態、開発者モードOFF、距離5m、方位180度
- **期待結果**: 「境界までの距離」と「方角」のテキストが見つかる

---

## 11. ui/settings_page_test.dart

SettingsPage のUI動作を検証するテストです。

### テストケース

#### 11.1 `shows progress indicator when config is null`
- **目的**: 設定が読み込まれていない場合、プログレスインジケーターが表示されることを確認
- **前提条件**: `controller.config` が `null`
- **期待結果**: `CircularProgressIndicator` が見つかる

#### 11.2 `renders form fields when config available`
- **目的**: 設定が読み込まれた場合、フォームフィールドが表示されることを確認
- **前提条件**: `controller.config` が設定されている
- **期待結果**: 「反応距離 (Inner buffer)」というテキストが見つかる

#### 11.3 `toggling developer mode switch calls controller`
- **目的**: 開発者モードスイッチを切り替えると、コントローラの `setDeveloperMode()` が呼ばれることを確認
- **手順**: 開発者モードスイッチをタップ
- **期待結果**: `controller.developerMode` が `true` になる

---

## 12. main_test.dart

アプリケーションのエントリーポイントとウィジェットツリーの基本動作を検証するテストです。

### テストケース

#### 12.1 `Argus app displays correctly`
- **目的**: アプリケーションが正しく表示されることを確認
- **期待結果**: アプリがクラッシュせずに表示される

---

## 13. widget_test.dart

ウィジェットの統合テストです。

### テストケース

#### 13.1 `Argus app displays correctly`
- **目的**: アプリケーション全体が正しく表示されることを確認
- **期待結果**: アプリがクラッシュせずに表示される

---

## テスト実行方法

すべてのテストを実行:
```bash
flutter test
```

特定のテストファイルを実行:
```bash
flutter test test/state_machine/state_machine_test.dart
```

特定のテストケースを実行:
```bash
flutter test test/state_machine/state_machine_test.dart --name "returns INNER"
```

---

## テストカバレッジ

現在のテストスイート（全88件）は以下の機能をカバーしています:

✅ **状態管理** (39件)
- すべての状態遷移（WAIT_GEOJSON, WAIT_START, GPS_BAD, INNER, NEAR, OUTER_PENDING, OUTER）
- ヒステリシス機構と条件チェック
- 状態復帰とリセット動作
- GPS精度による状態遷移
- OUTER状態時の特別処理（精度不良でも内側判定）

✅ **地理空間計算** (11件)
- 内外判定（レイキャスト法）
- 境界距離計算（ハバースイン距離）
- 複雑な形状（L字型、三角形）の処理
- エッジケース（境界上、頂点上）の処理
- 方位角と最寄り境界点の計算

✅ **GeoJSON処理** (13件)
- Polygon/MultiPolygonパース
- プロパティ（name, version）の読み込み
- エラーハンドリング（空のFeatureCollection、未対応ジオメトリタイプ、点不足など）
- ポリゴンの自動閉鎖機能
- バウンディングボックスの計算

✅ **ヒステリシス** (7件)
- サンプル数カウント
- 経過時間チェック
- 両方の条件を満たす必要があることの検証
- リセット機能
- エッジケース（ゼロ要件）の処理

✅ **アプリケーション制御** (3件)
- GeoJSON再ロード時の状態リセット
- アラーム停止
- 開発者モードの動作

✅ **通知とアラーム** (1件)
- OUTER/INNER遷移時のアラーム制御

✅ **ログ記録** (4件)
- 状態変化ログ
- 位置情報ログ
- JSONエクスポート

✅ **UI** (6件)
- HomePageのナビゲーション情報表示制御
- SettingsPageの設定表示と開発者モード切り替え

---

## テスト統計

- **総テスト数**: 88件
- **テストファイル数**: 13ファイル
- **成功率**: 100% (すべてのテストが通過)
- **主要カバレッジ**: 状態管理、地理空間計算、GeoJSON処理、ヒステリシス機構、UI、ログ記録

---

## 今後の拡張予定

以下の機能について追加のテストケースを検討中:

- [ ] `FileManager` のファイル操作テスト
- [ ] `LocationService` の権限要求テスト
- [ ] より複雑なGeoJSONファイルのパーステスト
- [ ] エッジケースの追加（極端な座標値、ポリゴンの自己交差など）
- [ ] パフォーマンステスト（大量のポリゴン、高頻度の評価）
- [ ] 統合テスト（エンドツーエンドのシナリオ）

---

## 参考資料

- [技術仕様書 (spec.md)](./spec.md)
- [Flutter Testing Guide](https://docs.flutter.dev/testing)
