# ドキュメント確認記録（2026-09-29）

作業開始時のGit追跡Markdown全37ファイルを読み、実装・テスト・workflowと照合した。加えて公開用HTML、バージョン別更新文、今回追加した資料を確認した。外部ストアの最新状態、法令適合性、全機種の実機動作を再認定する監査ではない。

## 既存Markdown

| ファイル | 確認・更新内容 |
| --- | --- |
| `.cursor/commands/ci.md` | 解析・全unit・coverageの実行指示は現行スクリプトと一致 |
| `.cursor/commands/docs.md` | 文書更新の作業用指示。仕様・テストへの参照は有効 |
| `AGENTS.md` | pull・全E2E・エミュレーター終了・commit/pushの規則を確認し実施 |
| `README.md` | 初心者ガイド・構成図・文書索引・開発コマンドへ案内。Android配信先をproductionへ訂正 |
| `design-qa.md` | 過去の端末・デザイン比較と今回の文字拡大/スクリーンショット確認を区別 |
| `docs/android_local_e2e.md` | Windowsの全件コマンドとエミュレーター後片付けを追加。Mac構築値は日付付きで保持 |
| `docs/app_store/2026-07-16_resubmission_handoff.md` | 当時の再提出記録と現行手順を区別 |
| `docs/app_store/2026-09-18_ios_0.8.0_release.md` | 版・SHA付きの配信証跡として保持。現行版の説明へ転用しない |
| `docs/app_store/2026-09-24_ios_0.8.2_release.md` | 版・SHA・CI・審査状態の記録として保持 |
| `docs/app_store/app_review_guideline_check.md` | 過去の審査確認であることを明記。現行GARMINデータ取扱への参照を追加 |
| `docs/app_store/app_review_notes.md` | 0.6.0提出用の過去資料と明記し、版別資料へ案内 |
| `docs/app_store/releases/0.8.1/review_notes.md` | 0.8.1提出用の記録。実装に存在しない手順の追加なし |
| `docs/app_store/releases/0.8.2/review_notes.md` | 地図・経路ガイドという不正確な説明を範囲監視へ訂正。外部提出内容を変更したわけではないことを明記 |
| `docs/app_store/screenshots/ja-JP/iphone-6.5/README.md` | 既存審査画像3枚のファイルと用途を確認。今回のAndroid初心者画像とは分離 |
| `docs/ci.md` | Gradleキー競合対策・iOS取得キャッシュと実際のSimulator指定を反映 |
| `docs/e2e_test_flows.md` | 通常16シナリオへ更新。GARMIN転送・利用端末選択の図を追加、C7初期値を0mへ訂正 |
| `docs/garmin_data_format.md` | 座標の検証、通信オフの報告と未記録条件を反映。AGW1/ACK/寿命をコードと照合 |
| `docs/garmin_multi_device_assessment.md` | 追加前の調査記録という既存注記を確認。現在のmanifestと対応機種表への案内を維持 |
| `docs/garmin_supported_devices.md` | 「時計を変更」の現行ラベルと初心者ガイドを反映。未検証機種を保証しない記述を維持 |
| `docs/geojson_to_qr.md` | アプリagz1とAPI既定gjz1、実際のデモI/O、不透明PNG、未実装CLI機能を整理 |
| `docs/ios_e2e_investigation.md` | 調査当時の問題と現在実装済みの起動・ログ取得方法を区別 |
| `docs/ios_release.md` | 固定の古いブランチ/build番号を除き、iOS通知音と手動確認項目を更新 |
| `docs/ios_release_automation.md` | 不採用のGitHub CD設計という既存注記・現行運用へのリンクを確認 |
| `docs/ios_release_cd.md` | Macでの署名・提出手順、対象mainの5必須CI、再upload回避を現行補助処理と照合 |
| `docs/macbook_ios_setup.md` | ブランチを利用者指定へ変更、追跡済みPodfile.lockと単一ビルド/native全テスト手順を反映 |
| `docs/mobile_release_security.md` | 日付付き設定監査と明記し、現行Androidタグ・iOS Mac運用へ案内 |
| `docs/play_console_background_location_declaration.md` | 配信チェックの固定closed testingを現行の対象トラックへ訂正 |
| `docs/post_release_improvement_plan.md` | 8月時点の338テスト・100%と現状を区別。今回対応した項目と残る仕様判断を追記 |
| `docs/refactoring.md` | コード例と現行APIの区別、非同期終了処理の制約、壊れたコードフェンスを修正 |
| `docs/release.md` | AndroidタグでiOSも自動配信するという古い説明を訂正 |
| `docs/spec.md` | 存在しないクラス図を現行構成図へ集約。UI・入力検証・一時ファイル・iOS音・E2Eの記述を更新 |
| `docs/tests.md` | GARMIN・端末選択のE2E、coverage目標と実際のCIゲートを区別 |
| `garmin/argus-data-field/README.md` | 時計の開発・検証手順を確認し初心者ガイドと構成図へ案内 |
| `integration_test/README.md` | 16シナリオ、スクリーンショット一覧、集約実行とWindowsのsuite別実行を反映 |
| `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md` | ロゴ3画像とworkspaceの更新手順を確認 |
| `privacy.md` | Run一時停止・開始期限・時計からの削除条件を実装に合わせ明確化 |
| `spec.md` | 重複仕様を削除しdocs/spec.md・構成図・ガイドへの入口へ変更 |

## その他の文書・画像

| 対象 | 確認・更新内容 |
| --- | --- |
| `docs/index.html` | 4月版の内容を現行privacy.mdと同期。任意GARMIN転送・保存期間・問い合わせ先・正規公開先を反映 |
| `docs/app_store/releases/0.8.1/ja-JP.txt` / `0.8.2/ja-JP.txt` | 過去の配信改善の更新文として保持 |
| `docs/app_store/review_test_area.geojson` | 審査用fixtureとして保持。新機能の一般的な対象地域とはしない |
| `docs/images/e2e/` | 図はテストの説明画像。C7と対応一覧を0m初期値へ再生成し、生成スクリプトも同期 |
| `docs/images/pr-87-mobile-release-overview.png` | 過去PRの図として保持。現行の配信入口はci.md・ios_release_cd.mdを参照 |
| `docs/guides/` | スマホ・GARMINの初心者向けMD、実画像5枚、GPT Image説明図2枚、生成プロンプト・出典を追加 |
| `docs/architecture.md` | 実クラス名・関数群・Durationを使う構成/クラス/シーケンス/寿命図を追加 |
| `docs/README.md` | 利用者・開発・配信・過去記録の索引を追加 |
| `docs/refactor_validation.md` | 今回の差分・全件検証・CI調査結果と制約を記録 |

## 検証方法

- Mermaidのコードブロックを全Markdownから抽出し、Mermaidのparse APIで構文検査。
- ローカルへのMarkdownリンクとHTML画像参照の存在を検査。
- E2Eを全件実行して画面を取得し、選択・転送前・転送後の表示を目視確認。
- リリースや審査の過去の証跡を現在の成功実績として扱わず、日付・対象版を維持。

実行結果とCIリンクは[検証記録](refactor_validation.md)を参照。
