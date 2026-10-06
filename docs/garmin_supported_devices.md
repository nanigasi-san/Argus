# GARMIN Data Field の対象機種とセットアップ

ARGUS Data Fieldは、次のForerunner・fēnix系37製品IDを配布対象に含める。Forerunner 55 / ForeAthlete 55では実機でテストしている。他の機種は試験的な対応で、実機では未検証。転送、表示、音、振動などの動作は保証していない。1つのIDに複数の販売名が対応する場合がある。APIと販売名は[Garmin公式対応機種表](https://developer.garmin.com/connect-iq/compatible-devices/)を参照。

API下限は3.2.0。スマホからのバックグラウンド電話メッセージ受信と、その処理内でのStorage書き込み・削除に必要なバージョンに合わせている。追加するAPI 3.3のForerunner 245・745・945、fēnix 5 Plus系も、[Background受信の対応機種一覧](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html#registerForPhoneAppMessageEvent-instance_function)に含まれる。[バックグラウンドでのStorage操作](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html#setValue-instance_function)もAPI 3.2以上で利用できる。通常のfēnix 5 / 5S / 5XはAPI 3.1で必要機能に対応せず、対象外。

| 系列 | 登録した製品ID | 実機での検証 |
| --- | --- | --- |
| Forerunner 55 / ForeAthlete 55 | `fr55` | テスト済み。確認範囲は下記参照 |
| Forerunner 165 / Music | `fr165`, `fr165m` | 試験的対応・未検証 |
| Forerunner 245 / Music | `fr245`, `fr245m` | 試験的対応・未検証 |
| Forerunner 255 / Music / 255s / 255s Music | `fr255`, `fr255m`, `fr255s`, `fr255sm` | 試験的対応・未検証 |
| Forerunner 265 / 265s | `fr265`, `fr265s` | 試験的対応・未検証 |
| Forerunner 745 / 945 / 945 LTE / 955（Solar含む）/ 965 | `fr745`, `fr945`, `fr945lte`, `fr955`, `fr965` | 試験的対応・未検証 |
| fēnix 5 Plus / 5S Plus / 5X Plus | `fenix5plus`, `fenix5splus`, `fenix5xplus` | 試験的対応・未検証 |
| fēnix 6 / 6 Pro / 6S / 6S Pro / 6X Pro（各Solar等を含む） | `fenix6`, `fenix6pro`, `fenix6s`, `fenix6spro`, `fenix6xpro` | 試験的対応・未検証 |
| fēnix 7 / 7 Pro / 7 Pro Solar（Wi-Fiなし）/ 7S / 7S Pro / 7X / 7X Pro / 7X Pro Solar（Wi-Fiなし） | `fenix7`, `fenix7pro`, `fenix7pronowifi`, `fenix7s`, `fenix7spro`, `fenix7x`, `fenix7xpro`, `fenix7xpronowifi` | 試験的対応・未検証 |
| fēnix 8 43mm / 47・51mm / 8 Pro / 8 Solar 47・51mm | `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm` | 試験的対応・未検証 |

画像付きの詳しい手順は[GARMIN初心者ガイド](guides/garmin.md)を参照。

## 初回セットアップ

1. 時計をGarmin Connectとペアリングし、ARGUS Data Fieldを時計にインストールする。
2. 時計の通常のRunのデータ画面にARGUS Data Fieldを追加し、一度表示する。これでバックグラウンド受信を登録する。
3. スマホのARGUSでGeoJSONファイルまたはQRを読み込み、「GARMINに送る」を開く。iPhoneでは「時計を変更」を押して共有する時計を選び、ARGUSに戻る。Androidではペアリング済み時計を検索する。
4. 接続済みの時計を選んで送信する。時計の保存・照合ACKを受けた場合だけ完了と表示する。未接続、Data Field未導入、送信失敗、ACK不一致・タイムアウトは再接続／再送して確認する。
5. 競技中は通常のRunを開始する。転送済みデータの有効期限内なら、判定と警告はスマホなしで動作する。

iPhoneの転送はARGUSを開いた状態で行う。Garmin公式[iOS Companion SDK 1.8.0](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/1.8.0)をXcodeのSwift Packageとして取得する。Garmin Connectは初回の時計選択とData Fieldのインストールに使い、iPhoneから時計への送信はBLEで行う。[GarminのiOS SDK手順](https://github.com/garmin/connectiq-companion-app-sdk-ios/blob/1.8.0/documentation/ConnectIQ_iOS_SDK.html)も参照。

## 検証状況と追加確認

ForeAthlete 55では旧版Data FieldへのiPhone送信と、0.6.0へのAndroid送信で、時計側の保存・照合ACKを実機確認した。0.6.0でRunを終了・削除した後、次にRun画面を開いた際の`READY`表示も確認した。最初は「CONNECT IQ」と表示されたが、待つか画面を開き直すと`READY`になり、時計のエラーログに今回のARGUSエラーは記録されていなかった。保存領域の直接照合、0.6.0でのRun中の手動停止と削除ACK、期限動作は未確認。オフライン送信、Run中の停止、次のRunでの非監視は変更前のData Fieldで確認した。`fr55`向けConnect IQビルドと26件のSimulatorテスト、Android・iOSのCIは成功している。

2026年10月7日、全37製品IDのSDK端末定義で、Background電話メッセージ受信とStorage書き込み・削除のAPIを確認した。API 3.3世代の`fr245`と`fenix5plus`では、API下限3.2.0の通常ビルドがSDK 9.2.0で成功した。全対象を含めるStore用IQの書き出しと提出状況は[今回の提出記録](garmin_store/2026-10-07_experimental_devices.md)を参照。

追加機種は実機未検証のまま試験的な配布対象に含める。通信、表示、警告などの実機確認は順次進め、確認した機種と試験内容を記録する。ビルド成功だけを動作保証とは扱わない。小／大データ欄、MIP／AMOLED、白黒背景、日本語、最大100頂点の保存・再送・ACK、IN／OUT、GPS待ち、有効期限切れ、音・振動を追加確認する。

Forerunner 55実機ではAndroidとiPhoneの双方から送信して保存ACKを確認し、スマホを切断したRun中の判定・音・振動を確認する。追加機種は全IDのシミュレーター結果を記録し、実機試験済みと区別する。PR提出前には `flutter test`、`flutter analyze`、Android全E2E、およびMac上で `bash scripts/run_ios_e2e.sh <simulator-udid>` を実行し、結果をPRに記録する。
