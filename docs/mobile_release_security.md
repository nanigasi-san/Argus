# モバイル配信のセキュリティとレビュー

## GitHub の実設定（2026-09-18）

リポジトリは公開の `nanigasi-san/Argus`。閲覧・fork・外部 PR ができても、配信 Secrets を利用する権限は与えない。

- `protect-main` (9448222): PR と5つの必須 CI。管理者の bypass なし。
- `release-tags-creation` (23612942): `refs/tags/v*` の作成を制限し、管理者ロールだけ許可。
- `release-tags-immutable` (23612944): `refs/tags/v*` の更新・削除は禁止。bypass なし。
- collaborators の読み取り結果は `nanigasi-san` 1人、管理者も同アカウントのみ。
  GitHub の ruleset はこの構成でユーザー個人ではなく管理者ロールを指定する。
  将来ほかの管理者を追加するなら、その前に Environment の required reviewers を再導入する。
- `android-release` / `ios-release`: tag 型 `v*.*.*` だけ許可。branch / PR ref は許可しない。
  上記の単独管理者・タグ作成制限により、通常の配信承認は不要。
- workflow の actor / triggering_actor も `nanigasi-san` を要求する。
  これは補助検証であり、Secrets を守る境界は GitHub 側のタグ規則と Environment の ref 制限。
- Android の配信 Secrets 5つを Environment へ移行し、Repository Secrets の同名値を削除済み。
  iOS の6つも Environment のみ。Repository Secret として残る `CODECOV_TOKEN` はカバレッジ送信用。
- 移行ではリポジトリ側に秘密復号鍵を渡さず、公開証明書で暗号化した値だけを Artifact に保存した。
  ローカルで復号し Environment へ標準入力で登録。秘密値はログ・Git・平文 Artifact に出していない。
  一時移行 workflow、暗号化 Artifact、ローカル復号秘密鍵を削除した。

権限のある所有者が悪意あるタグを作る場合や、所有者の GitHub アカウント自体を奪われた場合まで
workflow 内の検査で防げるとは扱わない。API キー・署名秘密鍵は定期的に更新し、漏えいが疑われれば失効・交換する。
この確認で、実際の配信秘密鍵の漏えいを示す証拠は見つかっていない。

## レビュー指摘への対応

| 指摘 | 対応 |
| --- | --- |
| 未レビュー workflow が配信 Secrets を利用可能 | Environment へ集約、tag-only、作成者制限、タグ変更禁止を GitHub に設定 |
| Android が main / CI 未確認でビルド | 両 OS の共通 gate で main 祖先・対象 SHA・5つの所定 main push workflow 成功を要求 |
| closed test 設定が production 公開へ化ける | 手動 closed test 経路と `PLAY_CLOSED_TRACK` を削除。ユーザー指定で production 本番配信に固定 |
| iOS が未知の同番号 build を採用 | 成功した upload または既知 Apple build ID の証跡を要求。結果不明なら停止 |
| iOS 下書きの設定不一致を提出後に検出 | メタデータ保存と提出を分離し、提出直前に build・公開方式・段階的公開・更新内容・審査情報を読み直す |
| Android の同時配信が競合 | アプリ単位で直列化、cancel-in-progress false |
| Android が古い版の審査を継続する | commit に CANCEL_IN_REVIEW_AND_SUBMIT を明示し、検証済みの最新版へ審査を差し替える |
| Android が署名後の未署名ファイル追加を見逃す | jarsigner の strict 検証で未署名エントリーを拒否し、自己署名の upload 証明書は fingerprint で照合 |
| 必須 Secrets 欠落でも成功 | 開始時の必須検証、配信ビルドの debug 署名禁止、AAB 署名 fingerprint 確認 |
| Android の再実行が重複 upload | 元の AAB と receipt を復元し、Google の同番号 AAB SHA-256 を照合。edit / commit 状態に応じて再開 |

