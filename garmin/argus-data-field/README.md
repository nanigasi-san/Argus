# ARGUS Data Field（転送検証版）

ForeAthlete 55 向け。Flutter ARGUS から送られた単一 Polygon（最大100頂点）を
Connect IQ Background で受信し、Storageへ保存、読み戻しとAdler-32照合後にACKを返す。
通常のRunのデータ画面へ追加すると、保存済み地点数を `N PT OK` と表示する。

現段階は転送・保存の実機検証用であり、GARMIN単独のIN/OUT判定、警告、
復帰方向表示はまだ実装していない。このData Field表示を競技中の安全監視として
使用しないこと。

SDK 9.2.0 / `fr55` でのビルド例:

```sh
monkeyc -f garmin/argus-data-field/monkey.jungle -d fr55 \
  -y <developer_key.der> -o garmin/argus-data-field/bin/ARGUS.prg -l 0
```

初回はRunのデータ画面にARGUSを追加して一度表示し、バックグラウンド受信を登録する。
その後Runを終了しても転送できる。スマホ側はGarmin ConnectとのBluetooth接続が必要。
