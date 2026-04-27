# Android リリース自動化運用

このプロジェクトでは、`main` への push を契機に GitHub Actions で Android AAB のビルドと Play Console への配信を行います。

## ワークフロー

- ファイル: `.github/workflows/release-android.yml`
- トリガー: `main` ブランチへの push
- 実行内容:
  1. 署名鍵情報を Secrets から復元
  2. `pubspec.yaml` の `versionCode`（`x.y.z+n` の `n`）を +1
  3. 変更を bot で main に commit/push（`[skip release]` 付き）
  4. AAB をビルド
  5. Play Console の `internal` track にアップロード

## 必須 Secrets

以下の Secrets を GitHub Repository Settings > Secrets and variables > Actions に登録してください。

- `ANDROID_KEYSTORE_BASE64`
  - `release-keystore.jks` を base64 化した文字列
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`
- `PLAY_SERVICE_ACCOUNT_JSON`
  - Play Developer API 権限を持つサービスアカウントの JSON

### base64 作成例

```bash
base64 -w 0 release-keystore.jks
```

> macOS の場合は `base64 release-keystore.jks | tr -d '\n'` を利用してください。

## 初期セットアップ確認

1. Play Console 側で対象アプリにサービスアカウントを招待済みであること
2. サービスアカウントに「リリース管理」相当の権限があること
3. `android/key.properties` はリポジトリに含めず、CIで毎回生成されること

## 運用メモ

- `versionName`（`x.y.z`）は手動管理です。必要時のみ `pubspec.yaml` で更新します。
- `versionCode`（`+n` の n）は workflow により自動更新されます。
- internal track で検証後、production への昇格は Play Console 側で実施してください。

## トラブルシュート

- 署名エラー: keystore の base64 文字列破損、alias/password 不一致を確認
- 配信エラー: サービスアカウントの権限不足または packageName 不一致を確認
- ループ実行: bot commit には `[skip release]` を付与して再実行を抑止

## PR運用ルール

- リリース自動化に関する PR タイトル・本文は日本語で記載します。
- PR 本文には `created by Codex` を含めます。

