# MacBook iOS 開発環境構築

この文書は、Windows 上で実装した ARGUS の iOS 対応を MacBook に引き継ぎ、Simulator ビルド、実機デバッグ、署名、Archive まで進めるための初回セットアップ手順です。

毎回の実機確認とリリース前チェックは [ios_release.md](ios_release.md) を参照してください。

## 前提

- ARGUS の iOS 最低対応バージョンは iOS 15.0 です。
- iOS のネイティブビルド、Simulator、実機インストール、Archive は macOS と Xcode が必要です。
- Simulator の確認だけでなく、位置情報、通知、バックグラウンド動作、警告音は必ず iPhone 実機で確認します。
- 実機への開発ビルドには Apple Account が必要です。
- TestFlight または App Store Connect への提出には Apple Developer Program への加入が必要です。

用意するもの:

- macOS を更新できる MacBook
- テスト対象の iPhone と接続用ケーブル
- Apple Account
- App Store 提出まで行う場合は Apple Developer Program の Team
- GitHub 上の `gati-ios-version` ブランチへアクセスできる Git 設定

## 0. Windows 側でブランチを共有する

MacBook で取得する前に、Windows 側で iOS 対応の commit を作成し、ブランチを remote に push します。

```powershell
git switch gati-ios-version
git status --short
git push -u origin gati-ios-version
```

未 commit の変更は push されません。MacBook へ移る前に `git status --short` を確認してください。

## 1. Xcode をインストールする

