# Android 本番リリース

`nanigasi-san` が main に反映済みのコミットへ `vX.Y.Z` タグを push すると、
5つの必須 CI がすべて同じ SHA で成功したことを確認して、署名 AAB をビルドする。
Google Play の `production / completed` を commit し、Google の審査・公開処理へ進める。
従来の production 下書き停止と手動 closed test 配信は廃止した。

## 通常の手順

1. `docs/app_store/releases/<version>/ja-JP.txt`（両ストア共通、500文字以内）と
   `review_notes.md`（iOS の審査メモ、3900文字以内）を用意し、アプリの変更とともに PR で main に取り込む。
2. main push の `Flutter Tests`、`Android Build`、`iOS Build`、`Android E2E`、`iOS E2E` が成功したことを確認する。
3. 配信対象の main コミットに `vX.Y.Z` タグを作成し push する。同じタグで iOS も配信される。
4. 各 workflow の Job Summary を確認する。Google Play の審査・公開状態は Play Console で確認する。

タグの削除・付け替えはしない。GitHub の ruleset でも禁止している。
main に未反映、CI 未完了・失敗、必要設定・更新内容の欠落時はビルド前に停止する。
チェック名だけでなく、main push の所定 workflow の結果を照合する。

## 自動化の到達点

API は production に `completed` を指定し、`changesNotSentForReview=false` で commit する。
Google の審査・公開は非同期であり、CD の成功は「公開要求の commit 完了」を意味する。
審査通過やユーザーへの配信完了を意味しない。
「管理対象の公開（Managed publishing）」が無効なら、必要な審査の承認後に通常は自動公開される。
有効なら審査承認後の公開操作が必要。現在の Play Console の当該設定はこの変更では確認・変更していない。
契約・ポリシー・宣言・アクセス権が不足する場合は停止し、必要な Console 操作を実施する。
審査が翌日・翌々日に終わることは保証しない。CI 内で何日も待機しない。

- [Google: APKs and Tracks](https://developers.google.com/android-publisher/tracks)
- [Google: edits.commit](https://developers.google.com/android-publisher/api-ref/rest/v3/edits/commit)
- [Google: 審査と公開のタイミング](https://support.google.com/googleplay/android-developer/answer/9859654)

## 設定

Repository Variable `RELEASE_VERSION_CODE_OFFSET=1005` と `github.run_number` の和を versionCode にする。
offset の未設定・不正値・番号上限超過は失敗にする。バージョン名はタグから解決する。
Flutter 3.44.1 と Java 17 を使用する。配信 Actions は commit SHA で固定する。

次の5つは **Environment `android-release` の Secrets** に保存する。
Repository Secrets の同名値は暗号化移行後に削除済み。

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`
- `PLAY_SERVICE_ACCOUNT_JSON`

Secrets が空なら失敗にする。配信用ビルドは debug 署名を禁止し、
AAB の JAR 署名と upload key の証明書 fingerprint を照合する。
Google の認証鍵は upload ステップだけへ渡し、Flutter / Gradle の実行環境へ渡さない。
終了時に一時 keystore と `key.properties` を削除する。

## 競合と再実行

- アプリ単位の concurrency で直列化し、進行中の実行はキャンセルしない。
- 元の検証済み AAB と receipt を upload 前・終了時に Artifact へ90日保存する。
- 同じ run の再実行は元の AAB を復元し、ソース SHA・versionCode・run ID・package と SHA-256 を確認する。
  成果物が失われた場合に、同じ番号で異なる AAB を再ビルドしない。
- 有効な edit が残っていれば再利用する。commit 後の通信切断なら、新しい edit の一覧で
  同じ versionCode と AAB hash、production の completed 状態を照合して成功を確認する。
- 別の hash の build、他の production 下書き・段階的配信、同番号以上の別 production release を上書きしない。
- API が失敗した場合に draft / closed test / `changesNotSentForReview=true` へ自動で切り替えない。
  ストアの操作結果が不明なら Console と receipt を確認する。
- Play Console での同時編集でも edit が無効になるため、配信中は Console で編集しない。

Secrets・タグの保護設定とリポジトリ全体の確認結果は
[配信セキュリティ](mobile_release_security.md)を参照。
