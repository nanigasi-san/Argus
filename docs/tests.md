# Argus テスト方針

本書は Argus のテスト戦略と、Android 周辺仕様を守るための確認観点をまとめる。手更新のテスト件数表は置かず、現在の実装を正として、どの層で何を守るかを優先する。

## 基本方針

- 現在の実装挙動を正とし、仕様変更時は実装・テスト・仕様書を同時に更新する。
- 本番挙動を変えずにテストしづらい箇所だけ seam を追加する。
- `test/support` の Fake / Harness / Fixture を共通語彙として使い、unit / widget / integration の重複セットアップを増やさない。
- Fake は呼び出し回数だけでなく、呼び出し順、最後の引数、返却シナリオを記録できるようにする。
- カバレッジは 100% を目標にする。GPS、カメラ、ファイルピッカー、通知プラグインなど実機または OS プラグイン境界でしか意味を持たない薄い wrapper は、契約テストで守った上で `coverage:ignore` を許容する。

## テスト層

### GARMIN Data Field

`Garmin Tests` CIでConnect IQ SDK 9.2.0の`fr55` Simulatorを起動し、
`garmin/argus-data-field/tests/MonitorTests.mc`の境界判定・監視状態・範囲の寿命・
保存とACKの全テストを実行する。通常ビルドも毎回実行し、テスト結果と検出件数が
一致しなければ失敗とする。[CIの実行環境と診断ログ](ci.md#garminのビルドとsimulatorテスト)を参照。
BLE通信・実GPS・実時計の表示や警告は実機確認として区別する。

### State / Geo / QR / IO

状態遷移、GeoJSON パース、点とポリゴン判定、QR codec、設定 JSON、ログ出力を純粋 Dart テストで守る。ここは実機依存を持たせず、例外系と境界値を厚く見る。

### Controller

`AppController` は UI と platform の間の判定を担当する。GeoJSON 読み込み、QR 読み込み、一時ファイル cleanup、監視開始/停止、ログ、通知、Android 音量チェックの分岐を Fake で検証する。

Android 音量チェックの重要契約:

- Android のみ監視開始前にアラーム音量を確認する。
- `percent >= 0.5` なら監視開始を許可する。
- `percent < 0.5` なら監視開始を止め、「５０％以上」の警告を UI に渡す。
- 音量取得に失敗した場合は warning ログを残し、監視開始はブロックしない。
- 非 Android では MethodChannel 音量取得を呼ばない。
- `openAlarmSoundSettings()` が失敗した場合は `false` を返し、ログで追えるようにする。

### Platform Contracts

プラグインそのものではなく、Argus が期待する contract をテストする。

- `MethodChannelAlarmClient`: method 名、payload、null / invalid response。
- `AlarmVolumeState.fromMap`: 必須値、型、範囲 validation。
- `NativeAlarmPlayer`: Android / iOS のネイティブ再生、volume clamp、copyWith、stop の contract。
- `Notifier`: channel ID / name / description / importance / playSound / vibration、OUTER 通知 ID `1001`、通知キャンセル、alarm / vibration stop の冪等性、通知・バイブなしの警告音preview。
- `PermissionCoordinator`: refresh は要求しない、foreground から background の順に要求する、iOSは拒否後に設定を自動表示しない、Androidは既存の app / location settings 導線を維持する、camera denied/manual settings flow を維持する。
- `GeolocatorLocationService`: Android foreground notification 文言、wake lock、ongoing、interval、iOS background update 設定を `LocationSettingsFactory` で検証する。
- `FileManager`: iOSのQR画像は写真ライブラリを開き、不要な画像メタデータの権限を要求しない。キャンセルは未選択として返す。Androidの画像選択と両OSのGeoJSON選択はファイルピッカーを維持する。写真ライブラリの実UIからの選択はiPhone実機で確認する。

### UI

Widget test はユーザーから見える文言と導線を守る。

- 低音量ダイアログは「５０％以上」を含む全文を表示する。
- `音設定を開く`、`再確認`、`キャンセル` の各操作を検証する。
- 音設定 open 失敗時は snackbar を表示する。
- 音量を上げた後の再確認で監視開始に進む。
- Home の permission card、developer details、file loader sheet、Settings、QR permission error を表示単位で守る。
- iOSの位置情報説明が「続ける」だけで閉じられないこと、明示的な設定導線、Settingsの警告音テスト開始・停止を守る。

### Integration Smoke

`integration_test/ui_smoke_test.dart` は実機または Android emulator / iOS Simulator 向けの smoke に限定する。`core_monitoring_e2e_test.dart` は監視・警告・復帰、`compass_navigation_test.dart` は退避ナビゲーションを扱う。unit / widget で守れる詳細仕様とは重複させない。

対象:

- Home permission card
- background location disclosure
- Settings
- QR camera permission error
- Home から Settings への navigation
- 利用端末の選択からスマホ／GARMIN画面への遷移
- GARMIN転送候補の読込から保存・照合ACK後の完了表示（SDKはFake）

Android / iOSの全E2Eは現在CIで実行する。対象は `integration_test/` および追加された場合の `e2e/` 配下の全 `*_test.dart` で、個別のsmokeだけでは全件検証にならない。

QR画像のケースはOSの画像解析を呼び出す。Androidでは復元・Garmin転送候補への反映を確認する。`mobile_scanner` はiOS Simulatorで画像解析を明示的に無効化しているため、Simulatorではエラー表示・選択済み範囲の保持・戻る操作を確認し、iPhoneでの画像解析は実機確認として区別する。iOS E2Eスクリプトは `ARGUS_IOS_SIMULATOR=true` をDartのビルド定義として渡す。これはSimulatorの識別用であり、`SIMULATOR_GPS` とは別の設定である。

## 実行コマンド

通常確認:

```sh
flutter analyze
flutter test
```

カバレッジ確認:

```sh
flutter test --coverage
python3 scripts/parse_coverage.py
```

Android 周辺を重点確認する場合:

```sh
flutter test \
  test/app_controller_test.dart \
  test/app_lifecycle_test.dart \
  test/platform \
  test/ui/home_page_test.dart \
  test/ui/background_location_disclosure_page_test.dart \
  test/ui/qr_scanner_page_test.dart
```

実機 / emulator / Simulatorでの個別smoke（全件検証の代替にはしない）:

```sh
flutter test integration_test/ui_smoke_test.dart -d <device-id>
```

macOS / LinuxのAndroid Emulatorで全E2E:

```sh
bash scripts/run_android_e2e.sh emulator-5554
```

macOSのiOS Simulatorで全E2E:

```sh
bash scripts/run_ios_e2e.sh <simulator-udid>
```

PowerShell helper:

```powershell
./scripts/run_android_ui_checks.ps1 -CaptureScreenshots
```

## 受け入れ条件

- `flutter analyze` が通る。
- `flutter test` が通る。
- `flutter test --coverage` と `scripts/parse_coverage.py` で実測値を記録し、未検証の分岐を確認する。100%は目標であり、現在のCIに割合による失敗ゲートはない。
- Android 仕様に関わる文言、閾値、MethodChannel、通知、権限導線がテストで保護されている。
- 実機依存 wrapper は実装詳細ではなく contract と ignore 理由で管理されている。
