# iOS CD の運用と設定

`iOS Release` は Android Release と同じ `vX.Y.Z` タグ push で起動する。
GitHub-hosted macOS runner で署名 IPA を作り、App Store Connect に upload し、
対象 build を審査へ提出する。公開方式は承認後の自動公開、段階的公開なし、評価維持。
Apple の審査が終わるまで公開済みとは扱わない。

## 登録済みの設定（2026-09-18）

リポジトリ: `nanigasi-san/Argus`。Environment: `ios-release`。
Environment の配信許可は `v*.*.*` タグに限定した。
秘密の値をこの文書や Git に記載しない。

| 種別・保存先 | 名前 | 用途・設定状況 |
| --- | --- | --- |
| Repository Variable | `IOS_TEAM_ID` | `DLJC9VB2SL` を登録済み |
| Repository Variable | `IOS_RELEASE_BUILD_NUMBER_OFFSET` | `1010` を登録済み。初回 run_number=1 は1011 |
| Environment Secret | `IOS_DISTRIBUTION_P12_BASE64` | この Mac の ARGUS 用 Apple Distribution 証明書と秘密鍵を export して登録済み |
| Environment Secret | `IOS_DISTRIBUTION_P12_PASSWORD` | export 時に生成したランダム password を登録済み |
| Environment Secret | `IOS_APPSTORE_PROFILE_BASE64` | Team/Bundle ID/Time Sensitive capability を確認した App Store profile を登録済み |
| Environment Secret | `ASC_KEY_ID` | リリース用 Team API キーの ID を登録済み |
| Environment Secret | `ASC_ISSUER_ID` | アカウントの Issuer ID を登録済み |
| Environment Secret | `ASC_PRIVATE_KEY_BASE64` | API キー p8 を Base64 化して登録済み |

Apple の API 利用申請は同意を得て提出し、承認済み。
キー名は `ARGUS GitHub Actions Release`、権限は App Manager。
Team キーは Apple アカウント内の全アプリに作用する。workflow は App ID/Bundle ID を照合して ARGUS だけを操作する。
API キーは一度しかダウンロードできないため、この Mac の `~/.appstoreconnect/private_keys/` に
所有者だけが読めるバックアップを保存した。GitHub の Secret 値は後から読み出せない。

配布証明書の有効期限は2027-06-15 UTC、profile は2027-06-18 UTC。
期限前に更新し、同じ Secret 名で差し替える。API キーの失効・権限変更時も差し替える。
Base64 は暗号化ではなく、GitHub Secrets の保存とアクセス制御を利用する。

固定値は workflow の `IOS_APP_ID=6781527103`、`IOS_BUNDLE_ID=com.argus.orienteering`。
`GH_TOKEN` は実行ごとの GitHub token、一時 keychain password は runner 内で生成するので登録不要。
`RELEASE_VERSION`、`RELEASE_BUILD`、`RELEASE_SHA` は検証 job の出力から設定する。
`IOS_PROFILE_UUID` と `IOS_EXPORT_OPTIONS` は署名復元時に設定する。手動登録しない。

## 配信の手順

1. 変更と日本語の更新内容を PR で main に取り込む。
   `docs/app_store/releases/<version>/ja-JP.txt` と `review_notes.md` を用意する。
   更新内容は4000文字以内。審査メモは先頭に version/build が自動で付くため少し余裕を持たせる。
   [0.8.0 の記録](app_store/2026-09-18_ios_0.8.0_release.md)と
   [審査メモ案](ios_release.md)を参考に、実際の変更内容に合わせて記載する。
2. main の5つの必須チェックが配信対象コミットで成功したことを確認する。
3. 対象コミットに `vX.Y.Z` タグを作成し origin へ push する。
   同じタグで Android Release も起動する。Android は現行実装どおり production の draft、
   iOS は審査提出まで進む。各 OS の結果を別々に確認する。
4. `iOS Release` の Job Summary と receipt Artifact で対象 SHA、番号、IPA hash、
   build ID、version ID、submission ID、審査状態を確認する。

```bash
# 例。0.9.0を実際にリリースすると決めた場合だけ実行する。
git tag v0.9.0 <main上の配信対象コミット>
git push origin v0.9.0
```

