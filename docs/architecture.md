# ARGUSの構成と処理フロー

確認日: 2026-09-29。現行仕様は[仕様書](spec.md)、利用手順は[スマホ](guides/phone.md)・[GARMIN](guides/garmin.md)を参照。
図の名前は実装のクラス・モジュールに対応する。QR codecはトップレベル関数群であり、`GeoJsonQrCodec`というクラスは存在しない。

## システム構成

```mermaid
flowchart LR
  File[GeoJSONファイル / QR] --> Phone
  subgraph Phone[スマホ ARGUS]
    Mode[UsageModeSelectionPage] --> Home[HomePage]
    Mode --> Transfer[GarminTransferPage]
    Home --> Controller[AppController]
    Controller --> State[StateMachine]
    Controller --> Platform[位置・コンパス・権限・通知]
    Controller --> IO[FileManager / EventLogger]
    Transfer --> Selection[GarminCourseSelection]
    Selection --> Encoder[GarminCourseEncoder]
    Transfer --> Client[GarminTransferClient]
  end
  Client --> Android[Android GarminBridge / Garmin Connect]
  Client --> iOS[iOS IOSGarminBridge / Companion SDK]
  Android <-->|Bluetooth / ACK| Receiver
  iOS <-->|Bluetooth / ACK| Receiver
  subgraph Watch[GARMIN Data Field]
    Receiver[ArgusReceiver] --> Protocol[ArgusProtocol]
    Receiver --> Storage[Application.Storage]
    Storage --> View[ArgusField]
    View --> Monitor[ArgusMonitor]
    Monitor --> Geometry[ArgusGeometry]
    View --> Alert[音・振動・表示]
    Lifecycle[ArgusCourseLifecycle] --> Storage
  end
```

GARMIN用のファイル・QR選択は`GarminCourseSelection`に保持する。スマホ監視中に別の範囲を選んでも、スマホの`GeoModel`と監視を差し替えない。異なる範囲の送信時は確認を表示する。

## 主要クラス

```mermaid
classDiagram
  class AppController {
    +StateSnapshot snapshot
    +GeoModel geoModel
    +bool isMonitoring
    +startMonitoring()
    +stopMonitoring()
    +reloadGeoJsonFromPicker()
    +reloadGeoJsonFromQr(String)
    +updateConfig(AppConfig)
  }
  class StateMachine {
    +evaluate(LocationFix) StateSnapshot
    +updateGeometry(GeoModel, AreaIndex)
    +updateConfig(AppConfig)
    +resetMonitoring()
  }
  class HysteresisCounter {
    +addSample(Duration) bool
    +isSatisfied(Duration) bool
    +reset()
  }
  class LocationService {
    <<interface>>
    +start(AppConfig)
    +stop()
  }
  class GeoModel {
    +List~GeoPolygon~ polygons
    +fromGeoJson(String)
    +bool hasGeometry
  }
  class GeoPolygon {
    +List~LatLng~ points
    +double minLat
    +double maxLat
    +double minLon
    +double maxLon
  }
  class GarminCourseSelection {
    +GeoModel model
    +String fileName
    +fromFile(XFile)
    +fromQrText(String)
    +hasSameGeometry(GeoModel) bool
  }
  class GarminCourseEncoder {
    +encode(GeoModel) GarminCoursePayload
  }
  AppController --> StateMachine
  AppController --> LocationService
  LocationService <|.. GeolocatorLocationService
  AppController --> PermissionCoordinator
  AppController --> Notifier
  AppController --> FileManager
  AppController --> EventLogger
  AppController --> CompassService
  StateMachine --> HysteresisCounter
  StateMachine --> AreaIndex
  StateMachine --> PointInPolygon
  StateMachine --> GeoModel
  StateMachine --> StateSnapshot
  GeoModel "1" *-- "0..*" GeoPolygon
  GeoPolygon "1" *-- "0..*" LatLng
  GarminCourseSelection --> GeoModel
  GarminCourseSelection --> GarminCourseEncoder : validates
  GarminTransferPage --> GarminCourseSelection
  GarminTransferPage --> GarminCourseEncoder
  GarminTransferPage --> GarminTransferClient
  GarminCourseEncoder --> GarminCoursePayload
```

