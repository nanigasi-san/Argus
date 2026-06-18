# iOS 実機ビルド引き継ぎ

Windows 上で実装、Dart テスト、Android 回帰確認までは完了できます。iOS の最終確認、署名、Archive は macOS と Xcode が必要です。

MacBook の初回環境構築は [macbook_ios_setup.md](macbook_ios_setup.md) を先に実施してください。この文書は環境構築後の実機確認とリリース前チェックを扱います。

## 実装済みのiOS設定

- App version: `0.5.0+1005`
- Bundle ID: `com.argus.orienteering`
- Minimum deployment target: iOS 15.0
- Background Modes: `Location updates`, `Audio`
- 権限文言: 常時位置情報、使用中位置情報、カメラ、写真追加
- 通知: `Time Sensitive Notifications`
- 警告音: `ios/Runner/Resources/alarm.caf` をネイティブループ再生。iOS通知音は重複再生を避けるため無効
- ネイティブアラーム: `argus/alarm` MethodChannel と `AVAudioPlayer` のループ再生
- Privacy Manifest: `ios/Runner/PrivacyInfo.xcprivacy` を `Runner` target resources に含める
- 位置情報: `Geolocator.getPositionStream` に一本化し、`allowBackgroundLocationUpdates: true`
- QR: 標準 `agz1` で元ファイル名を保持し、既存 `gjz1` の読み取り互換を維持
- 更新確認: 起動時に日本のApp Storeを確認し、設定画面に現在のversion/build番号を表示

`Critical Alerts` はAppleへの個別申請が必要なので有効化していません。現在は通常配布可能な `Time Sensitive Notifications` を使います。

## 環境構築後に実行するコマンド

```bash
git switch gati-ios-version
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter analyze
flutter test
flutter build ios --simulator --debug
```

`pod install` 後は `ios/Runner.xcworkspace` をXcodeで開いてください。`Runner.xcodeproj` ではなく workspace を使います。

## Simulatorでの確認

利用するSimulatorを明示的に起動してからFlutterテストを実行します。XCTest終了後はSimulatorが停止している場合があるため、UI smokeの直前にもboot状態を確認します。

```bash
simulator_id="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for xs in d.values() for x in xs if x["name"].startswith("iPhone")))')"
xcrun simctl boot "$simulator_id" || true
open -a Simulator
xcrun simctl bootstatus "$simulator_id" -b
flutter devices
flutter test integration_test/ui_smoke_test.dart -d "$simulator_id"
```

## Xcodeで必要な署名設定

1. `Runner` target の `Signing & Capabilities` を開く。
2. Apple Developer Team を選ぶ。
3. Bundle ID `com.argus.orienteering` をApple Developer側に登録する。
4. `Automatically manage signing` を有効にする。
5. `Background Modes` に `Location updates` と `Audio, AirPlay, and Picture in Picture` が表示されることを確認する。
6. `Time Sensitive Notifications` capability が表示されることを確認する。

## iPhone実機での開発起動

実機がMacに接続され、Xcodeでpairing済みになっていることを確認します。接続状態は次で確認できます。

```bash
flutter devices
```

Flutterのホットリロードや実行ログを見ながら確認する場合:

```bash
flutter run -d <iphone-device-id>
```

ホーム画面から通常アプリとして開く挙動を確認する場合:

```bash
flutter run -d <iphone-device-id> --release
```

DebugビルドはFlutter toolingまたはXcodeから起動する前提です。Debugビルドを実機に入れたあとホーム画面から直接開くと、白画面になり、実機ログに `Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode.` が出ることがあります。この場合はReleaseビルドを入れ直して確認します。

インストール済みアプリとバージョンを確認する場合:

```bash
xcrun devicectl device info apps \
  --device <device-identifier> | grep com.argus.orienteering
```

起動ログを短時間確認する場合:

```bash
xcrun devicectl device process launch \
  --device <device-identifier> \
  --terminate-existing \
  --console \
  com.argus.orienteering
```

## 実機で必ず確認する項目

1. 初回起動後、通知、位置情報の使用中許可、常時許可を順に設定できる。
2. QRスキャン時にカメラ許可が表示される。
3. QR画像保存時に写真追加許可が表示される。
4. 監視中に画面を消しても位置情報更新が続く。
5. エリア外へ出るとTime Sensitive通知と警告音が鳴る。
6. 警告音とバイブレーションが始まり、スヌーズまたはエリア復帰で両方停止する。
7. 電話、Siri、Bluetooth切替などの音声割り込み終了後、警告中なら警告音が復帰する。
8. サイレントモード、集中モード、画面ロック中の通知挙動を確認する。
9. 音量案内からiOSのARGUSアプリ設定画面を開ける。
10. Xcodeの `Product > Test` で `RunnerTests` が通る。
11. 設定画面に `0.5.0 (1005)` が表示される。
12. `agz1` QRからGeoJSONと元ファイル名を復元でき、`gjz1` QRも読み込める。

## Archive前の確認

```bash
flutter build ipa --release
```

App Store Connectへ提出する際は、バックグラウンド位置情報とバックグラウンド音声の用途を審査メモに記載してください。音声モードはエリア外警告のループ再生中だけ使用します。

## App Store Connect 審査メモ案

```text
ARGUSは、利用者が読み込んだGeoJSONエリアを監視するアプリです。利用者が明示的に監視を開始した後、バックグラウンド位置情報を使用して、画面ロック中や他アプリ利用中でもエリア外への離脱を検知します。位置情報は端末内でのみエリア内外判定に使用し、開発者サーバーへ送信しません。

バックグラウンド音声は、エリア外を検知したときに警告音をループ再生するためだけに使用します。警告音はスヌーズ操作、または安全エリアへの復帰で停止します。
```

## リリース証跡チェックリスト

| 項目 | 証跡 |
| --- | --- |
| `flutter analyze` が通る | 実行日時と結果 |
| `flutter test` が通る | 実行日時と結果 |
| `flutter build ipa --release` が通る | Archive / IPA のビルド番号 |
| Xcode `Product > Test` が通る | 実行端末またはSimulator名 |
| 実機で常時位置情報を許可できる | 端末名 / iOS version |
| 画面ロック中に位置情報更新が続く | 確認メモ |
| エリア外でTime Sensitive通知と警告音が鳴る | 確認メモ |
| スヌーズまたはエリア復帰で警告音とバイブが止まる | 確認メモ |
| 音声割り込み終了後に警告音が復帰する | 割り込み方法 / 確認メモ |
| 音量案内からARGUSアプリ設定画面を開ける | 確認メモ |
| App Store Connect Privacy回答と審査メモを入力した | 入力者 / 日時 |

## 2026-06-18 統合確認結果

- Flutter 3.44.1 / Xcode 26.5 / CocoaPods 1.16.2
- `flutter analyze`: 成功
- `flutter test --coverage`: 303件成功、100.0% (2548/2548)
- iPhone 17 Pro Simulator (iOS 26.5): Debug build成功、RunnerTests 3件成功、UI smoke 5件成功
- KAITOのiPhone (iOS 26.0.1): Release署名・インストール・起動成功、`ARGUS 0.5.0 (1005)` と実行中processを確認
- 権限ダイアログ、実移動中のbackground位置更新、音・振動・スヌーズは端末操作を伴うため、リリース前に上記チェックリストで官能確認する
