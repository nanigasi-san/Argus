# iOS 実機ビルド引き継ぎ

Windows 上で実装、Dart テスト、Android 回帰確認までは完了できます。iOS の最終確認、署名、Archive は macOS と Xcode が必要です。

MacBook の初回環境構築は [macbook_ios_setup.md](macbook_ios_setup.md) を先に実施してください。この文書は環境構築後の実機確認とリリース前チェックを扱います。

## 実装済みのiOS設定

- App version: `0.6.0+1008`
- Bundle ID: `com.argus.orienteering`
- Minimum deployment target: iOS 15.0
- Background Modes: `Location updates`, `Audio`
- 権限文言: 常時位置情報、使用中位置情報、カメラ、写真追加
- 通知: `Time Sensitive Notifications`
- 警告音: `ios/Runner/Resources/alarm.caf` をネイティブループ再生。iOS通知音は重複再生を避けるため無効
- ネイティブアラーム: `argus/alarm` MethodChannel と `AVAudioPlayer` のループ再生
- 警告音テスト: 設定画面から通知・バイブなしで警告音を開始・停止し、ホーム画面でも継続を確認可能
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

1. iOSの位置情報説明画面には「続ける」だけが表示され、戻る・スワイプ・別操作で閉じられない。
2. 「続ける」の後に位置情報の使用中許可、常時許可を順に設定できる。
3. 位置情報を拒否しても設定アプリへ自動遷移せず、権限カードの「アプリ設定を開く」を明示的に押した場合だけ遷移する。
4. QRスキャン時にカメラ許可が表示される。
5. QR画像保存時に写真追加許可が表示される。
6. 監視中に画面を消しても位置情報更新が続く。
7. エリア外へ出るとTime Sensitive通知と警告音が鳴る。
8. 警告音とバイブレーションが始まり、スヌーズまたはエリア復帰で両方停止する。
9. 設定画面の「警告音をテスト」で音声だけが鳴り、「テストを停止」で止まる。再生中にホーム画面へ移動しても継続する。
10. 電話、Siri、Bluetooth切替などの音声割り込み終了後、警告中なら警告音が復帰する。
11. サイレントモード、集中モード、画面ロック中の通知挙動を確認する。
12. 音量案内からiOSのARGUSアプリ設定画面を開ける。
13. Xcodeの `Product > Test` で `RunnerTests` が通る。
14. 設定画面に `0.6.0 (1008)` が表示される。
15. `agz1` QRからGeoJSONと元ファイル名を復元でき、`gjz1` QRも読み込める。

## Archive前の確認

```bash
flutter build ipa --release
```

App Store Connectへ提出する際は、バックグラウンド位置情報とバックグラウンド音声の用途を審査メモに記載してください。音声モードはエリア外警告のループ再生中だけ使用します。

## App Store Connect 審査メモ案

```text
ARGUSは、利用者が読み込んだGeoJSONエリアを監視するアプリです。利用者が明示的に監視を開始した後、バックグラウンド位置情報を使用して、画面ロック中や他アプリ利用中でもエリア外への離脱を検知します。位置情報は端末内でのみエリア内外判定に使用し、開発者サーバーへ送信しません。

バックグラウンド音声は、エリア外を検知したときに警告音をループ再生するためだけに使用します。警告音はスヌーズ操作、または安全エリアへの復帰で停止します。

審査時は、アプリ右上メニューの「設定」から「警告音をテスト」を押すと、通知やバイブレーションを発生させずに同じ警告音を確認できます。再生中にiPhoneのホーム画面へ移動しても警告音は継続し、アプリへ戻って「テストを停止」を押すと停止します。
```

## App Review用の実機録画

1. アプリを削除して再インストールし、位置情報権限を未決定へ戻す。
2. 監視開始操作からiOS専用の説明画面を表示し、「続ける」以外の操作がないことを映す。
3. システム許可画面で拒否し、設定アプリへ自動遷移しないことを映す。
4. 権限カードの「アプリ設定を開く」を押した場合だけ設定アプリが開くことを映す。
5. 常時位置情報を許可し、実機周辺の小さなGeoJSONを読み込んで監視を開始する。
6. ホーム画面へ移動した状態でエリア外へ出て、位置情報更新と警告音が継続することを映す。
7. 別録画で「設定」→「警告音をテスト」→iPhoneのホーム画面→ARGUSへ復帰→「テストを停止」の順に操作する。
8. 2本の録画をApp Review InformationのNotesへ添付し、上記の審査メモを記載する。

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
| 設定画面の警告音テストがホーム画面でも継続する | 録画ファイル名 |
| 権限拒否後に設定アプリへ自動遷移しない | 録画ファイル名 |
| 音量案内からARGUSアプリ設定画面を開ける | 確認メモ |
| App Store Connect Privacy回答と審査メモを入力した | 入力者 / 日時 |

## 2026-06-18 統合確認結果

- Flutter 3.44.1 / Xcode 26.5 / CocoaPods 1.16.2
- `flutter analyze`: 成功
- `flutter test --coverage`: 303件成功、100.0% (2548/2548)
- iPhone 17 Pro Simulator (iOS 26.5): Debug build成功、RunnerTests 3件成功、UI smoke 5件成功
- KAITOのiPhone (iOS 26.5): Release署名・インストール・起動成功。初回確認時は `ARGUS 0.5.0 (1005)`、再提出用の現行buildは `1007`
- 画面ロック中のエリア外検知、Time Sensitive通知、通知音を実機確認済み
- バイブ停止、エリア復帰、サイレント/集中モード、電話/Siri/Bluetooth割り込み復帰は端末操作を伴うため、merge前に上記チェックリストで官能確認する

## 2026-07-16 App Review指摘対応の確認結果

- Flutter unit/widget tests: 336件成功
- `flutter test --coverage`: 100.0% (2703/2703)
- `flutter analyze`: 成功、指摘0件
- ARGUS App Store iPhone 11 Pro Max Simulator (iOS 26.5): Debug build成功
- `RunnerTests`: 4件成功（Background Modes、位置情報用途文言、警告音bundle、Scene lifecycle）
- iOS UI smoke: 5フロー成功（権限カード、iOS説明画面、警告音テスト付き設定画面、QR権限エラー、設定画面遷移）
- App Store用スクリーンショット3枚を同Simulatorから `1242 x 2688` で再取得
- Release Archive / App Store IPAの作成に成功（`0.5.0 (1007)`、App Store provisioning、`get-task-allow=false`）
- 配布IPAのentitlementsにTime Sensitive Notifications、Info.plistに `audio` / `location` と更新済み位置情報用途文言が含まれることを確認
- Flutter標準のLaunch ImageプレースホルダーをARGUSロゴへ置換し、App Settings Validationの警告を解消
- 実機での拒否動作、画面ロック中の監視、バックグラウンド警告音の録画は提出前の手動確認として残す
