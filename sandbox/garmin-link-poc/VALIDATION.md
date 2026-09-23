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
| 時計へのUSB転送 | Windows / `GARMIN (D:)`、`GarminDevice.xml` で ForeAthlete 55（`006-B4033-00`）と確認 | 成功。通常ビルドの `LinkPoc.prg` を `D:\GARMIN\APPS\LINKPOC.PRG` へコピーし、転送元と転送先のSHA-256一致を確認（92,892 B）。既存ファイルは変更せず |
| USB取り外し後の連携 | Xiaomi 14T Pro → ForeAthlete 55 | 時計の保存領域はPCから消え、Android PoCのログで `CONNECTED` と対象アプリUUIDの確認に成功。ACK受信リスナーを登録 |
| 実機送信・保存・ACK | 512 / 1024 / 2048 B | **未実施**。ADB `input tap` は端末側の `INJECT_EVENTS` 権限拒否。スマホ画面からの送信操作も成立せず、時計側の `READY` 表示・保存・ACKは未確認 |
| ARGUS全件E2E | `integration_test/` | 今回はPR未作成・本体未変更のため未実施。PR提出前には全件実行が必要 |

Androidから対象アプリが見えたことは、時計側保存・ACKの成功を意味しない。
次は時計のRunデータ画面でLink PoCを追加・表示し、`READY` を確認する。
Android PoCで接続・インストール状態を再確認して512 / 1024 / 2048 Bを順に送信し、各サイズで `PASS` と時計の保存表示を確認する。
MacBookで継続する場合、Garmin Connectと時計をペアリングしたAndroid端末、および55を接続して試す。PRG・APKはビルド成果物としてGitに含めていない。
