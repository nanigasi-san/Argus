# ガイド画像の出典と生成記録

作成日: 2026-09-29。生成ツール: Codex内蔵GPT Image（imagegen）。

## 保存した画像

| ファイル | 種別・参照元 |
| --- | --- |
| phone-quickstart.png | GPT Imageの説明図。usage-mode-selection.pngとhome-permission-card.pngを参照 |
| garmin-quickstart.png | GPT Imageの説明図。garmin-transfer-before.pngとgarmin-transfer-after.pngを参照。時計は模式図 |
| usage-mode-selection.png | Android E2Eの同名スクリーンショット |
| home-permission-card.png | Android E2Eの同名スクリーンショット |
| compass-forward.png | Android E2Eの同名スクリーンショット |
| garmin-transfer-before.png | Android E2Eのgarmin-transfer-option1-before.png |
| garmin-transfer-after.png | Android E2Eのgarmin-transfer-option1-after.png |

保存先はすべてこのディレクトリ（`docs/guides/images/`）。生成画像は1536×1024、実スクリーンショットは1080×2400。生成時の参照はローカルの`build/integration_test/screenshots/`にあった同一画面。ここに保存した実スクリーンショットは今回の全E2Eで再取得したもの。

取得コマンド: `./scripts/run_android_ui_checks.ps1 -CaptureScreenshots`。端末はMedium_Phone_API_36.0、API 36、x86_64、Flutter 3.44.2。位置・権限・時計接続はテスト実装であり、実機通信の証跡ではない。

生成画像は手順を要約したイラストで、実画面と装飾・余白・端末枠が異なる。日本語、ボタン名、手順、余白を目視確認した。スマホ図のQR風アイコンは操作の記号で、読み取るデータではない。実際の操作名は各ガイドと実スクリーンショットを参照する。

## スマホ図の最終プロンプト

```text
Use case: infographic-diagram. Create a polished Japanese beginner-guide illustration for the ARGUS smartphone app, landscape 1536x1024, white background, navy headings, accessible blue accents, restrained flat editorial style. Reference images are actual app screenshots; use their visual appearance and exact existing labels for two small phone screen illustrations. Three numbered panels left to right: 1 「スマホで利用」 with the selection screen and highlighted phone choice; 2 「位置情報を設定」 with the permission card and callout 「常に許可」; 3 「範囲を読み込んで開始」 with a simple file and QR icon pointing to a phone showing 「スタート待機」 and 「タップで開始」, based on the reference circular blue status. Top title 「スマホではじめる ARGUS」. Bottom small label 「実画面を参考にした操作イメージ」. Clearly show step arrows. Keep Japanese text crisp and minimal. Do not invent additional app buttons, maps, login screens or readable QR codes. No photos, no marketing slogans, no safety guarantee.
```

## GARMIN図の最終プロンプト

```text
Use case: infographic-diagram. Create a Japanese beginner-guide illustration for ARGUS GARMIN transfer, landscape 1536x1024, white background, navy headings and blue accents matching the reference app screens. Three numbered panels left to right: 1 「範囲と時計を選ぶ」 showing a phone based on reference 1 with 「境界データ」, 「ForeAthlete 55」 and blue 「GARMINに送信」 button; 2 「転送完了を確認」 showing a phone based on reference 2 with green check and exact heading 「GARMINへ転送しました」, short sublabel 「保存・照合済み」; 3 「時計でRunを開始」 showing a simplified round sports watch with black face, file label 「argus.geojson」 and large white 「IN」. Watch is a conceptual illustration, not an actual screenshot; no maps, navigation route, or invented watch menu. Arrows connect steps. Top title 「GARMINではじめる ARGUS」. Bottom note 「実画面を参考にした操作イメージ・時計は模式図」. Crisp Japanese text, minimal explanatory text, clear generous margins, no marketing slogans. The flow only claims local saved transfer then monitoring after starting Run, not that sending itself starts monitoring. Use the attached images as visual references, preserve existing button labels, no additional controls.
```