1. Mac App Store から Xcode をインストールします。
2. macOS が古く最新 Xcode を導入できない場合は、[Apple Developer の Xcode サポート](https://developer.apple.com/support/xcode/) で対応 macOS と Xcode の組み合わせを確認します。
3. Terminal を開き、Xcode の command-line tools を有効化します。

```bash
sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
sudo xcodebuild -license
xcodebuild -downloadPlatform iOS
xcodebuild -version
xcode-select -p
```

`sudo xcodebuild -license` では内容を確認して同意します。`xcodebuild -downloadPlatform iOS` は iOS platform support と Simulator runtime を取得します。

Xcode を `/Applications/Xcode.app` 以外へ配置した場合は、`xcode-select` のパスを実際の配置先に合わせて変更してください。

## 2. Flutter stable をインストールする

[Flutter 公式のインストール手順](https://docs.flutter.dev/install) に従って macOS 用 Flutter SDK を導入し、`flutter` を `PATH` に追加します。このリポジトリの iOS CI も Flutter の `stable` channel を使います。

既に Flutter が入っている場合:

```bash
flutter channel stable
flutter upgrade
flutter --version
flutter doctor -v
```

新規インストール後も、同じく `flutter --version` と `flutter doctor -v` を実行してください。

Apple Silicon Mac でも、現行 Flutter では通常 Rosetta 2 は不要です。古い Flutter SDK や外部ツールが明示的に要求した場合だけ追加対応を検討します。

## 3. Homebrew と CocoaPods をインストールする

ARGUS はネイティブ iOS plugin を使うため、CocoaPods が必要です。Homebrew 経由の導入を推奨します。

Homebrew が未導入の場合は、[Homebrew 公式サイト](https://brew.sh/) のコマンドを実行します。

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

インストーラーの最後に表示される `brew shellenv` の設定手順も実行してください。その後、CocoaPods を導入します。

```bash
brew install cocoapods
pod --version
```

Homebrew を使わない場合は、[CocoaPods 公式手順](https://guides.cocoapods.org/using/getting-started.html) に従って RubyGems から導入できます。

```bash
sudo gem install cocoapods
pod --version
```

## 4. リポジトリを取得する

初めて取得する場合:

```bash
mkdir -p ~/Documents/GitHub
cd ~/Documents/GitHub
git clone https://github.com/nanigasi-san/Argus.git
cd Argus
git fetch origin
git switch --track origin/gati-ios-version
```

既に clone 済みの場合:

```bash
cd ~/Documents/GitHub/Argus
git fetch origin
git switch gati-ios-version
git pull --ff-only
```

確認:

```bash
git branch --show-current
git status --short
```

ブランチ名が `gati-ios-version` で、意図しないローカル変更がないことを確認します。

## 5. Flutter と CocoaPods の依存関係を取得する

リポジトリのルートで実行します。

```bash
flutter config --enable-ios
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter doctor -v
```

`flutter pub get` は必ず `pod install` より先に実行してください。`ios/Flutter/Generated.xcconfig` が生成されていない状態では `pod install` が失敗します。

初回の `pod install` で `ios/Podfile.lock` が生成されます。依存関係を固定するため、内容を確認して iOS 対応の commit に含めてください。`Pods/`、`.symlinks/`、`Generated.xcconfig` は生成物なので commit しません。

`flutter doctor -v` では、少なくとも Flutter、Xcode、CocoaPods に問題がないことを確認します。MacBook で Android 開発をしない場合、Android toolchain の警告は iOS ビルドの blocker ではありません。

## 6. Simulator ビルドを確認する

まず署名を必要としない Simulator ビルドを通します。

```bash
simulator_id="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for xs in d.values() for x in xs if x["name"].startswith("iPhone")))')"
xcrun simctl boot "$simulator_id" || true
open -a Simulator
xcrun simctl bootstatus "$simulator_id" -b
flutter devices
flutter analyze
flutter test
flutter build ios --simulator --debug
xcodebuild build-for-testing \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

`flutter analyze`、`flutter test`、`flutter build ios --simulator --debug`、`xcodebuild build-for-testing` がすべて成功することを確認します。この `xcodebuild` はネイティブ XCTest target のコンパイル確認です。GitHub Actions の iOS CI では、利用可能な Simulator を起動して `xcodebuild test` まで実行します。

アプリを Simulator で起動する場合:

```bash
flutter devices
flutter run -d <simulator-device-id>
flutter test integration_test/ui_smoke_test.dart -d <simulator-device-id>
```

位置情報、通知、バックグラウンド警告音の最終判定は Simulator だけでは完了しません。

## 7. Xcode workspace を開く

CocoaPods を使うため、Xcode project ではなく workspace を開きます。

```bash
open ios/Runner.xcworkspace
```

開くファイル:

- 正しい: `ios/Runner.xcworkspace`
- 使用しない: `ios/Runner.xcodeproj`

Xcode で `Runner` scheme を選び、Simulator を destination にして `Product > Build` を実行します。`Product > Test` で `RunnerTests` も実行します。

## 8. Apple Account と署名を設定する

1. Xcode の `Settings > Accounts` で Apple Account を追加します。
2. `ios/Runner.xcworkspace` を開きます。
3. 左ペインで `Runner` project、続いて `Runner` target を選びます。
4. `Signing & Capabilities` を開きます。
5. `Automatically manage signing` を有効にします。
6. `Team` に使用する Apple Developer Team を選びます。
7. Bundle Identifier が `com.argus.orienteering` になっていることを確認します。

表示内容も確認します。

- Deployment Target: iOS 15.0
- Background Modes: `Location updates`
- Background Modes: `Audio, AirPlay, and Picture in Picture`
- Time Sensitive Notifications entitlement

App Store Connect へ提出する場合、`com.argus.orienteering` を Apple Developer 側で一意の App ID として利用できる必要があります。既に別 Team が使用している場合は、App ID と Xcode project の Bundle Identifier を同時に変更します。

## 9. iPhone を接続する

1. iPhone を MacBook に接続します。
2. iPhone に表示される「このコンピュータを信頼しますか？」で信頼を許可します。
3. Xcode の `Window > Devices and Simulators` を開き、iPhone が表示されることを確認します。
4. 必要に応じて iPhone の `設定 > プライバシーとセキュリティ > デベロッパモード` を有効にします。
5. iPhone を再起動し、再起動後の確認ダイアログでも有効化します。

Terminal で確認:

```bash
flutter devices
```

Flutter ツール経由でデバッグ起動:

```bash
flutter run -d <iphone-device-id>
```

ホーム画面から手動起動して確認したい場合は、Release ビルドを入れます。

```bash
flutter run -d <iphone-device-id> --release
```

Debug ビルドは Flutter tooling または Xcode から起動する前提です。iOS 14 以降では、Debug ビルドをホーム画面から直接開くと白画面になり、実機ログに `Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode.` が出ることがあります。この場合はアプリ本体のUI不具合ではなく、起動方法の問題です。

初回起動時に開発者証明書の信頼が必要な場合は、iPhone の `設定 > 一般 > VPNとデバイス管理` から対象証明書を信頼します。

## 10. ARGUS 固有の実機確認

実機で次を確認します。詳細なチェックリストは [ios_release.md](ios_release.md) にあります。

1. 通知、位置情報の使用中許可、常時許可を設定できる。
2. QR スキャン時にカメラ許可が表示される。
3. QR 画像保存時に写真追加許可が表示される。
4. 監視中に画面を消しても位置情報更新が続く。
5. エリア外へ出ると Time Sensitive 通知と警告音が鳴る。
6. 警告音とバイブレーションが始まり、スヌーズまたはエリア復帰で両方停止する。
7. 電話、Siri、Bluetooth切替などの割り込み終了後、警告中なら警告音が復帰する。
8. 音量案内からARGUSアプリ設定画面を開ける。
9. サイレントモード、集中モード、画面ロック中の挙動を確認する。

`Critical Alerts` は Apple への個別申請が必要なため使用していません。ARGUS は通常配布可能な `Time Sensitive Notifications` を使います。

## 11. Archive と提出前ビルド

署名と実機確認が完了したら、リポジトリのルートで実行します。

```bash
flutter build ipa --release
```

または Xcode で実機向け destination を選び、`Product > Archive` を実行します。Archive 後は Xcode Organizer で署名、バージョン、Team、Bundle Identifier を確認してから App Store Connect へアップロードします。

App Store Connect の審査メモには、バックグラウンド位置情報とバックグラウンド音声の用途を記載してください。バックグラウンド音声はエリア外警告のループ再生中だけ使用します。

## トラブルシュート

### `pod: command not found`

Homebrew の `PATH` 設定後に Terminal を開き直し、次を確認します。

```bash
brew --version
brew install cocoapods
pod --version
```

### `Generated.xcconfig must exist`

リポジトリのルートへ戻り、`flutter pub get` を先に実行します。

```bash
flutter pub get
cd ios
pod install
cd ..
```

### Xcode で plugin が見つからない

`Runner.xcodeproj` ではなく `Runner.xcworkspace` を開いてください。CocoaPods の公式トラブルシュートでも workspace の利用が必要とされています。

### CocoaPods の解決結果がおかしい

`Podfile` を変更していない通常の更新では、まず `pod install` を使います。依存関係の再生成が必要な場合だけ、変更差分を確認しながら次を実行します。

```bash
cd ios
pod deintegrate
pod install
cd ..
```

### 署名エラー

Xcode の `Runner > Signing & Capabilities` で、`Team`、`Automatically manage signing`、Bundle Identifier を確認します。App Store Connect 提出用の Team と、ローカル実機確認だけの Personal Team を混同しないでください。

### iPhone が `flutter devices` に出ない

ケーブル接続、Mac の信頼、Xcode の `Window > Devices and Simulators`、iPhone のデベロッパモードを順に確認します。

### Xcode で iPhone が unpaired と表示される

Xcode の destination に `iPhone is not available because it is unpaired` と出る場合は、`Window > Devices and Simulators` を開き、iPhone 側に表示されるペアリング確認を許可します。iPhone 側の「このコンピュータを信頼」も必要です。

### 実機インストール後にホーム画面から開くと白画面になる

まず入っているビルド種別を切り分けます。Debug ビルドをホーム画面から直接開いた場合は白画面になることがあります。

```bash
flutter run -d <iphone-device-id>
```

上のコマンドはデバッグ用です。ホーム画面から普通に開く動作を確認する場合は、Release ビルドを入れます。

```bash
flutter run -d <iphone-device-id> --release
```

実機ログで確認する場合:

```bash
xcrun devicectl device process launch \
  --device <device-identifier> \
  --terminate-existing \
  --console \
  com.argus.orienteering
```

Debug ビルドで `Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode.` が出ていれば、Release ビルドを入れ直して確認します。

### 通知または位置情報の初回許可を再確認したい

iPhone から ARGUS を削除して再インストールするか、iPhone の設定から ARGUS の権限をリセットします。位置情報の「常に」は、使用中許可の後に設定します。

### `alarm.caf` が見つからない

次の tracked resource が存在することを確認します。

```bash
test -f ios/Runner/Resources/alarm.caf
git status --short
```

## commit しない生成物

次のファイルやディレクトリはローカル生成物です。

- `ios/Pods/`
- `ios/.symlinks/`
- `ios/Flutter/Generated.xcconfig`
- `ios/Flutter/ephemeral/`
- Xcode の `DerivedData/`
- Xcode の `xcuserdata/`

`ios/Podfile.lock` は依存関係を固定するため commit 対象です。

## 公式資料

- [Flutter: Set up iOS development](https://docs.flutter.dev/platform-integration/ios/setup)
- [Flutter: Build and release an iOS app](https://docs.flutter.dev/deployment/ios)
- [Apple Developer: Xcode support](https://developer.apple.com/support/xcode/)
- [Apple Developer: Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [CocoaPods: Getting Started](https://guides.cocoapods.org/using/getting-started.html)
- [Homebrew](https://brew.sh/)
- [Homebrew Formulae: cocoapods](https://formulae.brew.sh/formula/cocoapods)
