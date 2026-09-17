# iOS CD の運用と設定

Android と同じ `vX.Y.Z` タグ push から、main 反映と5つの必須 CI 成功を確認して署名 IPA を作成する。
完成 IPA の検証、App Store Connect への upload、審査提出を行い、Apple の承認後に自動公開する。
段階的公開なし・評価維持。下書きで止める構成ではない。
タグ作成者を制限しているため、通常フローに GitHub の追加承認はない。

## リリース手順と到達点

1. main へ取り込む PR に `docs/app_store/releases/<version>/ja-JP.txt`（両 OS 共通、500文字以内）と
   `review_notes.md`（3900文字以内）を含める。
2. 配信対象の main コミットの5つの必須 CI 成功を確認してから `vX.Y.Z` タグを push する。
3. iOS Release が API の現在状態と未使用番号を確認し、IPA を生成・検証して upload する。
4. deliver はまずメタデータと自動公開設定だけを保存する。対象 build を紐付け、API で
   version/build・自動公開方式・段階的公開なし・日本語更新内容・審査メモ・連絡先を確認してから審査へ提出する。
5. Job Summary / receipt の submission ID と状態を確認する。
   `WAITING_FOR_REVIEW` / `IN_REVIEW` は審査待ち・審査中であり、公開済みではない。
   公開は Apple の承認後に進む。CI は審査完了まで何日も待機しない。

Apple は API の審査提出と、自動公開オプションを提供している。
審査が翌日・翌々日に終わることは保証されず、却下・契約更新・追加情報要求などは担当者の対応が必要。

- [Apple: App Store Connect API](https://developer.apple.com/app-store-connect/api/)
- [Apple: 公開オプション](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/)
- [fastlane: deliver](https://docs.fastlane.tools/actions/deliver/)

## 設定

Repository Variables は `IOS_TEAM_ID=DLJC9VB2SL` と `IOS_RELEASE_BUILD_NUMBER_OFFSET=1010`。
build 番号は `github.run_number + offset`、version はタグから解決する。
固定値は App ID `6781527103`、Bundle ID `com.argus.orienteering`。

Environment `ios-release` の Secrets:

| 名前 | 用途 |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | 配布証明書と秘密鍵 |
| `IOS_DISTRIBUTION_P12_PASSWORD` | p12 password |
| `IOS_APPSTORE_PROFILE_BASE64` | App Store provisioning profile |
| `ASC_KEY_ID` | API キー ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_PRIVATE_KEY_BASE64` | API 秘密鍵 |

すべて登録済み。秘密の値は文書・Git・Artifact に保存しない。
API キーは App Manager の Team キーで、アカウント内の全アプリに作用する。
コードで ARGUS の App ID / Bundle ID を照合するが、キーそのものの権限を単一アプリへ縮小するものではない。
API キーのバックアップはこの Mac の `~/.appstoreconnect/private_keys/` に所有者専用権限で保存済み。
配布証明書は2027-06-15 UTC、profile は2027-06-18 UTCに期限が来るため、期限前に差し替える。

Flutter 3.44.1 / Xcode 26.6 / Ruby 3.3 / fastlane 2.240.1 / CocoaPods 1.16.2 を指定する。
Actions は commit SHA、Ruby の依存は Gemfile.lock で固定する。
API 鍵は API を操作するステップのみ、署名秘密鍵は復元ステップのみに渡す。
署名用の一時 keychain と profile は終了時に削除する。

## 検証と復旧

- タグ形式と checkout SHA、main の祖先、同じ SHA の5つの必須チェックを検証する。
  さらに所定 workflow の main push 実行が成功したことを照合し、名前だけ同じ別のチェックを採用しない。
- IPA の署名・version/build・Team/Bundle ID・最低 iOS・Background Modes・Time Sensitive entitlement・暗号化宣言を検証する。
- App ID 単位の concurrency で直列化し、進行中の配信をキャンセルしない。
- 同じ Actions run の以前の attempt から receipt を復元し、SHA・番号・App ID・Team・run ID を照合する。
- 既知の Apple build ID、または upload の成功応答を保存した receipt がある場合だけ、既存 Apple build を再利用する。
  ローカル IPA が完成しただけの `built` や、結果不明の `uploading` から未知の Apple build を採用しない。
- Apple の処理待ちは最大40分。未処理で停止した場合は証跡を確認して同じ run を再実行する。
- 下書き再開では、自分の version/build だけが含まれることと、公開設定・審査内容が期待どおりであることを
  最終提出**前**に確認する。設定が変わっていたら提出せず停止する。
- 提出済みなら同じ build / submission / 自動公開方式を確認し、重複提出しない。
- 別versionの審査・下書きは自動取消・削除しない。既存タグは移動・削除しない。
- upload の結果が不明で receipt に成功応答も Apple build ID もない場合は、自動復旧せず担当者が証跡を確認する。
  App Store Connect はリモート IPA の SHA-256 をこの経路で照合できないため、番号の一致だけを信用しない。

## テストの言語

アプリと E2E は Dart / Flutter。
Ruby は fastlane と同じ言語で upload・審査提出・再実行を検証する。
Python は両 OS の共通 gate、署名、配信証跡、Google Play API と既存 CI 補助処理を検証する。
API の代替モデルによる回帰テストは、実ストアでの upload 成功を保証するものではない。

クリーンな GitHub-hosted runner からの本番 upload・審査提出は次の実リリースで確認する。
現在の0.8.0を再提出するためのタグ push やストア変更は、この改修では行わない。
[配信セキュリティ](mobile_release_security.md)、[導入時の調査](ios_release_automation.md)、
[macOS の Android E2E](android_local_e2e.md)も参照。
