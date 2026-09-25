# Garminランニング系・fēnix対応の差分調査（2026-09-25）

この文書は実装前の調査記録。現在の登録機種と検証状況は[対応機種ガイド](garmin_supported_devices.md)を参照。

対象はForerunner/ForeAthleteなどのランニング向け腕時計とfēnixのうち、**Forerunner 55と同じConnect IQ API 3.4以上の機種**。API 3.3以下やEdge、Venu、ハンディGPSは今回の対象外。現行のARGUS Data Fieldは `fr55` のみをmanifestに登録し、技術上はConnect IQ API 3.2以上、Android側Garmin Connect、通常Runのデータ画面を前提とする。**追加機種でのビルド成功は動作保証ではない。**

## 結論と候補

| 優先 | 候補 | 公式Connect IQ API / 画面 | 現行コードの試験ビルド | 判定 |
| --- | --- | --- | --- | --- |
| 基準 | Forerunner 55 | 3.4 / 208px MIP | 既存ターゲット | 実機基準。新しいARGUS Data Fieldの送信・警告の実機再確認が必要 |
| 高 | Forerunner 255/255s、265/265s | 5.2 / 218–416px、MIPまたはAMOLED | 255、255s、265成功。他の派生型は未試験 | 小画面MIPと高解像度AMOLEDの両方を代表させる |
| 高 | fēnix 7系 | 5.2 / 240–280px MIP | 7成功。S/X/Proは未試験 | fēnix側の初回候補 |
| 中 | Forerunner 165、945 LTE、955/965、570/970 | 3.4–6.0 / 240–454px、MIPまたはAMOLED | 165、965成功。他は未試験 | 同じ表示系統ごとに追加検証。570/970の端末定義は手元にない |
| 中 | fēnix 6系、8/9系 | 3.4–6.0 / 240–466pxなど | 今回未試験。端末定義を手元に導入する必要あり | 製品ID・端末定義を導入し、世代と画面別に検証 |
| 対象外 | Forerunner 245/245 Music、645/645 Music、745/945、fēnix 5/5 Plusなど | 3.3以下 | 245と645 Musicはビルド成功、645はAPI不足で失敗 | ビルド可否にかかわらず、55より低いAPIなので対応しない |

名称やビルド可否だけでは対象にしない。例えば245はAPI 3.3、645 MusicはAPI 3.2でビルドできたが、今回の下限3.4には届かない。機種・解像度・APIは[Garmin公式の対応機種表](https://developer.garmin.com/connect-iq/compatible-devices/)を参照。現行のBackground電話メッセージ登録API自体は3.2以降で、[対応機種も個別に示されている](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)。

試験はConnect IQ SDK 9.2.0でソースを変更せず、作業用のmanifestだけ対象IDへ置換して `monkeyc -d <id> -l 0` を実行した。対象内の `fr255`、`fr255s`、`fr265`、`fr165`、`fr965`、`fenix7` は成功。対象外の `fr245`、`fr645m` も成功し、`fr645` は `Device does not support API Level '3.2.0'` で失敗した。シミュレーター実行・画面確認・実機送受信は今回未実施。

## アプリを広げる際の差分

| 箇所 | 現状 | 必要な対応 |
| --- | --- | --- |
| 製品登録と配布 | `garmin/argus-data-field/manifest.xml` は `fr55` だけ。`minApiLevel` は3.2、ビルド例も55のPRG | 下限を3.4にし、検証済み製品IDだけmanifestに追加。全対象を個別ビルドし、配布時は全対象バイナリを含む `.iq` を生成。同じアプリUUID・保存プロトコルは共通化できる。[Garminの配布手順](https://developer.garmin.com/connect-iq/submit-an-app/) |
| 受信時のメモリと保存 | `ArgusReceiver.mc` は受信辞書を `pending` と `course` に保存し、それぞれ読み戻す。Data Fieldは最大100頂点・本体2048 B | 55の32 KB Backgroundを基準に、追加機種でも最大サイズの受信・二重保存・ACK・再送でメモリと容量を計測する。Storageの単一値は32 KB以下、総容量は機種依存。[Storage仕様](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html) |
| 描画 | `ArgusApp.mc` は高さ75/150pxで分岐し、白文字・黒背景とシステムフォントを固定 | 小さい複数データ欄、丸画面の切れ、MIP/AMOLED、端末の白背景設定で見えるようにする。`getBackgroundColor()` と `getObscurityFlags()`、画面形状別リソースを検討。日本語名・方角のフォントも各表示系統で確認。[Data Field API](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html)、[機種別リソース](https://developer.garmin.com/connect-iq/core-topics/build-configuration/) |
| 警告 | `ArgusApp.mc` は振動3秒とトーン3秒を `has` で分岐し、OUT中4秒周期 | 機種・設定ごとに振動/音の実効性、長さ、繰返し、Run中の鳴動を確認。音がない機種では画面表示だけに頼らず、対応基準を決める。Forerunnerの振動パターンは制限される。[Attention仕様](https://developer.garmin.com/connect-iq/api-docs/Toybox/Attention.html) |
| Run中の位置・電池 | `compute(info)` でGPS精度、タイマー、10秒/2秒の判定を扱う | 機種別のRun画面追加方法、他ページ表示中・画面消灯時の更新、GPS未測位/Auto Pause、長時間稼働と電池を確認する。`compute()` はData Fieldに毎秒呼ばれる仕様だが、実運用の警告周期は実機で測る。[Data Field API](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html) |
| スマホ側 | `GarminBridge.java` はペアリング済みGarminを全件表示し、送信時に対象UUIDのインストール有無を照会。Flutter画面も機種を絞らない | サポート済み製品と未検証製品の案内、Data Field導入/Run画面への追加手順、接続・未導入・ACK失敗の表示を整える。製品名の文字列一致だけで互換性判定しない。Androidの通信経路とACK照合は原則共通。iOS Bridge未実装は機種拡張と別の課題 |

## 対応を確定する条件

1. 製品IDのAPIが3.4以上であること、Background電話メッセージと必要な権限を確認してからmanifestへ追加する。
2. 各IDで通常ビルドと単体テストを実行し、32 KB機種を含めて最大100頂点・2048 Bの保存/読み戻し/ACK/再送を検証する。
3. 218–240px MIP、260–280px MIP、360–454px AMOLEDで、Runの小/大データ欄の表示、白黒テーマ、日本語表示をシミュレーターで確認する。
4. 代表実機で「Android ARGUS → Garmin Connect → Data Field → Storage → ACK」、Run中のIN/OUT、画面を切り替えた状態の警告、GPS切断/再取得、音/振動、電池を確認する。未検証機種は対応済みと表示しない。
5. 対応機種を増やしたPRではリポジトリ規則の全件E2Eも実行する。これはGarmin実機試験の代わりにはならない。

実装順は **255s/255 → 265 → fēnix 7** を推奨。まず小画面MIP、次にAMOLED、別シリーズを通す。API 3.4世代のfēnix 6や945 LTEは端末定義を導入して別途検証し、その結果をもとに同世代の派生型と新世代へ広げる。
