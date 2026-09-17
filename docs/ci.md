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
Android Buildと両E2Eは手動実行にも対応する。
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

ビルド・E2Eには `concurrency` と `cancel-in-progress: true` を設定し、
同じPRブランチの新しい実行が始まると古い実行をキャンセルする。
これは古い実行の重複を抑える設定であり、マージを制限する必須チェック設定とは
別の仕組みである。`Flutter Tests` には現在このキャンセル設定を付けていない。

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

`scripts/run_ios_e2e.sh` は `flutter drive --verbose` ログと結果を
`build/e2e/ios/` に保存する。
30秒ごとに経過時間を出力し、全件実行の制限は900秒とする。
ローカルで変更する場合は `E2E_IOS_SUITE_TIMEOUT_SECONDS` を指定する。
時間超過は終了コード124の失敗として記録し、子プロセスも終了する。
失敗を成功扱いせず、全件の登録と実行を維持する。

Simulatorの起動待ちは420秒に制限し、起動後の画面取得で応答を確認する。
両iOSワークフローはSimulatorアプリも明示的に起動する。
終了時のアプリ・インストールサービスのログ取得と
スクリーンショット取得にも時間制限を設け、診断処理自体の停止を防ぐ。
結果・詳細ログ・スクリーンショットは `ios-e2e-diagnostics` Artifactに
14日間保存する。コマンドの時間制限・キャンセル処理の回帰テストは
`Flutter Tests` で実行する。

## キャッシュと重複削減

Flutter SDK・pubキャッシュを全検証ワークフローで有効にする。
Android Build・Android E2Eは `gradle/actions/setup-gradle` により
Gradle依存と再利用可能なビルド状態をキャッシュする。
iOS Buildで重複実行していた解析・DartテストはFlutter Testsの全件実行に
集約し、Simulator向け通常アプリビルドとnative XCTestは維持する。
5つの必須チェック、Android release AAB、全E2Eシナリオは削減しない。
PRとmain pushの実行条件も変更しない。
