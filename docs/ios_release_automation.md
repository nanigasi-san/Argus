# iOS リリース自動化の調査と設計

調査日: 2026-09-18。対象: nanigasi-san/Argus。
この文書はGitHub ActionsによるiOS CDを検討した当時の調査記録であり、現在は採用していない。
現在の手動リリース手順は [iOS リリース運用](ios_release_cd.md) を参照する。
以下の現在地・未確認事項は調査時点の記録であり、導入後の設定状況と区別する。

## 推奨する構成

GitHub Actions の GitHub-hosted macOS runner で Flutter の署名付き IPA を作り、
fastlane の API キー認証でアップロード・更新情報登録・審査提出まで実行する。
手元の MacBook の起動や Apple Account のブラウザログインに依存しない構成にする。
Apple の審査、契約更新、実機での動作確認は別に残る。

Flutter 公式は GitHub Actions と fastlane の組み合わせを紹介している。
Gemfile と lockfile による依存固定、既存 Flutter Archive の再利用も案内されている。
[Flutter: Continuous delivery](https://docs.flutter.dev/deployment/cd)

本番トリガーはユーザー指定により Android と同じ `vX.Y.Z` のタグ push とする。
タグ名から version、タグの参照先から配信対象 SHA を確定し、審査提出・承認後の自動公開まで進める。
既存 Android Release も同じ push で起動する。iOS の再実行のために共通タグを削除・移動しない。
初回の検証は配信を開始しないテストと署名ビルドから行い、本番トリガーと分ける。

## ARGUS の現在地

| 項目 | 確認結果 | 設計への影響 |
| --- | --- | --- |
| iOS CI | iOS Build は Simulator と XCTest、iOS E2E は全共通 E2E | 配布用署名と Archive は別 workflow が必要 |
| 品質チェック | main の必須チェックは Flutter Tests、両 OS Build、両 OS E2E | 配信対象 SHA の成功を確認してから配信 |
| リポジトリ | `gh repo view` で public を確認 | 標準 hosted runner を利用できる |
| リポジトリ Secrets | `gh secret list` には Android と Codecov のみ | iOS 用 Secrets を準備する。Environment/Organization の全設定は未確認 |
| Bundle ID / App ID | `com.argus.orienteering` / `6781527103` | API で取得したアプリ情報と一致確認 |
| Developer Team | project は `DLJC9VB2SL` | 証明書・profile の Team と一致確認 |
| バージョン | pubspec は `0.7.0+1009`、直近提出は `0.8.0 (1010)` | pubspec から配信番号を自動決定しない |
| iOS 設定 | iOS 15.0、Background Modes の audio/location、Time Sensitive entitlement | profile と配布 IPA でも設定を検証 |
| ローカルの実績 | 0.8.0 の IPA 作成、Xcode アカウントで upload、ブラウザで審査提出に成功 | API キーだけを使うクリーン runner での成功は未確認 |
| main の保護 | 直接 push は拒否された | workflow から pubspec や提出記録を main に直接 push しない |

確認対象は `.github/workflows/ios_build.yml`、`ios_e2e.yml`、`flutter_tests.yml`、
`android_release.yml`、`ios/Runner.xcodeproj/project.pbxproj`、
`ios/Runner/Runner.entitlements`、`docs/ci.md`、
[0.8.0 提出記録](app_store/2026-09-18_ios_0.8.0_release.md)。
この記録時点の App Store Connect 状態は「審査待ち」であり、公開済みとはしていない。

## 公式手順で確認できたこと

| 工程 | 公式に確認した方法 | ARGUS での方針 |
| --- | --- | --- |
| 署名環境 | GitHub Secrets から p12 と profile を復元し、一時 keychain に import | 初回は既存配布証明書を利用 |
| Flutter ビルド | `flutter build ipa` で Archive と IPA を生成 | version/build を引数で注入 |
| Apple 認証 | App Store Connect API キーから JWT を生成 | Apple ID/password/2FA の継続セッションを使わない |
| バイナリ upload | Apple は Xcode、Transporter、altool、API に対応 | 初回は fastlane pilot を使用 |
| 処理待ち | upload 直後にビルドが利用可能になるとは限らない | 対象 build の処理完了を待つ |
| 審査提出 | メタデータと build を設定し、提出物に追加してから提出 | fastlane deliver、version/build を明示 |
| 公開 | 審査承認後の自動公開と手動公開を選べる | 指定モードに対応し、公開方式を記録 |

署名復元の基準は
[GitHub: Sign Xcode applications](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。
証明書は秘密鍵を含む p12 が必要で、公開証明書の cer だけでは足りない。
hosted runner は終了後に破棄されるが、一時ファイルと keychain は終了処理でも削除する設計とする。

ビルド番号指定・IPA 出力の基準は
[Flutter: Build and release an iOS app](https://docs.flutter.dev/deployment/ios)。
署名ビルドは Xcode/macOS が必要だが、ユーザーの端末が macOS である必要はない。

アップロード手段と Apple 側の処理待ちは
[Apple: Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)。
API によるバイナリアップロードも現在は提供されており、API はメタデータ操作だけという前提にしない。
直接実装する場合は
[Apple: Build uploads](https://developer.apple.com/documentation/appstoreconnectapi/build-uploads)
が対象になる。ただし初回は upload protocol を独自実装せず既存ツールを利用する。

審査は「Add for Review」だけでは提出されない。
[Apple: Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
の最終提出まで必要。API でも
[Review submissions](https://developer.apple.com/documentation/appstoreconnectapi/review-submissions)
を使う設計で、ブラウザ内部の非公開 API を直接呼ばない。

## 実際の導入記事との照合

記事は執筆者自身の導入例として扱い、API 権限や現在のオプションは公式ドキュメントで再確認した。
記事だけでは ARGUS の署名・審査提出が成功することまでは保証できない。

| 記事・日付 | 確認した実装 | 採用する考え方 / そのまま使わない点 |
| --- | --- | --- |
| [かっきー: Flutter + GitHub Actions + Fastlane のテスト配布](https://zenn.dev/hayate_doc/articles/c56a31364c3248)（2025-05-04） | match readonly、API キー、一時 keychain、手動署名、TestFlight | クリーン runner での署名準備を参考にする。TestFlight のみで App Store 審査は対象外。Secrets 名と変数名の対応は自分の定義で統一する |
| [NCDC / ゆーと: fastlane で TestFlight を配信](https://zenn.dev/ncdc/articles/fastlane_testflight)（2024-05-07、更新 2024-06-01） | 配信ブランチ制限、最新 TestFlight build + 1、match、Flutter と Xcode ビルド | 番号確認と配信元制限を参考にする。単純な最新値 + 1 は並列実行で衝突し得る。Flutter 設定の番号を最終 IPA で検証し、二重 Archive を避ける |
| [カウシェ / ymshun: iOS・Android の審査提出を自動化](https://zenn.dev/ymshun/articles/55f7f1fc4b4e48)（2025-12-12） | Actions 入力、pilot の処理待ち、deliver で審査提出、公開方式指定 | 審査提出までの実運用例。署名準備は省略されているため GitHub 公式で補う。記事は手動公開・段階的公開であり ARGUS の自動公開とは設定を変える。通知先追加は今回の必須要件にしない |
| [エクサウィザーズ: GitHub Actions + Fastlane の継続的デリバリー](https://zenn.dev/exwzd/articles/20210323_ios_cd_github_actions_fastlane)（原文 2021-03-23、移行ページ更新 2026-04-06） | 手動起動、リリース準備、タグと申請を含む運用 | 工程の分離を参考にする。Git Flow や main/develop 同時マージは ARGUS に持ち込まない。ページの更新日を API 手順の最新性と同一視しない |

## 構成の比較

| 選択肢 | 利点 | 追加負担 | 判断 |
| --- | --- | --- | --- |
| Actions + p12/profile の Secrets + fastlane | 現行 CI と接続しやすく、別の証明書管理ストレージが不要 | 証明書/profile の更新時に Secrets を差し替える | 初回の推奨 |
| Actions + fastlane match | 複数アプリ・複数開発者への配布証明書共有がしやすい | 暗号化ストレージ、復号鍵、アクセス認証が増える | 共有管理が必要になったら移行 |
| Xcode Cloud | Apple の配布ビルド・署名・TestFlight 配布が統合される | Flutter の post-clone 準備、既存 Actions との結果連携、審査提出処理が必要 | 代替案 |
| MacBook の self-hosted runner | ローカル環境を活用できる | 常時稼働・保守が必要 | 手元 Mac への依存解消には hosted runner を選ぶ |

match を使う場合、CI は readonly とする。
[fastlane: match](https://docs.fastlane.tools/actions/match/)
初回は現在の証明書の移行を検討し、既存証明書の一括失効や作り直しを行わない。

Xcode Cloud でも配布ビルドを作れるが、審査提出は別工程として設計する。
[Apple: Distribution workflow](https://developer.apple.com/documentation/Xcode/Creating-a-workflow-that-builds-your-app-for-distribution)
Flutter の準備には公式の post-clone スクリプト例を参照できる。

ARGUS は public のため標準 GitHub-hosted runner の実行時間は無料の対象。
Artifact/キャッシュのストレージや larger runner は別条件なので、保持期間を決める。
[GitHub: Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

## 初回に準備する認証情報

下記は提案する名前。配信 Secrets の保存先は保護した Environment を想定する。
既存 Secrets の値を読んだり変更したりはしていない。

| 保存先 | 名前 | 内容 |
| --- | --- | --- |
| Secrets | `IOS_DISTRIBUTION_P12_BASE64` | 有効な Apple Distribution 証明書と対応する秘密鍵を含む p12 の Base64 |
| Secrets | `IOS_DISTRIBUTION_P12_PASSWORD` | p12 の export password |
| Secrets | `IOS_APPSTORE_PROFILE_BASE64` | ARGUS の App Store Connect 用 mobileprovision の Base64 |
| Secrets | `ASC_KEY_ID` | API Key ID |
| Secrets | `ASC_ISSUER_ID` | Team キー使用時の Issuer ID |
| Secrets | `ASC_PRIVATE_KEY_BASE64` | API キー p8 の Base64 |
| Variables | `IOS_TEAM_ID` | Developer Team ID、現行 project と一致させる |
| Variables | `IOS_RELEASE_BUILD_NUMBER_OFFSET` | iOS 専用の採番オフセット。初期候補1010、実装前に最新 upload 番号と照合 |

keychain password は runner 内でランダム生成し、そのジョブだけで使う。
API キーの p8 と配布証明書の秘密鍵は別用途であり、片方では代用できない。
Base64 は暗号化ではなく、保存先を Secrets にする。

API access の初回申請は Account Holder、Team key 作成は Account Holder/Admin が行う。
Team key は全アプリに作用する。権限を ARGUS 単体へ限定できるとは説明しない。
[Apple: App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)

提出用は App Manager 相当の権限を基本にする。
Developer はアップロードできても審査提出には不足する。
Individual key はユーザーの権限に従い Provisioning API を使えない。
固定 p12/profile を使う構成では選択肢になり得るが、初回は Team key での互換性を検証する。
[Apple: Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)

pilot/deliver は API キー認証に対応し、fastlane はこの認証を推奨している。
[fastlane: App Store Connect API](https://docs.fastlane.tools/app-store-connect-api/)
API access の契約承諾、キー発行、Secrets 登録は実装後の初回設定として扱う。

## 実装するファイルと責務

| ファイル案 | 責務 |
| --- | --- |
| `.github/workflows/ios_release.yml` | Android と同じタグ push、タグ/SHA 検証、対象 SHA の品質確認、配信ジョブ、証跡保存、終了処理 |
| `ios/Gemfile` / `ios/Gemfile.lock` | fastlane と Ruby 依存を固定し `bundle exec` で実行 |
| `ios/fastlane/Fastfile` | API 認証、ビルド番号/状態確認、Runner の配布用署名、upload、submit の各 lane |
| `ios/ExportOptions.appstore.plist` | App Store Connect export の設定。秘密情報を含めない |
| `docs/app_store/releases/<version>/ja-JP.txt` | レビュー可能な日本語の更新内容 |
| `docs/app_store/releases/<version>/review_notes.md` | version/build に対応した審査メモ。既存の用途説明をベースにする |
| `scripts/` の補助処理 | CI 成功/IPA 情報/profile/提出状態の検証と receipt 出力。必要な部分のみ追加 |
| `.gitignore` | p8/p12/mobileprovision と認証用一時ファイルを除外。現在の `*.lock` 例外へ `ios/Gemfile.lock` を追加 |

fastlane の調査時最新 release は 2.240.1（2026-09-15）。実装時に Gemfile.lock を生成し、
依存を固定したうえで確認する。master の説明だけで互換性を保証しない。
[fastlane release 2.240.1](https://github.com/fastlane/fastlane/releases/tag/2.240.1)

### 起動からビルドまで

起動条件と同時実行制御の YAML 案（配信 job は未実装）:

```yaml
name: iOS Release

on:
  push:
    tags:
      - "v*.*.*"

permissions:
  contents: read
  checks: read

concurrency:
  group: ios-store-6781527103
  cancel-in-progress: false

env:
  IOS_RELEASE_BUILD_NUMBER_OFFSET: ${{ vars.IOS_RELEASE_BUILD_NUMBER_OFFSET }}
```

オフセット未設定はエラーとし、既存番号と衝突し得る暗黙の既定値を入れない。
実装を main にマージした後の新しいタグから有効になる。既存 `v0.8.0` は再 push しない。

1. `.github/workflows/android_release.yml` と同じ `on.push.tags` の `v*.*.*` を使い、
   実行時に `^v[0-9]+\.[0-9]+\.[0-9]+$` で検証する。glob だけでは形式検証にならない。
   version はタグ名から先頭の v を除いて取得し、タグのコミットを checkout する。
   annotated tag は commit に解決して source SHA を記録する。
   source SHA が保護された main の履歴に含まれることを確認し、タグ配信 workflow 自体も
   main にレビュー済みの定義を使う。タグ push ではタグ側の workflow が実行されるため、
   このチェック自体を任意の workflow が省けるという制約がある。
   配信 Secrets を保護した Environment に置き、許可タグとタグ作成・更新の ruleset を
   組み合わせる構成を実装時に確認する。YAML 内の ancestry 検証だけを Secrets のアクセス制御と扱わない。
   [GitHub: Environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)、
   [Tag rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
2. 対象 SHA の5つの必須チェックを検証する。名前だけでなく提供元と head SHA を照合し、
   pending/失敗/キャンセル/未実行なら配信しない。main の CI がまだ実行中なら上限付きで待つ。
   文書変更でも必要チェックがない SHA は勝手に免除しない。
3. API で Bundle ID/App ID、version、build、既存提出状態を確認する。
   審査中の他 version があれば停止する。既存 0.8.0 を自動で取り消さない。
4. Android と同じ `github.run_number + offset` を採用する。
   offset は Android と共有せず `IOS_RELEASE_BUILD_NUMBER_OFFSET` とし、初期候補1010なら
   iOS workflow の初回 run_number=1 は1011になる。整数・上限を検証する。
   実装前に Apple の最新 upload と照合し、候補が既存番号以下なら配信前に停止する。
   workflow 名/ファイルの変更や別 workflow の採番はカウンターの継続性に影響するため、
   自動でリセット・再利用せず次の未使用番号へ設定を移行する。
   Android の現行変数 `RELEASE_VERSION_CODE_OFFSET=1005` は iOS に流用しない。
   Re-run は run_number が増えないので同じ build を指す。新規タグは新規 build、
   Re-run は記録済み build の upload 状況確認・待機・提出の再開として扱う。
5. 採番から提出まで App ID 単位で直列化する。例: group `ios-store-6781527103`、
   `cancel-in-progress: false`。既存検証 CI の true を配信にコピーしない。
   pending は既定では置き換えられるので、全起動が必ず実行されるキューと説明しない。
   手動 upload はこのロックの外なので、並行して行わない運用と upload 前の重複確認も必要。
   [GitHub: Concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
6. Flutter/Ruby/Xcode の版を固定する。既存 Flutter 実績は3.44.1。
   runner は `macos-26` を候補にし、搭載 Xcode と Apple の提出条件の一致を確認してから固定する。
   ローカルの Xcode 27.0 が hosted runner にあるとは仮定しない。
   [GitHub: macOS 26 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
7. 必須 Secrets の欠落をビルド前に失敗させ、一時 keychain に配布証明書を復元する。
   profile の有効期限、Team、Bundle ID、証明書との対応、Time Sensitive capability を検証する。
8. Runner の Release 構成だけを CI checkout 内で配布用 manual signing に設定する。
   ExportOptions の指定だけでは Archive 工程の署名設定を変えられない。
   RunnerTests/Pods 全体へ同じ profile を強制しない。Debug/Simulator の既存設定を維持する。
   [fastlane: update_code_signing_settings](https://docs.fastlane.tools/actions/update_code_signing_settings/)
9. `flutter build ipa --release --build-name <version> --build-number <build> --export-options-plist <options>`。
   `method=app-store-connect`、`destination=export`、番号自動変更無効、internal-only 無効を設定する。
   Xcode の対応 export option は固定した Xcode で確認し、記事の古い `app-store` 表記を無検証でコピーしない。
10. 最終 IPA の番号、識別子、署名 entitlement、Background Modes を検証し SHA-256 を計算する。
    ビルドを失敗させる検証は upload 前に行う。

### アップロードと審査提出

upload lane は完成した IPA を pilot に渡す。Dart/Xcode Archive を再度作らない。
API キーの値は環境変数で渡し、workflow input を shell のコード文字列に直接埋め込まない。

- `skip_submission` と `skip_waiting_for_build_processing` は別の設定。
  前者は pilot の配布操作を省略するもので、App Store の審査提出を実行する意味ではない。
- submit へ進む場合は処理待ちを有効にする。
  `wait_processing_timeout_duration` で上限を設け、時間超過を成功扱いしない。
- 初回は upload と処理確認だけで検証し、TestFlight グループへの追加は必要な場合だけ行う。
  外部テスターへの配信・通知は自動で拡張しない。

根拠:
[fastlane: upload_to_testflight](https://docs.fastlane.tools/actions/upload_to_testflight/)

submit lane は対象 version/build を明示し、既存 upload を再利用する。
`skip_binary_upload=true` と `skip_screenshots=true` を使い、
更新情報と審査メモを登録して審査へ提出する。
`automatic_release` を指定された公開方式に合わせ、`phased_release=false`、評価維持を明示する。
`skip_metadata=true` を付けたまま更新情報も登録できるとは仮定しない。
既存説明/連絡先などは現行値を保ち、変更対象だけ送る挙動を固定版で確認する。
[fastlane: deliver](https://docs.fastlane.tools/actions/deliver/)

fastlane 2.240.1 の実装では、審査中の提出物や、項目入りの既存下書きがあると停止する。
対象 version を review submission の item に追加し、最後に submit を実行している。
したがって、途中失敗後に同じ lane を呼ぶだけで常に再開できるわけではない。
[2.240.1 の submit_for_review.rb](https://github.com/fastlane/fastlane/blob/2.240.1/deliver/lib/deliver/submit_for_review.rb)

完了後は API を読み直し、選択 build ID と提出物が一致し、審査待ち/審査中へ進んだことを確認する。
CLI の成功メッセージだけで公開済みとは報告しない。

## Android Release に揃える点と iOS 固有の点

| 項目 | Android の現行実装 | iOS の設計 |
| --- | --- | --- |
| トリガー | `v*.*.*` の push、手動は closed test | 同じタグ push を本番トリガーにする |
| version | タグの v を除去 | 同じ処理。pubspec を更新して push しない |
| build | run_number + RELEASE_VERSION_CODE_OFFSET | run_number + IOS_RELEASE_BUILD_NUMBER_OFFSET |
| 対象 | タグ ref の checkout | 同じ commit。main 履歴と CI を照合 |
| 配信先 | production、draft | App Store 審査提出、承認後の自動公開 |
| 認証不足 | 一部 step を skip する条件がある | 必須認証がなければ最初に失敗し、配信成功と区別 |
| 同時実行 | ref ごとの cancel-in-progress=true | App ID 単位、cancel-in-progress=false。別タグも直列化 |
| 証跡 | AAB Artifact | IPA hash、Apple ID 群と提出状態の receipt |

手動のリカバリー専用 workflow を追加する場合は version/build と receipt を指定し、
タグから確定した元の SHA に対応するビルドだけ再開する。通常の本番起動を手動方式へ置き換えない。

## 再実行と失敗時の扱い

| 状況 | 対応 |
| --- | --- |
| Archive 前に失敗 | 認証/設定を修正して同じ run を再実行。失敗を upload 成功扱いしない。workflow コード修正は次のリリースか明示した recovery で扱う |
| upload 結果が不明 | version/build の存在・処理状況を読み直し、存在するなら再 upload しない |
| Apple の処理待ちが時間超過 | upload 済みの番号と ID を記録し、同じ build の待機/提出工程から再開 |
| 提出前のメタデータ不足 | 不足項目を示して停止。勝手にプライバシー回答や年齢区分を作らない |
| 項目入りの既存下書き | receipt と API の item を照合。自動削除せず、対象が分かる再開処理を別途実装 |
| 既に対象 build が審査待ち/審査中 | 同じ提出の存在を成功条件として確認。取り消しや別 build への置換を行わない |
| 証明書/profile 期限切れ | 更新して Secrets 差し替え。既存証明書一括失効は不要 |
| 契約承諾/API 権限不足 | 必要な初回設定を明示して停止 |

同じ run の再実行では決定済み番号を維持する。Apple に upload 済みなら再 build/upload を省く。
未 upload の再 build なら最終 IPA hash を保存し直し、upload 結果不明の状態と区別する。
GitHub の Re-run と、新規 upload と、既存 build の submit は区別する。
既存 build を API で見つけただけではソースが同じと証明できないため、
source SHA/IPA hash と対応する receipt がないものは自動採用しない。

## 証跡と導入時の検証

receipt に source SHA、version/build、IPA hash、App Store build ID、
version ID、submission ID、公開方式、確認した状態、CI run URL を残す。
Job Summary と Artifact に保存し、必要なら後で PR によりリポジトリへ取り込む。
秘密鍵、JWT、認証付きレスポンス、審査連絡先は Artifact に含めない。

初回導入の完了条件:

- Secrets なしで入力検証と状態判定のテストが実行できる。
- 不正タグ/SHA、対象 CI 未完了、profile 不一致、番号衝突を配信前に検出する。
- クリーンな hosted macOS runner で署名 IPA を作成し、API キーだけで upload できる。
- テスト配信/アップロード成功と App Store 審査提出成功を別々に確認する。
- 途中成功後の再実行で同じ IPA を再 upload せず、別の最新 build も選ばない。
- 最初の production 提出には次の実リリースを使う。動作確認だけで新バージョンを公開しない。
- 実装 PR の提出前には AGENTS.md 指定の Android 全件 E2E を実行し、
  コマンド・端末/API・全ファイル・成否・任意 GPS モードの有無を PR 本文に記載する。

調査段階では API キー・証明書の発行、Secrets 登録、workflow 実行、
新規 upload/審査提出、GitHub の保護設定変更を行っていない。
未確認の中心はクリーン runner での署名、固定版 fastlane の ARGUS メタデータ更新、
途中失敗時の再開、現在の Apple アカウントの API 利用可否である。

## 実装順序

1. Android と同じタグ解析、receipt/既存状態の確認と iOS 専用採番を実装し、外部書き込みなしで検証する。
2. 証明書復元と IPA 作成を追加し、終了処理と Artifact の内容を確認する。
3. 初回認証設定後に upload モードで API キー経由の配信を検証する。
4. deliver の更新情報登録・submit と途中再開を追加する。
5. 実装の CI と初回設定の確認後、次の実リリースの `vX.Y.Z` タグ push で Android/iOS を起動し、
   iOS の審査待ちまで確認する。承認後の自動公開は Apple 側で行う。
   両 OS の配信結果は別々に記録し、片方の失敗で他方の成功を取り消さない。
