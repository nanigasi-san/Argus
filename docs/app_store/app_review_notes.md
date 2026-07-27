# App Review Notes

提出対象: iOS `0.6.0 (1008)`

## 日本語

ARGUSは、利用者が読み込んだGeoJSON競技エリアを監視するアプリです。利用者が明示的に監視を開始した後だけバックグラウンド位置情報を使用し、画面ロック中や他のアプリ使用中でもエリア外への離脱を検知します。位置情報は端末内でのみ処理し、開発者サーバーへ送信しません。

バックグラウンド音声は、エリア外を検知したときに警告音をループ再生するためだけに使用します。警告音はスヌーズ操作、安全エリアへの復帰、または監視終了で停止します。

警告音の確認手順:

1. 右上メニューから「設定」を開きます。
2. 「アラーム音量」の下にある「警告音をテスト」を押します。
3. iPhoneのホーム画面へ移動しても警告音が継続することを確認できます。
4. ARGUSへ戻り「テストを停止」を押すと停止します。

位置情報を拒否した場合、ARGUSは設定アプリを自動的に開きません。ユーザーが監視機能を使うために権限を変更するときだけ、権限カードの「アプリ設定を開く」を明示的に押します。

## English

ARGUS monitors a GeoJSON competition area selected by the user. Background location starts only after the user explicitly starts monitoring. It is required to detect leaving the competition area while the screen is locked or another app is in use. Location data is processed only on the device and is never sent to the developer's server.

Background audio is used only to loop the warning sound after ARGUS detects that the user has left the competition area. The sound stops when the user snoozes the alert, returns to the safe area, or stops monitoring.

To verify background audio:

1. Open Settings from the top-right menu.
2. Tap “警告音をテスト” below Alarm Volume.
3. Return to the iPhone Home Screen; the warning sound continues in the background.
4. Return to ARGUS and tap “テストを停止” to stop it.

If location permission is denied, ARGUS does not open Settings automatically. The Settings app opens only after the user explicitly taps “アプリ設定を開く” while trying to enable monitoring.

## 提出時の添付物

- `review_recordings/ARGUS-App-Review-Recordings.mp4`
  - `00:00–00:42`: GeoJSON読込、監視開始、実際のエリア外判定、通知・警告音、アプリが前面でない状態での継続
  - `00:42–01:41`: iOS用事前説明画面（「続ける」のみ）、権限設定、実際の監視・エリア外判定・通知・警告
- 上記MP4は元の実機録画2本を撮影順に連結したもので、内容のカットや加工は行っていない。
- 審査用テストデータ:
  - `review_test_area.geojson`
  - `../../scripts/output/qr.png`
