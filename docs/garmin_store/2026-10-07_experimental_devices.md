# Connect IQ Store 0.1.1の試験対応機種追加

2026年10月7日、[Issue #110](https://github.com/nanigasi-san/Argus/issues/110)にあるForerunner・fēnixを試験的な配布対象へ追加し、既存アプリの更新版0.1.1としてConnect IQ Storeへ提出した。Forerunner 55 / ForeAthlete 55では実機でテストしている。他の機種は実機未検証として案内する。

## 変更内容

| 項目 | 内容 |
| --- | --- |
| Store版 | 0.1.1。開発用manifestは0.6.0 |
| 対象 | manifestの全37製品ID。既存30 IDにForerunner 245 / Music・745・945、fēnix 5 Plus / 5S Plus / 5X Plusの7 IDを追加 |
| API下限 | 3.4.0から3.2.0へ変更。Background電話メッセージ受信と背景処理でのStorage書き込み・削除に合わせる |
| 実機試験 | fr55のみ実施。追加する36 IDは実機未検証 |
| 掲載文 | 日英の概要と更新情報に、55実機でのテストと他機種の試験対応・実機未検証を明記 |
| AppID | `a86f7de8169f4a3e8c38763cdd2e4d55`を維持 |
| 転送・ACK | 実装とプロトコルを維持 |

通常のfēnix 5 / 5S / 5XはAPI 3.1で必要機能に対応せず、対象に含めない。登録した製品IDと実機確認の範囲は[対応機種ガイド](../garmin_supported_devices.md)を参照。

## 書き出し

Storeの更新画面へ0.1.0を添付したところ、`The updated version should be different from previous versions.`と表示され、同じ番号での更新を受け付けなかった。このため、機種追加の更新版は0.1.1とする。

次のコマンドは、開発用manifestを変更せず、Store用のバージョンだけを0.1.1にして全製品IDを含むIQを書き出す。既存の開発者署名鍵を使い、秘密鍵とビルド生成物はGitへ含めない。

```powershell
./scripts/export_garmin_store.ps1 -Version 0.1.1 -OutputDirectory build/garmin-store/multi-device-0.1.1
```

出力先は`build/garmin-store/multi-device-0.1.1/`。`package-receipt.json`にはAppID、API下限、製品ID、SDK、容量、SHA256を記録する。端末定義が不足している場合は書き出しを中止する。

掲載に使う文面は、このディレクトリの`listing-ja.txt`・`listing-en.txt`、`whats-new-ja.txt`・`whats-new-en.txt`で管理する。

## 検証と提出の記録

SDK 9.2.0 / fr55 / minApiLevel 3.2.0で通常ビルドとテストビルドが成功した。全26件のMonkey Cテストは`PASSED (passed=26, failed=0, errors=0)`、monkeydoの終了コードは0。検出件数と結果を既存の`verify_garmin_tests.py`で照合した。テスト用に起動したSimulatorは終了済み。

```powershell
monkeyc.bat -f garmin/argus-data-field/monkey.jungle -d fr55 -y <既存の署名鍵> -o build/garmin-tests-issue110/ARGUS.prg -l 0
monkeyc.bat -f garmin/argus-data-field/monkey.jungle -d fr55 -y <既存の署名鍵> -o build/garmin-tests-issue110/ARGUS-tests.prg -l 0 --unit-test
monkeydo.bat build/garmin-tests-issue110/ARGUS-tests.prg fr55 /t
```

37製品IDの全地域別バイナリ70件で書き出しが成功した。SDKの`VerifyingUtils.verifyIqFile()`はtrueで、パッケージ内の公開鍵は既存の開発者署名鍵と一致した。IQから取り出したmanifestの全70部品番号を、登録した37 IDのSDK定義と照合し、過不足がないことを確認した。

| 項目 | 結果 |
| --- | --- |
| 提出ファイル | `build/garmin-store/multi-device-0.1.1/ARGUS-0.1.1.iq` |
| 容量 | 1,007,612 bytes |
| SHA256 | `B485EE1A31A20FC1710417877F73D4F23DD7D7D79455E5511BD8A910854FB4AC` |
| 書き出し | SDK 9.2.0、70 / 70ターゲット成功 |
| 署名 | 検証成功、既存の開発者署名鍵と一致 |
| 収録機種 | 全37製品ID・70部品番号を照合済み |

手元SDKに不足していた13製品IDの端末定義は、既存Garmin CIで固定した`ghcr.io/matco/connectiq-tester@sha256:64958e8fd2925d0c4986d72a9aa9d8e2101297a881354aab0118be2f1dc22105`のDevices層から導入した。レイヤーのSHA256を固定manifestと照合し、既存の定義は上書きしていない。追加した全37 IDの必要APIシンボルを確認し、`fr245`と`fenix5plus`の通常ビルドも成功した。

追加機種のSimulator実行と実機通信・表示・警告は未実施。ビルドの成功を実機試験の成功とは扱わない。

## Storeでの確認

canon_orienアカウントで更新ファイルを添付し、`Status: Verified`、`Signature: Verified`、`Version: 0.1.1`と追加機種の認識を確認した。ユーザーは更新提出時のDeveloper License Agreement and Terms of Useへの同意を明示した。日英のDescriptionとWhat's Newへ保存した文面を照合し、Submit後にアプリ詳細へ戻った。

| 項目 | 保存後の表示 |
| --- | --- |
| ストアURL | https://apps.garmin.com/apps/f1c244ce-871e-4d20-9d69-da552afdd38a |
| 版番号 | 0.1.1 (Internal: 2) |
| 審査状態 | App pending。一般公開と承認は未確認 |
| 対応機種 | Compatible DevicesにForerunner 165・245・255・265・745・945・945 LTE・955・965とfēnix 5 Plus・6・7・8の登録済み派生機種を表示 |
| 実機テストの案内 | 日英の概要と更新情報に、55の実機テストと他機種の実機未検証を表示 |

SDKが同じ製品ID・部品番号に対応付けた別の販売名もStoreに列挙される。Enduro 2、quatix 6・7・8、tactix系、Forerunner 158なども一覧に含まれ、これらも55以外の実機未検証として扱う。

保存後の証跡は`build/garmin-store/multi-device-0.1.1/store-compatible-devices.jpg`と、同じディレクトリの概要画面に記録する。画像と署名済みIQはローカルのビルド生成物として保持する。

## Android E2E

既存PR #109へ反映する前に、`./scripts/run_android_ui_checks.ps1 -CaptureScreenshots`で全件を実行した。端末はMedium_Phone_API_36.0 / emulator-5554 / x86_64 / API 36、Flutter 3.44.2。

| 実行ファイル | 結果 |
| --- | --- |
| `integration_test/compass_navigation_test.dart` | 1件成功 |
| `integration_test/core_monitoring_e2e_test.dart` | 8件成功 |
| `integration_test/ui_smoke_test.dart` | 8件成功 |

全3ファイル・17シナリオが成功し、終了コードは0。`e2e/`はなく、`SIMULATOR_GPS=true`などの任意モードは実行していない。起動したAndroid Emulatorを終了し、`adb devices`に残っていないことと、起動プロセス・子qemuプロセスの終了を確認した。検証結果とログは`build/e2e-issue110/`へ保存した。E2Eの時計通信はFakeで、Garmin実機での通信確認とは区別する。