既存 `v0.8.0` は削除・移動・再 push しない。
2026-09-18 のレビュー時点では0.8.0は審査中（`IN_REVIEW`）なので、次のversionの配信は既存提出が完了してから行う。
審査中の他version、別versionの下書き、対象不明の提出項目があると workflow は停止する。

## 実装と検証条件

- gate job は Secrets を使用しない。タグ形式、タグ commit と checkout の一致、main の祖先であることを確認する。
- Flutter Tests、Android Build、iOS Build、Android E2E、iOS E2E が同じ SHA で成功していることを確認する。
  最新のチェック結果を使い、失敗・キャンセル・skip は通さない。未完了は最大40分待つ。
- release job の Secrets は `ios-release` Environment に置く。
  タグ側の workflow 自体が実行されるので、タグを作成できる人は信頼された配信担当者に限る運用とする。
  Environment のタグパターンは「タグが main 上にある」ことを保証しない。
  この変更では既存 GitHub ruleset を変更していない。
- 採番は Android と同じ `github.run_number + offset`。offset は iOS 専用。
  Apple にある全 build 番号より大きいことを確認し、衝突時は upload 前に止める。
  整数の iOS build 番号は1〜9999に制限する。採番形式や workflow カウンターを変える際は設定を移行する。
- App ID ごとの `concurrency`、`cancel-in-progress: false` で直列化する。
  pending は GitHub の既定動作で置き換えられ得るため、タグをまとめて push しない。
