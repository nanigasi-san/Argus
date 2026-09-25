# 利用方法選択画面（B2）デザインQA

- Source visual truth: `/Users/kaitoyamada/.codex/generated_images/01a0ce70-5597-7141-b15c-5f4de3f8c2c1/exec-765408af-8643-40af-9645-af864b03d4c4.png` の右上 B2。画像全体は1024×1536pxで、B2にはiPhone枠が含まれる。
- Implementation screenshot: `build/integration_test/screenshots/usage-mode-selection.png`。Android Emulator API 36、アプリ領域411×891 logical px、PNG 1440×3120px（約3.5倍密度）。E2Eの `usage-mode-selection` で取得する。端末枠・OS chromeを除き、アプリ所有領域を比較した。
- iPhone実機の追加確認: `/tmp/argus-usage-mode-iphone-verified-20260925.png`（1125×2436px、iOS 26.7）。開発デバッグ用ローカルネットワーク許可ダイアログを閉じた状態で最終画面を確認した。
- State: 初期表示、「スマホで利用」選択済み。「次へ」操作前。B2は短めの端末、実装は縦長端末なので、余白は固定ピクセルではなく画面高に追従する。

## 比較結果

- Typography: 見出しと二択の階層は一致。既存ARGUSのBIZ UDPGothicを使用。初回比較で補足文がB2より太かったため、補足文のみ通常ウェイトへ修正した。
- Spacing/layout: ARGUSロゴ、見出し、二つのラジオ式選択カード、下部「次へ」の順序・配置はB2に沿う。縦長画面のカードとボタン間の余白増は意図したレスポンシブ差。320×568 logical pxのWidgetテストでスクロールと操作を確認。
- Color/tokens: 白地、淡青の選択カード、濃紺の文字を再現。初回比較で「次へ」がB2より灰色寄りだったため、青のアクセント色を修正し、再取得画像で確認した。
- Assets/icons: B2の標準的なスマホ・時計・ラジオアイコンはFlutterのMaterial Iconsを使用。独自の写真・イラスト・ロゴ画像は参照にない。ARGUSはテキストロゴとして再現。
- Copy/content: 二択と「次へ」はB2に一致。B2画像のGARMIN説明は転送方向が曖昧なため、実装では「スマホからGARMINへ境界データを送信します。」と明記した。
- Interaction: 初期選択、選択変更、スマホ→既存HomePage、GARMIN→既存GarminTransferPageをWidgetテスト・Android E2E・iPhone実機UI smokeで確認。接続端末の有無にかかわらず選択画面は表示される。

## 比較履歴

1. 初回のAndroid実装画像とB2を同じ比較入力で確認し、補足文の太さとボタン色をP2と判定。
2. 補足文を通常ウェイトに、ボタンと選択ラジオをARGUS青に修正。
3. 全Android E2E後に同じ viewport/state の画像を再取得し、B2と同じ比較入力で確認。操作を妨げるP0/P1/P2の差分なし。小さなロゴ寸法・画面高に伴う余白差はP3の表現差として許容。

final result: passed
