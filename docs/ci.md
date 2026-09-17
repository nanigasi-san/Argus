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

名前を変更したチェックを必須にする場合は、ブランチ保護の設定でも対応する
チェック名を指定する。既存の保護設定はワークフロー変更だけでは更新されない。
