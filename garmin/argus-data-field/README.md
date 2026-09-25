# ARGUS Data Field（範囲監視版）

Forerunner 55・165・255・265・945 LTE・955・965とfēnix 6・7・8向け。製品IDの一覧と初回セットアップは[対応機種ガイド](../../docs/garmin_supported_devices.md)を参照。Flutter ARGUS から送られた単一 Polygon（最大100頂点）を
Connect IQ Background で受信し、Storageへ保存、読み戻しとAdler-32照合後にACKを返す。
通常のRunのデータ画面へ追加し、Runのタイマー開始後にGPSが使える状態で
境界の内外を監視する。上段には転送したファイル名を表示し、長い名前は省略する。
`IN` は範囲内、`CHECKING` は範囲外の再確認中、`OUT` とその下の
日本語の絶対方位・境界までの距離は範囲外を示す。
日本語表示にはGARMIN本体の言語設定を日本語にする必要がある。英語設定の標準フォントでは
日本語の方角や日本語ファイル名を描画できない。

境界外の測位を2回（2秒以上）確認したとき、音とバイブを同時に3秒鳴らし、
OUTが続く間は1秒休んで繰り返す。ForeAthlete 55で非対応の振動パターンは使わず、
単一の振動プロファイルを使う。音・振動APIの失敗はConnect IQログに記録する。
再入域も2回確認して解除する。通常は10秒ごと、範囲外候補・範囲外では2秒ごとに
判定する。方角は現在地から最寄り境界への絶対方位（N/NE/E/SE/S/SW/W/NW）。
Run中に新しいコースを受信した場合は、最大6秒間 `RECEIVED` と頂点数を表示する。
Run外のバックグラウンド受信ではGARMINに即時ポップアップを出せないため、
スマホ側の保存・照合ACKを成功確認とする。
`ARMED` はRun開始待ち、`GPS WAIT` は測位待ち、`EXPIRED` は転送時から12時間が
経過した状態。`EXPIRED` の場合はスマホのARGUSから同じ地図を再送する。

Data FieldはGPS精度や電池・OSの制約を受けるため、安全を保証する機能ではない。
競技中は画面と周囲の状況を自分でも確認すること。

SDK 9.2.0 / `fr55` でのビルド例（他の製品IDではSDK Managerで端末定義を導入して `-d` を変更）:

```sh
monkeyc -f garmin/argus-data-field/monkey.jungle -d fr55 \
  -y <developer_key.der> -o garmin/argus-data-field/bin/ARGUS.prg -l 0
```

初回はRunのデータ画面にARGUSを追加して一度表示し、バックグラウンド受信を登録する。
その後Runを終了しても転送できる。スマホ側はGarmin ConnectとのBluetooth接続が必要。

座標表現、100頂点時のサイズ、チェックサムとACKの詳細は[Garmin転送データ形式](../../docs/garmin_data_format.md)を参照。

送信するGeoJSON/QRはスマホ内で読み込む。AndroidではGarmin Connectを介した
Bluetooth通信、iPhoneではConnect IQ Companion SDKのBLE通信で送信とACKを行う。
ARGUSの転送処理はクラウドAPIを呼ばないため、
ペアリングとData Fieldのインストールが済んでいれば、送信時のインターネット接続は不要。
ただしBluetooth、Garmin Connectアプリ、両アプリの事前インストールは必要。

オフライン実機確認: スマホのWi-Fiとモバイルデータを切り、Bluetoothはオンのまま
Garmin ConnectとGARMINの接続を確認する。ARGUSからGeoJSONを送信して60秒以内に
保存ACK・スマホ通知・GARMIN上のファイル名を確認し、Run中のIN/OUT監視も確認する。
