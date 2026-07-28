# App Review再提出 引き継ぎログ（2026-07-16）

## 現在地

- Appleへの再提出操作は、実機録画を後で行うため中断した。
- 今回の操作ではIPAのアップロード、App Review Notesの更新、審査提出を行っていない。
- App Store ConnectはApple Accountのサインイン画面まで開いた。URLに `authResult=FAILED` が表示され、サインイン完了は確認できていない。
- 再開時はApp Store Connectへサインインし、ARGUSの現在の提出状態とbuild `1007` のアップロード有無を最初に確認する。既に存在する場合は重複アップロードしない。
- 最終の「審査に提出」操作は未実行。

## 再提出用成果物

- Version / build: `0.5.0 (1007)`
- Bundle ID: `com.argus.orienteering`
- IPA: `build/ios/ipa/ARGUS.ipa`
- IPA SHA-256: `8f00391dd660ab62f23033fd0a6e9a1d4ed379426e4d7dd457767fc985f476cf`
- Git branch: `gati-ios-version`
- 作業開始時HEAD: `46d52fde4eafec024a3f2dd34af055ab5cb22b7e`
- 変更は未コミット。再開時も既存差分を保持すること。

## 完了済みの検証

- `flutter analyze`: 成功、指摘0件
- Flutter unit/widget tests: 336件成功
- `flutter test --coverage`: 100.0%（2703/2703）
- iPhone 11 Pro Max Simulator（iOS 26.5）Debug build: 成功
- RunnerTests: 4件成功
- iOS UI smoke: 5フロー成功
- Release Archive / App Store IPA: 作成成功、App Store署名、`get-task-allow=false`
- IPA内の `UIBackgroundModes`: `audio` / `location` を確認
- Time Sensitive Notifications entitlementと更新済み位置情報用途文言を確認
- Launch ImageのApp Settings Validation警告を修正し、再ビルドで警告なしを確認

詳細は `docs/ios_release.md` と `docs/app_store/app_review_guideline_check.md` を参照する。

## iPhoneで残っている作業

1. アプリを削除して再インストールし、位置情報権限を未決定へ戻す。
2. iOS説明画面が「続ける」だけで、戻る・スワイプ終了できないことを録画する。
3. 位置情報を拒否しても設定アプリへ自動遷移しないことを録画する。
4. 権限カードの「アプリ設定を開く」を押した場合だけ設定アプリが開くことを録画する。
5. 常時位置情報を許可し、小さなテスト用GeoJSONで監視を開始する。
6. ホーム画面または画面ロック中も監視が継続し、エリア外で警告音が鳴ることを録画する。
7. 「設定」→「警告音をテスト」→ホーム画面→ARGUSへ復帰→「テストを停止」を録画する。
8. 録画ファイル名と確認結果を `docs/ios_release.md` のリリース証跡へ追記する。

## App Store Connect再開手順

1. `https://appstoreconnect.apple.com/apps` へサインインする。
2. ARGUSのiOSバージョン画面を開き、現在の審査状態を確認する。
3. build `0.5.0 (1007)` が選択可能か確認する。
4. buildが未アップロードの場合だけ `build/ios/ipa/ARGUS.ipa` をTransporterでアップロードし、処理完了を待つ。
5. App Review InformationのNotesを `docs/app_store/app_review_notes.md` の内容へ更新する。
6. 実機録画とテスト用GeoJSON/QRを、App Reviewが確認できる形で添付または案内する。
7. Privacy Policy URLが `https://argus-lp.vercel.app/privacy.html` であることと、App Privacy回答が実装に一致することを確認する。
8. 保存後、入力内容と選択buildを最終確認する。
9. ユーザー確認を得てから「審査に提出」を実行する。

## 提出前の重点確認

- iOS権限説明画面に、許可前に設定画面へ誘導する文言やキャンセル導線がないこと。
- 拒否後に設定アプリを自動表示しないこと。
- `location` / `audio` のBackground Modesと用途説明が、実機動作およびReview Notesと一致すること。
- 警告音テストは音声だけで、通知・バイブレーションを発生させないこと。
- 審査担当者が警告音テストとバックグラウンド監視を再現できる手順・テストデータがあること。

## 再提出完了（2026-07-24）

- App Store Connectへ再提出済み。
- 提出状態: `審査待ち`
- Version / build: `0.5.0 (1007)`
- App Review submission ID: `5062da36-3c20-45ee-abcd-775d9e5f70ba`
- 提出詳細:
  - `https://appstoreconnect.apple.com/apps/6781527103/distribution/reviewsubmissions/details/5062da36-3c20-45ee-abcd-775d9e5f70ba`
- App Review Notes:
  - 5.1.1(iv)のiOS権限フロー修正
  - 位置情報拒否後に設定アプリを自動表示しないこと
  - background `location` / `audio` の必要性と再現手順
  - 警告音テスト手順
  - 実機録画のタイムスタンプ
- App Review添付:
  - `docs/app_store/review_recordings/ARGUS-App-Review-Recordings.mp4`
  - 元の実機録画2本を、古い録画を先頭にして撮影順に連結
  - 再生時間: `101.02666666666667`秒
  - 解像度: `1126 × 2436`
  - 映像: `HEVC`
  - 音声: `MPEG-4 AAC`（音声トラック1本を確認）
  - SHA-256: `129d4b5227763515d1ddcd8f6f70766608914ffed558169e1fddc0cde435a8c1`
- 元録画:
  - `01-background-monitoring-and-audio.mp4`
  - `02-permission-flow-and-background-verification.mp4`
- App Store Connect上で、添付動画のアップロード完了、審査メモ保存、build `1007` の「審査準備完了」を確認してから再提出した。