- Flutter 3.44.1、Xcode 26.6、Ruby 3.3、fastlane 2.240.1、CocoaPods 1.16.2を指定する。
  fastlane の依存は `ios/Gemfile.lock` で固定する。
  Flutter を fastlane から起動した際も同じ CocoaPods を使えるよう、同じ Gemfile に含める。
  [CocoaPods: Using a Gemfile](https://guides.cocoapods.org/using/a-gemfile.html)
- App Store profile の有効期限・Team・Bundle ID・配布証明書・Time Sensitive capability を検証する。
  Runner の Release 構成だけを作業 checkout 内で manual signing にする。
- `flutter build ipa` は一度だけ実行する。ExportOptions は runner 内に生成し、番号自動変更を無効にする。
  最終 IPA の署名・version/build・entitlement・最低 iOS・Background Modes・暗号化宣言を upload 前に検証する。
- pilot は完成した IPA の upload だけを行う。処理待ちは同じ version/build に対し API で最大40分行い、
  TestFlight グループ配布やテスター通知は行わない。
- deliver は対象 version/build を明示し、更新内容と審査メモを設定して審査提出する。
  審査連絡先は App Store Connect の既存情報を引き継ぐ。説明・スクリーンショット・プライバシー回答を生成しない。
  再実行時に対象versionの審査情報がまだ作成されていなければ、直前versionから引き継ぐ。
  対象versionに情報があるが不完全な場合は、担当者による確認を求めて停止する。
  fastlane の公開 CI ログへ連絡先が表示されないよう、引き継ぐ値を GitHub の mask に登録する。
- 成功後に対象 build と submission、審査状態、自動公開方式を API で読み直す。
  秘密鍵、JWT、審査連絡先は receipt に入れない。終了時は一時 keychain と秘密ファイルを削除する。
  keychain の検索パス復元が失敗しても残りの削除を続け、後片付けの失敗を job に報告する。

## テストに Ruby と Python を使う理由

アプリとアプリのテストは引き続き Dart / Flutter を使用する。
Ruby と Python は配信のための補助処理に使用する。

| 言語 | 対象と理由 |
| --- | --- |
| Ruby | fastlane が Ruby 製のため、Apple API 操作・upload・審査提出・再実行処理を同じ言語で実装・検証する |
| Python | 既存 CI と同じ標準ライブラリ中心の補助スクリプト。タグ・採番・CI チェック・署名 profile・IPA の plist と配信証跡を検証する |
| Dart | アプリの unit / widget テストと、Android・iOS で動く全 E2E |

Ruby の回帰テストでは新規 upload と新規審査提出、既存 build の再利用、
誤った build・他versionの提出を拒否する処理を Apple API の代替モデルで確認する。
これは実 App Store への upload を伴うテストではない。

## 再実行

GitHub の Re-run は run_number が増えないので同じ version/build を再利用する。
同じ run の以前の attempt の receipt だけを復元し、SHA・番号・App ID・Team・run ID が一致することを確認する。

| 失敗地点・状態 | 対応 |
| --- | --- |
| gate / 署名復元 / Archive 前、IPA 証跡なし | 設定を修正して同じ run を Re-run。workflow コード修正は過去タグへは反映されない |
| Apple に対象 build が存在し、同じ run の IPA hash 証跡がある | 再 Archive/upload を省き、処理待ちと提出から再開 |
| 審査待ち・審査中、対象 build と submission が一致 | 再提出せず、同じ提出を確認して成功 |
| 自分の version/build だけが入った READY_FOR_REVIEW 下書き | 対象と receipt を照合して最終提出を再開。既存項目の削除は行わない |
| IPA 証跡はあるが Apple に build がまだ見えない | upload 結果が不明な可能性があるため停止。Apple の処理状況を確認し、見えるようになってから Re-run |
| Apple build があるが receipt がない / Artifact 期限切れ | ソースを証明できないので自動採用しない。担当者が証跡を確認する |
| 他versionの提出・下書き、番号衝突、契約・権限不足 | 原因を解消してから再開。自動取消・証明書一括失効は行わない |

Archive 後かつ upload 前に停止して Apple build がない場合も、曖昧な upload と安全に区別するため停止する。
その場合の手動 recovery は今回の workflow に含めていない。receipt を確認して配信担当者が復旧する。
通常の本番起動はタグ push のみで、手動実行トリガーは追加していない。
preupload/result receipt は90日保持する。リリース証跡として必要な場合は別途 PR で保存する。

## 設定の確認と更新

```bash
gh variable list
gh secret list --env ios-release
gh api repos/nanigasi-san/Argus/environments/ios-release/deployment-branch-policies
# p12/profile/p8 のBase64は標準入力から登録する。値をコマンド行に直接書かない。
gh secret set IOS_DISTRIBUTION_P12_BASE64 --env ios-release < encoded-p12.txt
```

公開リポジトリで Secrets が利用できる workflow 変更とタグ作成は、配信権限を持つ変更としてレビューする。
GitHub の Environment Secret の表示では値は確認できないため、登録名の確認と API/署名の検証を分ける。

## この変更で実行した確認

- 新しい iOS Release workflow: `actionlint` 成功。
- Python の CI/署名/gate 回帰テスト: 35件成功。
- Ruby の配信・再実行回帰テスト: 12件成功、32 assertions（ローカル Ruby 4.0.5。CI は指定した Ruby 3.3 で実行）。
- 固定版 fastlane の lane 読み込み成功。
- export した p12 の証明書 fingerprint と有効期限を確認し、profile の証明書と一致。
- 前回配布した0.8.0の IPA が今回の署名・番号・entitlement 検証処理を通ることを確認。
- 発行した API キーで ARGUS の既存version/build と提出物を読み取り確認。新規 upload・審査提出は実行していない。
- 実 API に対する読み取り preflight で、0.8.0の審査待ち・審査中が次versionの配信を止めることと、既存審査連絡先を引き継げることを確認。
- `flutter analyze`: 成功。
- Android 全件 E2E: `bash scripts/run_android_e2e.sh emulator-5554` 成功。
  Pixel 7 Pro / API 36 / Google APIs / arm64-v8a、Flutter 3.44.1。
  `integration_test/` と `e2e/` の存在する全対象を再帰検出した結果、次の3ファイル・14シナリオを実行。
  `e2e/` は現時点で存在しない。`SIMULATOR_GPS` 任意モードは未実行。
  - `integration_test/compass_navigation_test.dart`: 1件成功。
  - `integration_test/core_monitoring_e2e_test.dart`: 8件成功。
  - `integration_test/ui_smoke_test.dart`: 5件成功。
  ログ、ファイルごとの実行件数、スクリーンショットをローカルの `build/e2e/` と
  `build/integration_test/screenshots/` に保存した。環境の再利用は
  [macOS の Android E2E 環境](android_local_e2e.md)を参照。

クリーンな hosted runner での署名・API upload・審査提出は、実装のマージと次の実リリースで確認する。
導入前の公式資料と実運用記事の照合は [調査と設計](ios_release_automation.md) に記載した。
Apple は API による新version作成・審査提出・承認済みアプリ公開を公式用途として案内している。
自チームの ARGUS の CD として利用する。
[Apple: App Store Connect API overview](https://developer.apple.com/app-store-connect/api/)
