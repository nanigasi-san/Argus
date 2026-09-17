# CIとリリースのワークフロー

ワークフロー名とチェック名は「対象 + 役割」で統一する。

| ワークフロー・チェック名 | 定義 | 検証内容 |
| --- | --- | --- |
| Flutter Tests | `.github/workflows/flutter_tests.yml` | 静的解析、unit/widgetテスト、カバレッジ |
| Android Build | `.github/workflows/android_build.yml` | 本番エントリーポイントのrelease AAB生成 |
| iOS Build | `.github/workflows/ios_build.yml` | Simulator向けビルド、native XCTest（Dartテスト・解析はFlutter Testsに集約） |
| Android E2E | `.github/workflows/android_e2e.yml` | Android Emulator上の全共通E2E |
| iOS E2E | `.github/workflows/ios_e2e.yml` | iOS Simulator上の全共通E2E |
| Android Release | `.github/workflows/android_release.yml` | ストア向けAABの生成、設定済みの場合のGoogle Playへのアップロード |

テスト・ビルド・E2EはPRとmain pushで実行する。
Android Build・iOS Buildと両E2Eは手動実行にも対応する。
Android Releaseはバージョンタグのpushまたは手動実行で起動する。

Android E2Eはテストを入口にしたdebug APKをビルドする。
Android Buildは `flutter build appbundle --release` により通常のアプリ入口、
release向けDartコンパイル、ネイティブコードとリソース、AABの生成を検証する。
署名用Secretは使用せず、既存Gradle設定のdebug署名フォールバックを使う。
このArtifactはビルド確認用であり、ストア配布にはAndroid Releaseを使用する。

## mainへのマージ条件