`GeoModel.polygons`と`GeoPolygon.points`は変更不可のコピー。モデルと`AreaIndex`の構築後に呼び出し側が元のリストを変更しても、判定対象が食い違わない。

## スマホでの開始・停止

```mermaid
flowchart TD
  A[起動・スマホで利用] --> B[GeoJSON / QR読込]
  B --> C{位置サービスと常に許可}
  C -->|不足| D[開示・OS権限設定・状態更新]
  D --> C
  C -->|準備済み| E[タップで開始]
  E --> F{Androidのアラーム音量確認}
  F -->|50%未満| G[音量を上げて再確認]
  G --> F
  F -->|条件を満たす / iOS| H[位置ストリームを購読]
  H --> I[状態評価・UI・ログ更新]
  I --> J{範囲外確定}
  J -->|はい| K[通知・音・振動・方向案内]
  K -->|範囲内へ復帰| I
  I -->|長押しでレース終了| L[購読解除・警告停止・開始待ち]
  K -->|長押しでレース終了| L
```

Androidの音量取得失敗はログを残して開始を許可する既存仕様。通知権限は推奨だが開始の必須条件ではない。スマホの状態遷移・GPS不良時の例外は[仕様書の状態遷移](spec.md#431-状態遷移図)を参照。

## GARMINへの転送

```mermaid
sequenceDiagram
  actor User as 利用者
  participant UI as GarminTransferPage
  participant Encoder as GarminCourseEncoder
  participant Native as GarminTransferClient / native bridge
  participant Receiver as ArgusReceiver
  participant Storage as Application.Storage
  User->>UI: 範囲・接続済み時計を選択して送信
  UI->>Encoder: encode(model, fileName)
  Encoder-->>UI: AGW1 / checksum / 12時間の開始期限
  UI->>Native: sendCourse(device, payload)
  Native->>Receiver: requestId付きメッセージ
  Receiver->>Receiver: 形式・座標・チェックサム検証
  Receiver->>Storage: pending保存・読戻し
  Receiver->>Storage: course保存・読戻し
  Receiver-->>Native: 保存結果ACK
  Native->>Native: requestId・内容を照合
  Native-->>UI: 照合成功
  UI-->>User: 転送完了・スマホ通知
  Note over User,Storage: 時計でRunを開始してから監視。ACK待機上限60秒。
```

## 時計のデータ寿命

```mermaid
stateDiagram-v2
  [*] --> READY
  READY --> ARMED: 保存成功
  ARMED --> Monitoring: 12時間の期限内にRun開始
  ARMED --> EXPIRED: 開始期限切れ
  Monitoring --> Monitoring: Run一時停止・再開 / 期限通過
  Monitoring --> READY: Run終了・活動完了 / 範囲削除
  Monitoring --> READY: スマホ停止・削除ACK
  ARMED --> READY: スマホ停止・削除ACK
  EXPIRED --> ARMED: 範囲を再送信
  EXPIRED --> READY: Run終了 / スマホ停止
```

Run終了処理は`requestId`を照合するため、遅れて届いた古い終了イベントで新しい範囲を削除しない。未開始のまま期限を過ぎても自動削除タイマーは動かない。詳細は[転送仕様](garmin_data_format.md)。

## ディレクトリの役割

| 場所 | 責務 |
| --- | --- |
| `lib/ui` / `lib/theme` | 画面・配色・文字。選択/転送画面の共通色は`AppPalette` |
| `lib/geo` / `lib/state_machine` | 形状、境界計算、スマホの状態判定 |
| `lib/qr` / `lib/garmin` | QR変換、GARMIN転送候補・AGW1変換 |
| `lib/platform` / `android` / `ios` | OS・センサー・通知・GARMIN SDKとの接続 |
| `garmin/argus-data-field` | 時計の受信・保存・Run監視・削除 |
| `test` / `integration_test` / `scripts` | 回帰テスト、全E2E、CIと配信の補助処理 |

座標計算や警告の境界条件を変える場合は、まず該当する層の回帰テストで変更を明示し、スマホと時計の判定条件を混同しない。
