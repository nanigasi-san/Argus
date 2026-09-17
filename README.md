# ARGUS

https://argus-lp.vercel.app/


[![Flutter Tests](https://github.com/nanigasi-san/Argus/actions/workflows/flutter_tests.yml/badge.svg)](https://github.com/nanigasi-san/Argus/actions/workflows/flutter_tests.yml)
[![codecov](https://codecov.io/gh/nanigasi-san/Argus/branch/main/graph/badge.svg)](https://codecov.io/gh/nanigasi-san/Argus)

テスト・ビルド・E2Eのワークフロー構成は [docs/ci.md](docs/ci.md) を参照してください。

![App icon](./icon.png)

## CIとマージ条件

mainへの変更はPR経由でマージします。以下の5つのGitHub Actionsチェックが
すべて成功していることがマージ条件です。

- `Flutter Tests`
- `Android Build` / `iOS Build`
- `Android E2E` / `iOS E2E`

CIが未完了・失敗・キャンセルの場合はマージできません。
この条件は管理者にも適用されます。
設定は [protect-mainルールセット](https://github.com/nanigasi-san/Argus/rules/9448222)
で管理しています。各チェックの内容と実行条件は [docs/ci.md](docs/ci.md) を参照してください。

## リリース運用

Android AAB のproduction / closed test配信とバージョン更新オプションは [docs/release.md](docs/release.md) を参照してください。

iOS 開発用 MacBook の初回セットアップは [docs/macbook_ios_setup.md](docs/macbook_ios_setup.md)、署名、実機テスト、Archive 手順は [docs/ios_release.md](docs/ios_release.md) を参照してください。
