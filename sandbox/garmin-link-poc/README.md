# Garmin Link PoC

Issue [#86](https://github.com/nanigasi-san/Argus/issues/86) の Phase 0 用の独立した通信実験。
ARGUS本体へ組み込む前に、Android → ForeAthlete / Forerunner 55 の
バックグラウンド受信 → 永続保存 → 読み戻し照合 → ACK を検証する。

| 構成 | 内容 |
| --- | --- |
| `android/` | ネイティブJavaのAndroidアプリ。表示名 `Garmin Link PoC`、パッケージ `com.argus.garminpoc` |
| `garmin/` | 時計側 `Link PoC` Data Field。対応製品は **`fr55` のみ** |
| `build-android.ps1` | Androidのビルド、単体テスト、Lint、指定スマホへのインストール |
| `build-watch.ps1` | 55向けPRGのビルド。開発鍵は `.local/` に生成しGit対象外 |

ARGUS本体と異なるアプリID・時計UUID・保存領域を使う。位置情報の取得、
実コース読込、IN/OUT判定、音・バイブ、競技中の監視はこのPoCの対象外。
時計に多数の機種定義を入れていても、ビルド対象は `fr55` に固定される。

## Androidをビルド・インストール

必要なもの: JDK 17以上、Android SDK platform 36、ADB。
アプリの最低OSはAndroid 8.1 / API 27。PoCはtarget SDK 34でビルドし、
Play Store公開用の設定にはしていない。Garmin Companion SDKはMaven Centralの2.4.0を固定使用する。

```powershell
cd sandbox/garmin-link-poc
./build-android.ps1
adb devices -l
./build-android.ps1 -Install -Serial <adbの端末シリアル>
```

`ANDROID_HOME` を指定しない場合、Windowsの標準SDK配置を使用する。
Android Studioでも `android/` を直接開ける。Gradle wrapperはこのPoC内に同梱。

Androidには **Garmin Connect** が必要。Connect IQ Storeアプリだけでは通信できない。
Garmin Connectへログインし、55をペアリングしておく。

## 時計側をビルド・転送

Connect IQ SDK ManagerでSDKと `fr55` のデバイス定義を導入する。

```powershell
./build-watch.ps1
# 出力: garmin/bin/LinkPoc.prg
```

`-SdkPath` / `-KeyPath` で任意のSDK・開発鍵を指定できる。
開発鍵・PRG・APK・ビルド成果物はコミットしない。

1. 55をデータ通信可能なUSBケーブルでPCにつなぐ。
2. エクスプローラーに時計の保存領域が出たら、`GARMIN/GarminDevice.xml` 等で55であることを確認する。
3. `garmin/bin/LinkPoc.prg` を時計の **`GARMIN/APPS/LinkPoc.prg`** へコピーする。
4. 時計を安全に取り外し、USBケーブルを抜く。
5. 時計のRunのデータ画面に **Link PoC** を追加し、一度表示する。`READY` 表示でバックグラウンド受信登録済み。
6. Garmin Connectで時計とのBluetooth接続を確認する。
7. スマホのPoCで「接続・インストール状態を再確認」を押す。

初回の受信登録にはData Fieldを一度開く必要がある。
時計がUSB接続中の場合、Bluetooth経由の確認はUSBを外してから行う。
WindowsがUSBデバイスをコード28で認識する場合は、保存領域へアクセスできていないため転送を進めない。
まず時計のUP長押し → 設定 → システム → USBモードでMass Storageを選び、USBをつなぎ直す。
それでも認識しない場合は、公式Garminドライバー／Garmin Expressを確認する。
関係のないアプリや活動ファイルは削除しない。

## 試験手順と成功条件

1. PoCで時計を選択する。接続・時計側PoC導入確認が完了すると送信ボタンが有効になる。
2. 512 B → 1,024 B → 2,048 Bの順に送信する。
3. **「時計への保存を確認」** とログの `PASS` を確認する。
4. Data Fieldには保存されたデータサイズが `512 B OK` 等と表示される。
5. Runの別ページ表示中、およびRun終了後にも送信してバックグラウンド受信を検証する。
6. 再送・Bluetooth切断・ACKタイムアウト・時計再起動後の保存データ表示を確認する。

`sendMessage` の `SUCCESS` は「保存ACK待ち」に進むだけ。完了には以下がすべて必要:

- 同じ時計の対象アプリからの受信
- `type=ack`, `v=1`, `receiver=background`, `saved=true`
- `requestId`, `courseId`, `bytes`, `vertexCount`, `armedUntil`, `checksum` の一致

待ち時間は送信開始から30秒。古い送信のACKは無視する。
タイムアウト・切断・不一致は成功にせず、再送可能にする。
画面回転やプロセス終了で待機が失われた場合も完了扱いにはしない。
これはRAM上の送信状態を使うPoCで、終了したアプリへのACKを後から復元する機能はない。

## 試験用プロトコル v1

時計UUID: `e9af7de8169f4a3e8c38763cdd2e4d55`（Androidとmanifestで共通）。

データ本体はASCII文字列。先頭 `0,0;100,0;100,100;0,100|` はローカルXYの架空の四角形、
残りはサイズを増やすための英字。512 / 1024 / 2048 Bは**本体サイズ**であり、
実際の通信サイズにはSDKのシリアライズとメタデータが加わる。
最大100頂点や実コース形式AGW1の検証はこの通信PoCでは行わない。

送信辞書: `type`, `v`, `requestId`, `courseId`, `armedUntil`, `vertexCount`, `bytes`, `data`, `checksum`。
`armedUntil` は作成時から1時間後のUnix秒で、照合試験用メタデータ。監視を有効化するものではない。
`checksum` はデータ本体のAdler-32を符号なし10進文字列で表現する。
これは転送・保存の破損検出用で、認証や暗号化の仕組みではない。

時計は型・サイズ・試験用形式・チェックサムを確認して `Application.Storage` の `last` に保存。
その値を読み戻して再検証した後に、読み戻した値からACKを作成する。
ACKには `data` を含めず、`saved`, `receiver`, `error` を追加する。

## 検証

```powershell
# APK、Android単体テスト、Lint
./build-android.ps1

# 時計側テストを含むビルド
./build-watch.ps1 -TestBuild
# 起動済みConnect IQ simulatorに対して実行
& '<SDK>/bin/monkeydo.bat' '<絶対パス>/garmin/bin/LinkPoc.prg' fr55 /t
# 実機へ転送する前に通常ビルドへ戻す
./build-watch.ps1
```

実施結果は [VALIDATION.md](VALIDATION.md) に記録する。
PoCの単体検証はARGUS全件E2Eの代わりにはならない。PR提出時にはルートAGENTS.mdに従って全件E2Eを実施する。

公式資料: [Android SDK](https://github.com/garmin/connectiq-android-sdk)、
[Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)、
[Storage](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)。
