# iOS リリース運用

iOS はGitHub ActionsのCDを使用せず、Mac上で `argus-ios-release` スキルを使って署名・配信する。
Androidのみ `vX.Y.Z` タグpushでCDが起動する。iOSは同じタグのcommit SHAを明示して作業し、
Appleの承認後に自動公開する。段階的公開は使用しない。

## 手順

1. `docs/app_store/releases/<version>/ja-JP.txt` と `review_notes.md` をmainへ反映する。
2. 対象main SHAで5つの必須CIが成功していることを確認する。
3. タグとmain SHAの一致、App Store Connectの既存version/buildと提出状態を確認する。
4. `argus-ios-release` スキルで未使用build番号を選び、署名IPAを生成・検証する。
5. IPAをApp Store Connectへuploadし、処理完了後に対象buildをversionへ紐付ける。
6. 日本語更新内容・審査メモ・自動公開・段階的公開なしを確認して審査へ提出する。
7. `docs/app_store/YYYY-MM-DD_ios_<version>_release.md` にSHA、version/build、CI、
   ビルドコマンド、IPA SHA-256、upload結果、審査状態、公開設定、提出URLを記録する。

`WAITING_FOR_REVIEW` / `IN_REVIEW` は公開済みではない。公開はAppleの承認後に進む。
同じversion/buildが存在する場合は再uploadせず、状態を確認して安全に再開する。

## 固定値

- Bundle ID: `com.argus.orienteering`
- App Store Connect App ID: `6781527103`
- Team ID: `DLJC9VB2SL`（実行時に現在のTeamと照合する）
- export method: `app-store-connect`
- `manageAppVersionAndBuildNumber`: `false`

認証情報はKeychainまたは `~/.appstoreconnect/private_keys/` の既存設定を使い、
ログ、Git、リリース証跡には保存しない。
