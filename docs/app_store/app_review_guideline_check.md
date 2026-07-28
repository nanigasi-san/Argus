# Apple App Reviewガイドライン確認

確認日: 2026-07-16

この文書は、ARGUSのiOS権限フロー、バックグラウンド位置情報、バックグラウンド警告音、通知、プライバシー表示をApple公式文書と照合した結果です。審査通過を保証するものではありませんが、コード上の既知の不整合は解消しています。

## 確認結果

| 確認対象 | 判定 | ARGUSの対応 |
| --- | --- | --- |
| HIG Privacy: 許可前画面 | 適合 | iOSは「続ける」の単一ボタンだけを表示し、戻る・スワイプ・キャンセル・追加リンクを表示しない。「続ける」がiOSの許可画面を開くことも明記する。 |
| App Review Guidelines 5.1.5: Location Services | 適合 | 位置情報はユーザーが開始する競技エリア監視に直接使用する。使用中許可から常時許可へ進み、用途文言に画面ロック中・他アプリ使用中の離脱検知を明記する。拒否後は設定を自動表示しない。 |
| Core Location background updates | 適合 | `UIBackgroundModes=location`、`allowBackgroundLocationUpdates=true`、背景位置情報インジケータを使用し、監視開始・停止に合わせて位置ストリームを開始・停止する。 |
| App Review Guidelines 2.5.4: Background Services | 適合 | `location` は監視中だけ、`audio` は警告音またはユーザーが開始した警告音テストの再生中だけ使用する。無音再生による延命は行わない。 |
| AVFoundation background audio | 適合 | `AVAudioSession.Category.playback` と `AVAudioPlayer` を実際の警告音再生に使用し、停止時にAudio Sessionを非アクティブ化する。割り込み開始・終了も処理する。 |
| App Review Guidelines 4.5.4: Notifications | 適合 | 通知権限は推奨するが、監視開始の必須条件にはしていない。Critical Alertsは使わず、Time Sensitive通知を競技エリア離脱警告だけに使う。 |
| App Review Guidelines 5.1.1: Privacy Policy | 適合（Connect要確認） | アプリ設定からプライバシーポリシーを開ける。公開URLはHTTP 200で応答し、位置情報・カメラ・GeoJSONの端末内処理、非送信、保持、問い合わせ先を記載する。 |
| App Privacy Details | 適合（Connect要確認） | 位置情報は端末上だけで処理し、開発者サーバーへ送信しない。Appleの定義では端末内だけの処理は「収集」に該当しないが、組み込みSDKを含む実態とApp Store Connect回答を提出直前に一致させる。 |
| Review completeness | 準備済み（添付要） | 日英App Review Notes、操作手順、1242 x 2688スクリーンショット、実機録画手順を用意した。Release ArchiveとApp Store IPAも警告なしで生成済み。 |

## 提出前に人手で完了する項目

1. App Store ConnectのPrivacy Policy URLへ `https://argus-lp.vercel.app/privacy.html` を設定し、公開状態を再確認する。
2. App Privacy回答を、位置情報を含むユーザーデータは端末内処理のみで開発者・第三者が収集しない実装と一致させる。
3. `app_review_notes.md` の日英Notesを貼り付け、権限フローと警告音テストの実機録画を添付する。
4. 審査担当者が機能を確認できるよう、テスト用GeoJSONまたはQRと、その読み込み手順をReview Notesまたは添付資料で提供する。
5. 実機で、拒否後の非自動遷移、常時位置情報、画面ロック中の監視、ホーム画面での警告音継続、停止操作を録画する。
6. 配布用Archiveの署名済みentitlementsに `com.apple.developer.usernotifications.time-sensitive` が含まれ、Info.plistに `audio` と `location` が残っていることを確認する。

## 参照したApple公式文書

- [Human Interface Guidelines: Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Requesting authorization to use location services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
- [allowsBackgroundLocationUpdates](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)
- [Configuring your app for media playback](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Time Sensitive notifications](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive)
