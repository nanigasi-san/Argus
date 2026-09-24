# ARGUS Data Field（範囲監視版）

ForeAthlete 55 向け。Flutter ARGUS から送られた単一 Polygon（最大100頂点）を
Connect IQ Background で受信し、Storageへ保存、読み戻しとAdler-32照合後にACKを返す。
通常のRunのデータ画面へ追加し、Runのタイマー開始後にGPSが使える状態で
境界の内外を監視する。`IN` は範囲内、`CHECKING` は範囲外の再確認中、
`MAP OUT` と方角・境界までの距離は範囲外を示す。

境界外10mを超える測位を2回（2秒以上）確認したとき、音とバイブを1回鳴らす。
再入域も2回確認して解除する。通常は10秒ごと、範囲外候補・範囲外では2秒ごとに
判定する。方角は現在地から最寄り境界への絶対方位（N/NE/E/SE/S/SW/W/NW）。
`ARMED` はRun開始待ち、`GPS WAIT` は測位待ち、`EXPIRED` は転送時から12時間が
経過した状態。`EXPIRED` の場合はスマホのARGUSから同じ地図を再送する。

Data FieldはGPS精度や電池・OSの制約を受けるため、安全を保証する機能ではない。
競技中は画面と周囲の状況を自分でも確認すること。

SDK 9.2.0 / `fr55` でのビルド例:

```sh
monkeyc -f garmin/argus-data-field/monkey.jungle -d fr55 \
  -y <developer_key.der> -o garmin/argus-data-field/bin/ARGUS.prg -l 0
```

初回はRunのデータ画面にARGUSを追加して一度表示し、バックグラウンド受信を登録する。
その後Runを終了しても転送できる。スマホ側はGarmin ConnectとのBluetooth接続が必要。