ストアキーは必要なステップのみに渡す。配信に使う Actions は完全な commit SHA へ固定した。
GitHub token は contents/checks/actions read のみ。Secrets、JWT、審査連絡先を receipt に保存しない。
Android API の失敗時に認証レスポンスを丸ごと出力しない。

## リポジトリ全体の確認範囲

- 追跡ファイル228個と主要なアプリ・ネイティブ設定・CI・配信・運用文書を確認。
- `gitleaks git --log-opts='--all' --redact`: 取得済み全 refs の115コミット、約2.56 MBを走査し検出0件。
- 現在の追跡ソースについて、private key / service-account key / token の典型パターンを照合し検出なし。
  最終差分約103 KBも commit 前に走査し検出0件。
- `pull_request_target` による PR コード実行、外部入力を `eval` する経路、TLS 証明書検証の無効化は見つからなかった。
- Android の公開 Activity は通常の launcher。任意 URL から自動実行する deep-link intent はない。
  iOS の ATS 全面無効化、Android の cleartext 通信許可は見つからなかった。
- ストア API key・upload keystore・署名用 password はアプリコードへ埋め込まない。
  外部ブラウザへ開く URL はプライバシーポリシーと問い合わせ先の固定 URL。
- CI の Flutter Tests に contents read を明記し、Codecov token を使う送信を main push のみに限定した。
- GeoJSON / QR の入力処理ではファイル名のパス区切り除去・形式検証を確認。
  gzip 展開・大きな GeoJSON のメモリ上限は別途強化余地がある。今回の CD 修正ではアプリの入力仕様は変更していない。

これは自動スキャンとコードレビューであり、侵入テスト・全依存関係の脆弱性監査・ストア権限全体の監査ではない。
公開済みの外部 Artifact、アクセスできないサーバー、漏えいした履歴の外部コピーまで検証したとは扱わない。
API は審査を回避できず、Google の Managed publishing の現在設定は未確認。
新しい本番 CD 自体の初回 upload は次の実リリースで確認する。

## 根拠となる公式資料

- [GitHub: deployment environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [GitHub: repository rulesets API](https://docs.github.com/en/rest/repos/rules)
- [Google: Edits の競合と commit](https://developers.google.com/android-publisher/edits)
- [Google: production track](https://developers.google.com/android-publisher/tracks)
- [Google: 審査と Managed publishing](https://support.google.com/googleplay/android-developer/answer/9859654)
- [Apple: 審査承認後の自動公開](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/)

## 改修後の検証

- Python: `python3 -m unittest discover -s scripts -p 'test_*.py'`、47件成功。
- Ruby: `bundle exec ruby fastlane/test_release_support.rb`（ios 配下）、15件・43 assertions 成功。
  未知 build 採用拒否、公開設定・更新内容・段階的公開変更の提出前拒否も含む。
- 配信 workflow 2本の actionlint、`flutter analyze`: 成功。
- Android 全 E2E: `bash scripts/run_android_e2e.sh emulator-5554`、全3ファイル・14シナリオ成功。
  Pixel 7 Pro / API 36 / Google APIs / arm64-v8a / Flutter 3.44.1。
  `integration_test/compass_navigation_test.dart` 1件、`core_monitoring_e2e_test.dart` 8件、
  `ui_smoke_test.dart` 5件。`e2e/` は現在存在せず、存在する全対象を再帰検出して実行した。
  `SIMULATOR_GPS` 任意モードは未実行。
- ローカル結果は `build/e2e/`、スクリーンショットは `build/integration_test/screenshots/` に保存。
- 今回の検証では production upload・審査提出・既存公開設定の変更は実行していない。

実 API の読み取りで、main の5 workflow 成功照合と Apple の段階的公開が無効であることを取得できた。
Apple の `resetRatingsRequest` relationship は現在の API で未提供だったため、その読み取りを成功条件には含めない。
fastlane へ `reset_ratings: false` を指定し、評価リセットを要求しない。

Android 署名検証は一時テスト鍵を使った実際の `keytool` / `jarsigner` でも確認し、
正しい署名と証明書 fingerprint の受け入れ、未署名成果物の拒否を確認した。