GitHubの [protect-mainルールセット](https://github.com/nanigasi-san/Argus/rules/9448222)
により、mainへの変更はPR経由とし、次の5チェックを必須にしている。

- `Flutter Tests`
- `Android Build`
- `iOS Build`
- `Android E2E`
- `iOS E2E`

チェックの提供元はGitHub Actionsに固定している。
最新のPR更新に対して必須チェックが満たされるまでマージできず、
未完了・失敗・キャンセルの場合は完了または再実行を待つ。
管理者を含めバイパス対象は設定していない。
`Android Release` とCodecovは必須チェックには含めない。
mainの最新状態への追従を要求するstrict設定は有効にしていない。

必須チェックはリポジトリの設定で管理しており、YAML変更だけでは更新されない。
チェック名を変更する場合は、このルールセットの必須チェック名とドキュメントも
合わせて更新する。

## 実行タイミングとキャンセル

PR作成・再オープン・PRブランチへの追加pushで検証を実行する。
PRがない作業ブランチへのpushでは実行せず、mainへのpushでは再実行する。
現在はDraft PRも通常PRと同じ検証対象であり、Readyにした時だけ実行する
最適化は導入していない。

全6ワークフローに `concurrency` と `cancel-in-progress: true` を設定し、
同じワークフロー・同じブランチの新しい実行が始まると古い実行をキャンセルする。
`Android Release` はブランチ・タグを含む完全なrefでグループを分け、
同じrefの再実行だけをキャンセルする。
これは古い実行の重複を抑える設定であり、マージを制限する必須チェック設定とは
別の仕組みである。

## iOS E2Eの診断ログと時間制限

両E2Eスクリプトは `integration_test/` と `e2e/` の `*_test.dart` を
再帰検出し、全ファイルのmainをgroupとして登録する入口を
`integration_test/ci_all_suites.dart` に自動生成する（生成物はGit対象外）。追加ファイルも自動で対象となる。
ファイルごとのビルド・インストール・起動を繰り返さず、一度のアプリ起動で
全シナリオを実行する。検出一覧は `suites.txt`、全体結果は `results.txt`、
個別シナリオの成否は `all_suites.log` に記録する。
実行件数を `test-results.json` に記録し、検出した各ファイルの完了件数が
0または報告が欠けている場合はdriverを失敗させる。完了通知は最上位で
登録し、最初のgroupだけで成功が返ることを防ぐ。
WindowsのPowerShellスクリプトは従来のファイル別全件実行を維持する。

`scripts/run_ios_e2e.sh` は `scripts/run_ios_e2e.py` を呼び出し、全件用の
Simulatorアプリを一度ビルド・インストールする。Dartを停止した状態で起動し、
起動開始時刻以降の保存ログを `log show --style json` で読み直す。
今回起動したPIDのVM Service URLを取得し、`flutter drive --use-existing-app`
で接続する。起動とライブのログ監視の競合でURL通知を取り逃がす問題を避ける。
以前のPIDや起動開始前のURLを使用せず、URL取得は120秒、各ログ取得は最大15秒に
制限する。アプリ起動・テストを再試行して失敗を隠す処理は行わない。
ビルド・起動・`flutter drive --verbose` のログと結果を `build/e2e/ios/` に保存する。
30秒ごとに経過時間を出力し、全件実行の制限は900秒とする。
ローカルで変更する場合は `E2E_IOS_SUITE_TIMEOUT_SECONDS` を指定する。
時間超過は終了コード124の失敗として記録し、子プロセスも終了する。
失敗を成功扱いせず、全件の登録と実行を維持する。

CIでは `E2E_IOS_BOOT_SIMULATOR=true` により、全件用アプリのビルド成功後に
Simulatorを起動する。`simctl bootstatus -b` の成功を確認してから
インストール、アプリ起動、保存ログのURL取得、driver接続へ順番に進む。
各処理の終了・成功を必ず待ち、ビルドとSimulator起動を重ねない。
ビルド出力の形式には依存しない。ローカルで起動済み端末を
指定する従来のコマンドも維持する。
両iOSワークフローでは最初に `sudo xcodebuild -runFirstLaunch` を実行し、
`xcodebuild -checkFirstLaunchStatus` の成功後にFlutter設定と端末操作へ進む。
これは[Appleが案内するXcode必須コンポーネントの準備](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)である。
Simulatorの初期端末取得には300秒、その後の状態取得には120秒、
起動待ちには420秒の余裕を持たせる。
端末の起動完了を待ってからGUIを開き、初回GUI起動には最大120秒を確保する。
起動後の診断画像を最大30秒で取得する。
画像取得は診断用途であり、取得失敗だけでテストを中断しない。
起動時間は `simulator-boot.json`、ビルドと起動待ちの時間は
`build-timing.json` に記録する。
両iOSワークフローはSimulatorアプリも明示的に起動する。
終了時のアプリ・インストールサービスのログ取得と
スクリーンショット取得にも時間制限を設け、診断処理自体の停止を防ぐ。
起動情報は `launch.json`、接続URLは `vm-service-uri.txt`、取得した保存ログは
`vm-service-log.json` に保存する。終了時の診断取得後にアプリを停止する。
結果・詳細ログ・スクリーンショットは `ios-e2e-diagnostics` Artifactに
14日間保存する。コマンドの時間制限・キャンセル処理の回帰テストは
`Flutter Tests` で実行する。保存済み通知の回収、古い起動情報の除外、
URL取得の時間制限、接続不能時の中断、driver失敗の保持もPythonテストで検証する。

## キャッシュと重複削減

Flutter SDK・pubキャッシュを全検証ワークフローで有効にする。
Android Build・Android E2Eは `gradle/actions/setup-gradle` により
Gradle依存と再利用可能なビルド状態をキャッシュする。
iOS Buildで重複実行していた解析・DartテストはFlutter Testsの全件実行に
集約する。通常入口のSimulatorアプリとnative XCTestは
`scripts/run_ios_build.py` で検証する。
`flutter build ios --simulator --debug --config-only --target=lib/main.dart` で
Flutter設定・プラグイン・CocoaPodsを準備し、`xcodebuild build-for-testing`
でアプリと全テストを一つのDerivedDataに一度だけビルドする。
ビルドはgeneric Simulator向けとし、通常アプリのSimulator用アーキテクチャを
特定の端末のものだけに絞らない。
Flutterの設定準備、アプリと全nativeテストのビルド、Simulator起動・起動確認、
全nativeテスト実行、結果検証を順番に行う。前の処理の成功前に次へ進まない。
IDE向けの索引生成は `COMPILER_INDEX_STORE_ENABLE=NO` で省き、
Flutterの通常ビルドと同じ設定にする。コンパイル・解析警告・テスト実行は維持する。
ビルドと起動確認の成功後に同じDerivedDataの成果物を
`xcodebuild test-without-building` で実行する。
短いnative XCTestのためだけに別のSimulatorを複製・起動する待ち時間を避けるため、
テストの並列実行を無効にする。テストの除外や自動再試行は行わない。
結果Bundleを `xcresulttool` で読み、0件・失敗・スキップ・完了件数不足を失敗とする。
全体は子プロセス終了付きwatchdogで1080秒に制限する（WFの上限は従来の20分）。
起動時間・ビルド時間・テスト時間・全件結果・ログ・`.xcresult` は
`ios-native-test-results` Artifactに14日間保存する。
前ステップの成功待ち、ビルド・起動失敗時の中断、通常入口と全テストの単一ビルド、
不完全な結果の検出もPython回帰テストで検証する。
5つの必須チェック、Android release AAB、全E2Eシナリオは削減しない。
PRとmain pushの実行条件も変更しない。
