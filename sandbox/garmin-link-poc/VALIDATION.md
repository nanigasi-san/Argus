# 検証記録 — 2026-09-23

| 項目 | 実行・端末 | 結果 |
| --- | --- | --- |
| Android APK / unit / lint | `./build-android.ps1` → `:app:assembleDebug :app:testDebugUnitTest :app:lintDebug`、JDK 21、Gradle 8.14、Garmin Companion SDK 2.4.0 | 成功。単体テスト5件、失敗0。Lintエラー0（翻訳・target SDK・バックアップ設定の警告あり） |
| Android実機インストール・起動 | `./build-android.ps1 -Install -Serial <端末>`、Xiaomi 14T Pro / 2407FPN8ER / API 36 | ADB `Success`、Activity起動 `Status: ok` |
| Garmin Connect連携 | 上記スマホ / WIRELESS | SDK準備完了、ペアリング済み端末1件、`ForeAthlete 55` を検出 |
| 時計の接続・アプリ照会 | 上記スマホ → 55 | 当初 `NOT_CONNECTED`。接続後、対象PoC UUIDが未導入とのコールバックを確認。送信ボタンは無効 |
| Garmin通常ビルド | `./build-watch.ps1`、Connect IQ 9.2.0、`fr55` | 成功。実機転送用 `garmin/bin/LinkPoc.prg` を生成 |
| Garminテストビルド | `./build-watch.ps1 -TestBuild`、`fr55` | 成功。通常ビルドに戻している |
| Garmin単体テスト実行 | `monkeydo.bat <絶対PRGパス> fr55 /t` | **結果未確認**。シミュレーター接続失敗、またはテスト出力が得られず。成功扱いにしない |
| USBドライバー | Garmin公式 `USBDrivers_2312.exe` 内の署名済み `USB_64.msi` | ユーザー指示で導入成功（MSI終了コード0）。対象ID一致をINFで確認。デバイスエラー28 → `Garmin USB GPS`、コード0、`grmnusb` 2.3.1.0へ改善 |
| 時計へのUSB転送 | Windows / Garmin USB `VID_091E&PID_0003` | **未実施**。ドライバー導入後もGarminモードの接続が残り、保存領域が出ていない。Mass Storage設定後のUSB再接続待ち |
| 実機送信・保存・ACK | 512 / 1024 / 2048 B | **未実施**。時計側PoCの導入待ち |
| ARGUS全件E2E | `integration_test/` | 今回はPR未作成・本体未変更のため未実施。PR提出前には全件実行が必要 |

Androidの成功は、時計側保存・ACKの成功を意味しない。
次は55のUSBモードをMass Storageにして保存領域を認識させ、受信PoCを転送する。
USBを外してRunにLink PoCを一度表示後、スマホから各サイズを送信して実機結果を追記する。
