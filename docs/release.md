# Android リリース運用

このプロジェクトでは GitHub Actions で Android AAB をビルドし、Google Play Console へ配信します。

## 配信フロー

### main: production 配信

- Workflow: `.github/workflows/production_release_android.yml`
- Trigger: `main` への `push`
- Track: `production`
- Version: `pubspec.yaml` の `version: x.y.z+n` を更新してからAABを作成
  - デフォルトは `minor`
  - bot commit には `[skip release]` が付き、再実行ループを防ぎます

mainでのバージョン更新オプションは、pushするcommit messageに次のどれかを含めて指定します。

```text
[version:major]  # 0.2.3+6 -> 1.0.0+7
[version:minor]  # 0.2.3+6 -> 0.3.0+7
[version:patch]  # 0.2.3+6 -> 0.2.4+7
```

指定しない場合は `[version:minor]` と同じ扱いです。

### main以外: closed test 配信

- Workflow: `.github/workflows/closed_test_release_android.yml`
- Trigger: `main` 以外への `push`、または手動実行
- Track: `PLAY_CLOSED_TRACK` repository variable の値
  - 未設定の場合は `beta`
- Version: `versionCode` だけ更新
  - 例: `0.2.3+6 -> 0.2.3+7`
  - Google Playは同じ `versionCode` の再アップロードを拒否するため、closed testでも `+n` は毎回上げます

## バージョン更新コマンド

ローカルで確認・手動更新したい場合は `scripts/bump_version.sh` を使います。

```bash
scripts/bump_version.sh pubspec.yaml major
scripts/bump_version.sh pubspec.yaml minor
scripts/bump_version.sh pubspec.yaml patch
scripts/bump_version.sh pubspec.yaml code
```

各オプションの意味:

| option | 更新例 | 用途 |
| --- | --- | --- |
| `major` | `0.2.3+6 -> 1.0.0+7` | 大きな互換性変更、正式版の区切り |
| `minor` | `0.2.3+6 -> 0.3.0+7` | 通常のproduction更新。mainのデフォルト |
| `patch` | `0.2.3+6 -> 0.2.4+7` | 小さな修正をproductionへ出す場合 |
| `code` | `0.2.3+6 -> 0.2.3+7` | closed test用。表示バージョンは変えずGoogle Play用のビルド番号だけ上げる |

## GitHub Secrets / Variables

Repository Settings > Secrets and variables > Actions に登録します。

Secrets:

- `ANDROID_KEYSTORE_BASE64`
  - upload keystore `.jks` をbase64化した文字列
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`
- `PLAY_SERVICE_ACCOUNT_JSON`
  - Google Play Developer APIを使えるservice account JSON

Variables:

- `PLAY_CLOSED_TRACK`
  - closed testing track名
  - 未設定時は `beta`

PowerShellでkeystore系Secretを登録する例:

```powershell
$repo = "nanigasi-san/Argus"
$props = @{}
Get-Content "android/key.properties" | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') { $props[$matches[1]] = $matches[2] }
}

$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks"))

gh secret set ANDROID_KEYSTORE_BASE64 --repo $repo --body $base64
gh secret set ANDROID_KEY_ALIAS --repo $repo --body $props["keyAlias"]
gh secret set ANDROID_STORE_PASSWORD --repo $repo --body $props["storePassword"]
gh secret set ANDROID_KEY_PASSWORD --repo $repo --body $props["keyPassword"]
```

## 運用メモ

- `android/key.properties` と `.jks` はリポジトリに含めません。
- `PLAY_SERVICE_ACCOUNT_JSON` が未設定の場合、AAB artifactは作られますがGoogle Play upload stepはスキップされます。
- 同じbranchで古いCD実行が残っている場合は `concurrency` により新しい実行が優先されます。
- GitHub公式ActionsはNode 24対応版を使います。
  - `actions/checkout@v6`
  - `actions/setup-java@v5`
  - `actions/upload-artifact@v7`

## トラブルシュート

- non-fast-forwardでpushに失敗する
  - workflowはcheckout後にremote branch先端へ同期します。古いworkflow定義で走った実行はキャンセルして再実行してください。
- 署名エラー
  - `ANDROID_KEYSTORE_BASE64`、alias、store password、key password の不一致を確認してください。
- Play uploadがスキップされる
  - `PLAY_SERVICE_ACCOUNT_JSON` がActions Secretに登録されているか確認してください。
- Play uploadが権限エラーになる
  - Play Consoleでservice accountに対象アプリのproduction/closed testing release権限があるか確認してください。
