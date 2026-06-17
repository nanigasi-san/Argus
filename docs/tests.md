# Argus テスト方針

本書は Argus のテスト戦略と、Android 周辺仕様を守るための確認観点をまとめる。手更新のテスト件数表は置かず、現在の実装を正として、どの層で何を守るかを優先する。

## 基本方針

- 現在の実装挙動を正とし、仕様変更時は実装・テスト・仕様書を同時に更新する。
- 本番挙動を変えずにテストしづらい箇所だけ seam を追加する。
- `test/support` の Fake / Harness / Fixture を共通語彙として使い、unit / widget / integration の重複セットアップを増やさない。
- Fake は呼び出し回数だけでなく、呼び出し順、最後の引数、返却シナリオを記録できるようにする。
- カバレッジは 100% を目標にする。GPS、カメラ、ファイルピッカー、通知プラグインなど実機または OS プラグイン境界でしか意味を持たない薄い wrapper は、契約テストで守った上で `coverage:ignore` を許容する。

## テスト層

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
- `Notifier`: channel ID / name / description / importance / playSound / vibration、OUTER 通知 ID `1001`、通知キャンセル、alarm / vibration stop の冪等性。
- `PermissionCoordinator`: refresh は要求しない、foreground から background の順に要求する、拒否時は app / location settings 導線に進む、camera denied/manual settings flow を維持する。
- `GeolocatorLocationService`: Android foreground notification 文言、wake lock、ongoing、interval、iOS background update 設定を `LocationSettingsFactory` で検証する。

### UI

Widget test はユーザーから見える文言と導線を守る。

- 低音量ダイアログは「５０％以上」を含む全文を表示する。
- `音設定を開く`、`再確認`、`キャンセル` の各操作を検証する。
- 音設定 open 失敗時は snackbar を表示する。
- 音量を上げた後の再確認で監視開始に進む。
- Home の permission card、developer details、file loader sheet、Settings、QR permission error を表示単位で守る。

### Integration Smoke

`integration_test/ui_smoke_test.dart` は実機または Android emulator / iOS Simulator 向けの smoke に限定する。unit / widget で守れる詳細仕様とは重複させない。

対象:

- Home permission card
- background location disclosure
- Settings
- QR camera permission error
- Home から Settings への navigation

Android emulator を CI に追加する作業は現在の範囲外。ローカルまたは実機で必要時に実行する。

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

実機 / emulator / Simulator smoke:

```sh
flutter test integration_test/ui_smoke_test.dart -d <device-id>
```

PowerShell helper:

```powershell
./scripts/run_android_ui_checks.ps1 -CaptureScreenshots
```

## 受け入れ条件

- `flutter analyze` が通る。
- `flutter test` が通る。
- `flutter test --coverage` と `scripts/parse_coverage.py` で 100% を維持する。
- Android 仕様に関わる文言、閾値、MethodChannel、通知、権限導線がテストで保護されている。
- 実機依存 wrapper は実装詳細ではなく contract と ignore 理由で管理されている。
