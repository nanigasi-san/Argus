# ARGUS ドキュメント

## 初めて使う

| 目的 | 読むもの |
| --- | --- |
| スマホで範囲を監視する | [スマホ初心者ガイド](guides/phone.md) |
| 時計へ範囲を送りRunで使う | [GARMIN初心者ガイド](guides/garmin.md) |
| 時計を選ぶ・制限を確認する | [対応機種](garmin_supported_devices.md)・[複数機種の評価](garmin_multi_device_assessment.md) |
| スマホ・QR・Garminで使えるGeoJSONを確認する | [画像と対応条件の比較](geojson_validation.md)・[形状ごとの検証結果](geojson_validation_report.md) |
| データの扱いを確認する | [プライバシーポリシー](../privacy.md) |

## 開発・テスト

| 目的 | 読むもの |
| --- | --- |
| 実装の全体像と処理順序 | [構成図・クラス図・フロー](architecture.md) |
| 現行の機能仕様 | [仕様書](spec.md) |
| QRと時計のデータ形式 | [QR](geojson_to_qr.md)・[GARMIN転送](garmin_data_format.md) |
| テストを実行する | [テスト方針](tests.md)・[E2E実行手順](../integration_test/README.md)・[シナリオ図](e2e_test_flows.md) |
| 環境を準備する | [Android E2E](android_local_e2e.md)・[MacBook iOS](macbook_ios_setup.md) |
| CIの役割・キャッシュ | [CI](ci.md)・[今回の改善と検証](refactor_validation.md) |
| 時計側を開発する | [Data Field README](../garmin/argus-data-field/README.md) |
| コードを整理する | [リファクタリング方針](refactoring.md) |

## リリース・過去の記録

- [Androidリリース](release.md)
- [iOSリリース運用](ios_release_cd.md)・[実機チェック](ios_release.md)・[自動化の設計](ios_release_automation.md)
- [配信セキュリティ](mobile_release_security.md)
- [Google Play位置情報申告](play_console_background_location_declaration.md)
- [App Store審査確認記録](app_store/app_review_guideline_check.md)
- [iOS E2E調査記録](ios_e2e_investigation.md)
- [8月時点の改善計画](post_release_improvement_plan.md)
- [全Markdownの確認記録](documentation_audit.md)

日付・バージョンを持つ審査提出資料は当時の記録として保存する。現在のバージョンは`pubspec.yaml`、CIは`.github/workflows/`、機能の詳細は実装と回帰テストを正とする。公開ストアや外部の設定を変更したことは、リポジトリ文書の更新だけでは意味しない。
