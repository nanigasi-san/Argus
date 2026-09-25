# GARMIN転送データ形式（AGW1）

ARGUSはGeoJSONやQRから復元した境界をスマホ上で変換し、GARMINのConnect IQ Data Fieldへ送る。GARMIN側でgzip/ZIPやGeoJSONを展開する方式ではない。`AGW1` は座標を約1m単位の整数へ量子化したコンパクトな**ASCII表現**であり、一般的な圧縮アルゴリズムは使用していない。

## 対応する形状と変換

- 想定形状は穴のない単一Polygon、3〜100頂点。GeoJSONで先頭点を末尾に重複させた閉路は、重複する末尾点を除いて数える。複数Polygonと101頂点以上は送信前に拒否する。頂点の自動間引きはしない。現行のGeoJSON読込は内側リング（穴）を保持しないため、穴付き入力は外周だけが送られる点に注意する。
- 原点は頂点の緯度・経度の算術平均。東を `x`、北を `y` とし、各頂点を `x = round((lon - originLon) × 111320 × cos(originLat))`、`y = round((lat - originLat) × 110540)` で整数メートルへ変換する。原点の緯度・経度は `originLatE7` / `originLonE7` に保存する。
- `x` と `y` はそれぞれ符号付き16bit相当の `-32768..32767` に制限する。範囲を超えた形状は送信しない。これは近似的な局所座標変換であり、測量精度の保証ではない。
- 座標本体は `AGW1|x1,y1;x2,y2;...`。例: `AGW1|-5000,-5000;5000,-5000;5000,5000;-5000,5000`。すべてASCIIなので、この文字列の長さが `bytes` の値と一致する。

## 100頂点のサイズ

本体の長さは `5（AGW1|）+ 各座標対の文字数 + 99（区切りの ;）` バイト。100頂点で各座標が取り得る最長表記は `-32768,-32768` の13文字なので、**座標本体の理論上限は1,404B**。10km四方の辺に25頂点ずつ等間隔で置き、座標を整数メートルで表した例では**1,088B**となる。小さな座標値ならさらに短くなる。スマホ側とGARMIN側は本体を最大2,048Bに制限しているため、正常な100頂点のAGW1本体はこの上限内に収まる。

ただし、これは**`data` フィールドだけ**のサイズである。転送辞書には `courseId`、最大48 UTF-8バイトの `displayName`、`requestId`、有効期限、頂点数、原点、チェックサム等も付く。Connect IQ SDK/BLEが実際に送るバイト数や一時メモリ使用量は辞書のシリアライズ方法に依存し、1,404Bと同一ではない。最大100頂点の保存・ACKはForeAthlete 55実機でも別途検証する。

## 保存と照合

スマホはAGW1本体のASCIIバイトに対するAdler-32を10進文字列の `checksum` として付ける。`courseId` はファイル名をASCIIの安全な文字へ置換した名前とチェックサムから作り、最大64文字に収める。外側のメッセージは `type=argus-course`、`v=1` とし、ネイティブ転送層が毎回 `requestId` を追加する。

GARMINのBackground受信処理は形式・長さ・チェックサムを確認し、`pending` に一時保存して読み戻した後、`course` として永続保存し再度読み戻す。成功時だけ保存結果を含むACKを返す。スマホは `requestId`、`courseId`、ファイル名、チェックサム、バイト数、頂点数、有効期限が一致するACKを受けて初めて転送完了とする。ACK待機の上限は60秒。通信開始には事前のペアリングとGarmin Connectが必要だが、ARGUSの転送処理自体はクラウドAPIを呼ばない。

実装: [エンコーダ](../lib/garmin/garmin_course_encoder.dart)、[転送payload](../lib/garmin/garmin_course_payload.dart)、[GARMIN受信処理](../garmin/argus-data-field/source/ArgusReceiver.mc)、[形式・チェックサム検証](../garmin/argus-data-field/source/ArgusProtocol.mc)。
