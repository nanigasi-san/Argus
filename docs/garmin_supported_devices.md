# GARMIN Data Field の対象機種とセットアップ

ARGUS Data Field 0.4.0 は、Connect IQ API 3.4 以上の次のランニング系・fēnix機種IDをmanifestに登録している。1つのIDに複数の販売名（Solar、Sapphireなど）が対応する場合がある。APIと販売名の出典は[Garmin公式対応機種表](https://developer.garmin.com/connect-iq/compatible-devices/)。Forerunner 245／745／945（LTE以外）、fēnix 5系などAPI 3.3以下の機種、および他シリーズは対象外。

| 系列 | 登録した製品ID |
| --- | --- |
| Forerunner 55 | `fr55` |
| Forerunner 165 / Music | `fr165`, `fr165m` |
| Forerunner 255 / Music / 255s / 255s Music | `fr255`, `fr255m`, `fr255s`, `fr255sm` |
| Forerunner 265 / 265s | `fr265`, `fr265s` |
| Forerunner 945 LTE / 955（Solar含む）/ 965 | `fr945lte`, `fr955`, `fr965` |
| fēnix 6 / 6 Pro / 6S / 6S Pro / 6X Pro（各Solar等を含む） | `fenix6`, `fenix6pro`, `fenix6s`, `fenix6spro`, `fenix6xpro` |
| fēnix 7 / 7 Pro / 7 Pro Solar（Wi-Fiなし）/ 7S / 7S Pro / 7X / 7X Pro / 7X Pro Solar（Wi-Fiなし） | `fenix7`, `fenix7pro`, `fenix7pronowifi`, `fenix7s`, `fenix7spro`, `fenix7x`, `fenix7xpro`, `fenix7xpronowifi` |
| fēnix 8 43mm / 47・51mm / 8 Pro / 8 Solar 47・51mm | `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm` |

## 初回セットアップ

1. 時計をGarmin Connectとペアリングし、ARGUS Data Fieldを時計にインストールする。
2. 時計の通常のRunのデータ画面にARGUS Data Fieldを追加し、一度表示する。これでバックグラウンド受信を登録する。
3. スマホのARGUSでGeoJSONファイルまたはQRを読み込み、「GARMINに送る」を開く。iPhoneでは初回に「Garmin Connectで時計を選ぶ」を押して共有する時計を選び、ARGUSに戻る。Androidではペアリング済み時計を検索する。
4. 接続済みの時計を選んで送信する。時計の保存・照合ACKを受けた場合だけ完了と表示する。未接続、Data Field未導入、送信失敗、ACK不一致・タイムアウトは再接続／再送して確認する。
5. 競技中は通常のRunを開始する。転送済みデータの有効期限内なら、判定と警告はスマホなしで動作する。

iPhoneの転送はARGUSを開いた状態で行う。Garmin公式[iOS Companion SDK 1.8.0](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/1.8.0)をXcodeのSwift Packageとして取得する。Garmin Connectは初回の時計選択とData Fieldのインストールに使い、iPhoneから時計への送信はBLEで行う。[GarminのiOS SDK手順](https://github.com/garmin/connectiq-companion-app-sdk-ios/blob/1.8.0/documentation/ConnectIQ_iOS_SDK.html)も参照。

## Macでの検証

現時点では追加機種のシミュレーター検証、iPhoneとForerunner 55の実機通信、およびiOSビルドは未実施。**manifest登録だけを実機での動作保証と扱わない。** MacでConnect IQ SDK Managerから上記の全製品IDの端末定義を導入してから、各IDを個別にビルド・シミュレーター実行する。小／大データ欄、MIP／AMOLED、白黒背景、日本語、最大100頂点の保存・再送・ACK、IN／OUT、GPS待ち、有効期限切れ、音・振動を確認する。

Forerunner 55実機ではAndroidとiPhoneの双方から送信して保存ACKを確認し、スマホを切断したRun中の判定・音・振動を確認する。追加機種は全IDのシミュレーター結果を記録し、実機試験済みと区別する。PR提出前には `flutter test`、`flutter analyze`、Android全E2E、およびMac上で `bash scripts/run_ios_e2e.sh <simulator-udid>` を実行し、結果をPRに記録する。
