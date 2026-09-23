# 検証記録 — 2026-09-23

| 項目 | 実行・端末 | 結果 |
| --- | --- | --- |
| Android APK / unit / lint | `./gradlew :app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`、JDK 21、Gradle 8.14、Garmin Companion SDK 2.4.0 | 成功。単体テスト6件、失敗0。Lintエラー0 |
| Android実機インストール・起動 | ADB、Xiaomi 14T Pro / 2407FPN8ER / API 36、Garmin Connect 5.29 | インストール成功。Kotlin runtime不足によるACK変換クラッシュを再現後、stdlib 1.9.24の明示依存で解消。以後crash logなし |
| Garmin Connect連携 | 上記スマホ / WIRELESS | SDK準備完了、`ForeAthlete 55 · CONNECTED`、対象PoC導入済み、ACK受信登録を確認 |
| Garmin通常ビルド | Connect IQ SDK 9.2.0、`fr55` | 成功。実機転送用PRGのSHA-256 `8a4af667de1d971699fb0f9fd7862d028987c850c02be517f72155581b18db42` |
| Garmin単体テスト | `monkeydo garmin/bin/LinkPoc-test.prg fr55 -t` | 4件すべてPASS。512 / 1024 / 2048 B、動的文字列、Number / Long、Data Field戻り値を含む |
| 時計へのUSB転送 | Mac / `GARMIN`、ForeAthlete 55 `006-B4033-00`、firmware 11.03 / Connect IQ 6.0.2 | 転送成功。コピー元・時計側PRGのSHA-256一致。macOSのAppleDouble sidecarを削除し安全にeject |
| Data Field実機起動 | ForeAthlete 55 / 通常Run | 当初の `value` Symbol Not Foundを実機ログで特定・修正。`READY`、保存後のサイズ表示を確認 |
| 失敗系の実機診断 | ForeAthlete 55の `CIQ_LOG.YML` / `.BAK` | 1文字ずつの変換でWatchdog、全体`toCharArray()`でOut Of Memory、2回checksumで2KB時Watchdogを再現。32文字chunkと候補Storageの1回検証へ修正 |
| Run停止中の実機送信・保存・ACK | 512 / 1024 / 2048 B | **すべてPASS**。時計のバックグラウンド受信、候補保存、読み戻しchecksum、正式保存、スマホACK照合を確認。実測 15,542 / 16,524 / 24,740 ms |
| 古いACK・再送 | 各サイズの実機送信 | 古い`requestId`のACKを拒否し、1.5秒後に同じ`requestId`で1回再送して各サイズPASS |
| Run開始・再起動後の永続保持 | 最終保存 2048 B | 転送後にRunを開始して `2048 B OK`。時計再起動後、再送なしでも `2048 B OK` を確認 |
| ARGUS単体テスト / 静的解析 | `flutter test` / `flutter analyze` | 353件すべてPASS。解析エラーなし |
| ARGUS全件E2E | `integration_test/` | 今回はPR未作成・本体未変更のため未実施。PR提出前には全件実行が必要 |

Phase 0のAndroid → ForeAthlete 55経路は、Run開始前のバックグラウンド転送から
保存完了ACK、Run開始・時計再起動後の読み出しまで成立した。
iOS経路、Phase 1の単独監視、Phase 2の既存Flutter ARGUS統合は今回のPoC対象外。
PRG・APK・開発鍵・回収した端末ログはビルド／ローカル成果物としてGitに含めない。
