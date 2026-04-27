# Android リリース運用

このプロジェクトでは GitHub Actions で Android AAB をビルドし、Google Play Console へ配信します。

## 配信フロー

### production 配信

- Workflow: `.github/workflows/android_release.yml`
- Trigger: `vX.Y.Z` 形式の tag push
- Track: `production`
- Status: `draft`
- Version:
  - `versionName`: tag名から先頭の `v` を除いた値
  - `versionCode`: `github.run_number + RELEASE_VERSION_CODE_OFFSET`

productionはtag pushでAABを作成し、Google Play Consoleにdraft releaseとしてアップロードします。ユーザーへ公開する前に、Play Consoleでリリース内容・versionCode・審査状態を確認してください。

```bash
git checkout main
git pull
git tag v1.2.3
git push origin v1.2.3
```

### closed test 配信

- Workflow: `.github/workflows/android_release.yml`
- Trigger: GitHub Actions の `Run workflow` から手動実行
- Track: `PLAY_CLOSED_TRACK` repository variable の値
  - 未設定の場合は `beta`
- Status: `completed`
- Version:
  - `versionName`: `pubspec.yaml` の `version: x.y.z+n` から `x.y.z` を使用
  - `versionCode`: `github.run_number + RELEASE_VERSION_CODE_OFFSET`

PR branch、feature branch、mainへのpushではGoogle Play配信は走りません。

## バージョン管理

workflowは `pubspec.yaml` を更新・commit・pushしません。リリース時のAndroid versionは `flutter build appbundle` の `--build-name` と `--build-number` で注入します。

Google Playは同じ `versionCode` の再アップロードを拒否します。`RELEASE_VERSION_CODE_OFFSET` は初期値 `1000` にしてあり、過去の `versionCode` より大きい番号から開始します。

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
- `RELEASE_VERSION_CODE_OFFSET`
  - workflow内の初期値は `1000`
  - 過去にGoogle Playへアップロード済みの最大 `versionCode` を上回るように必要なら調整します

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
- 同じrefで古いCD実行が残っている場合は `concurrency` により新しい実行が優先されます。
- production draftを公開する作業はPlay Consoleで手動実行します。
- release tagを作り直す場合は、既存tagを削除してから再作成してください。公開済みのversionCodeは再利用できません。
- GitHub公式ActionsはNode 24対応版を使います。
  - `actions/checkout@v6`
  - `actions/setup-java@v5`
  - `actions/upload-artifact@v7`

## トラブルシュート

- production配信が走らない
  - `v1.2.3` のような `vX.Y.Z` 形式のtagをpushしているか確認してください。
- closed test配信が走らない
  - Actions画面から `android_release` workflowを手動実行してください。
- 署名エラー
  - `ANDROID_KEYSTORE_BASE64`、alias、store password、key password の不一致を確認してください。
- Play uploadがスキップされる
  - `PLAY_SERVICE_ACCOUNT_JSON` がActions Secretに登録されているか確認してください。
- versionCodeエラー
  - Google Playに既に存在するversionCode以下でビルドされています。`RELEASE_VERSION_CODE_OFFSET` を上げてください。
- Play uploadが権限エラーになる
  - Play Consoleでservice accountに対象アプリのproduction/closed testing release権限があるか確認してください。
