# CIとリリースのワークフロー

ワークフロー名とチェック名は「対象 + 役割」で統一する。

| ワークフロー・チェック名 | 定義 | 検証内容 |
| --- | --- | --- |
| Flutter Tests | `.github/workflows/flutter_tests.yml` | 静的解析、unit/widgetテスト、カバレッジ |
| Android Build | `.github/workflows/android_build.yml` | 本番エントリーポイントのrelease AAB生成 |
| iOS Build | `.github/workflows/ios_build.yml` | iOS関連Dartテスト、Simulator向けビルド、native XCTest |
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
