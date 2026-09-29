# リファクタリングと検証記録（2026-09-29）

対象ブランチ: `refactor-maintainability-guides`。開始時にmainで`git pull --ff-only`を実行し、未コミット変更がないことを確認した。

## 変更と守る契約

| 対象 | 変更 | 既存仕様・確認した境界 |
| --- | --- | --- |
| GeoModel | 外周抽出・座標検証を分離、ポリゴン一覧を変更不可のコピーに | Polygon/MultiPolygon、外周のみ、自動閉鎖、3点未満の無視、高度の無視を維持 |
| 入力エラー | 不正な配列・型・非有限値・範囲外座標をFormatExceptionへ | 短い座標によるRangeError、キャスト失敗、無限値の混入を防ぐ |
| GARMIN変換 | サイズ定数・表示名生成を整理しchecksumの二重計算を除去 | AGW1、100頂点・2048B、UTF-8表示名48B、12時間の開始期限を維持 |
| QR | gjz1のSHA-256を小文字へ正規化 | 形式検査で許可される大文字ハッシュを正しく照合。改ざん検出は維持 |
| 時計検索 | 検索ごとの世代番号で古い応答を無視 | 古い成功・失敗が新しい検索結果を上書きしない。選択済み時計を黙って変更しない |
| 転送候補 | ファイルとQR読込後の画面更新を共通化 | 前の転送の通知警告を新しい候補に持ち越さない |
| UI | 共通色、説明文字、行間、ボタン最小高さ・折返し | 操作順序と監視閾値を維持。320×568・文字倍率2倍で操作可能 |
| 文書 | 仕様の集約、現行構成図、初心者ガイド、履歴の時点明記 | [全資料の確認記録](documentation_audit.md)を参照 |

GeoJSONの穴をスマホが外周として扱う既存仕様は変更していない。対応形式を変更する場合は別途仕様とテストの変更が必要。

## ローカル検証

| コマンド・確認 | 結果 |
| --- | --- |
| 変更前 `flutter test --reporter compact` | 382テスト成功 |
| `flutter analyze` | 問題なし |
| `flutter test --coverage --reporter compact` | 392テスト成功 |
| `python scripts/parse_coverage.py` | 3558 / 3611行、98.5%（ignore対象を除く行カバレッジ） |
| `./scripts/run_android_ui_checks.ps1 -CaptureScreenshots` | 下記の全3ファイル成功 |
| `actionlint` 1.7.12 | 全workflowの構文・式検査成功 |
| ローカル文書リンク | 全44 Markdownの143参照先と1アンカーを確認、欠落なし |
| Mermaid構文検査 | 全Markdownの11図成功（Mermaidのparse APIで確認） |
| スクリーンショット確認 | 選択画面、GARMIN送信前後を目視。ガイドに実画像5枚とGPT Image説明図2枚を保存 |
| Pythonスクリプトの全52テスト（Windows） | 50成功、POSIX watchdogの2件はWindows非対応のため失敗。下記参照 |

Android端末: `Medium_Phone_API_36.0` / `emulator-5554` / `sdk_gphone64_x86_64` / API 36。Flutter 3.44.2 / Dart 3.12.2。テスト用に起動したエミュレーターは完了後に終了した。

| 検出ファイル | 通常シナリオ | 結果 |
| --- | ---: | --- |
| `integration_test/compass_navigation_test.dart` | 1 | 成功 |
| `integration_test/core_monitoring_e2e_test.dart` | 8 | 成功 |
| `integration_test/ui_smoke_test.dart` | 7 | 成功 |

`e2e/`は未作成。`SIMULATOR_GPS=true`は実行していない。位置・権限・通知・時計通信はテスト実装を使うため、実GPS・OSの許可ダイアログ・実通知音・実時計通信の動作確認とは区別する。

Pythonは`python -m unittest discover -s scripts -p 'test_*.py'`で全件実行した。`test_run_with_timeout.py`の`test_timeout_stops_descendants_holding_output_open`と`test_signal_stops_child`はPOSIXの`sleep`・プロセスグループ・SIGTERMを前提とし、Windowsでは失敗した。このwatchdogはLinux/macOS CI用で、今回その実装は変更していない。

## CIの時間調査と変更

変更前の同一mainの実行ログを確認した。

| 実行 | 実測 | 観察 |
| --- | --- | --- |
| [Android E2E / 36558512126](https://github.com/nanigasi-san/Argus/actions/runs/36558512126) | job 599秒、E2E step 513秒、assembleDebug 319.6秒 | Gradleキャッシュが見つからず、保存に44秒かかった後、別jobとの同一キー競合で保存失敗 |
| [iOS Build / 36558512313](https://github.com/nanigasi-san/Argus/actions/runs/36558512313) | job 577秒、Flutter準備70秒、build/native test 451秒 | Flutter/pubは既にキャッシュあり。CocoaPods等のダウンロードキャッシュはなし |

Androidはワークフロー名と依存設定をキーに含め、SHAごとに成功した依存キャッシュを更新する。iOSはXcode・依存設定ごとにCocoaPods/SwiftPMの取得結果を再利用する。詳細は[CI](ci.md)。

キャッシュがなくても通常の取得・ビルド・全テストを行う。アプリ成果物、テスト結果、AVDの状態、DerivedDataはキャッシュしない。実行対象・起動条件・タイムアウト・必須チェックは変更しない。

初回は新しいキーでキャッシュがなく、保存分だけ遅くなる場合がある。以後のヒット状況、取得・コンパイル・テスト・保存の時間を分けて確認する。runner負荷とFlutter stable/Xcode更新の影響があるため、1回の差を一般的な短縮率とは扱わない。

### このブランチのCI確認

コードコミット`0959f63`に対しAndroid Build/E2E・iOS Build/E2Eを手動起動。結果と再利用時の比較は確認後に追記する。

## 参照

- [Gradle setup actionのキャッシュ設定](https://github.com/gradle/actions/blob/main/docs/setup-gradle.md)
- [GitHub Actions cacheの復元と保存](https://github.com/actions/cache)
- [ガイド画像の出典・最終プロンプト](guides/images/README.md)
