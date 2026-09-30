# GeoJSON対応早見表の生成記録

- 生成日: 2026-09-30
- 使用ツール: Codex内蔵 Image Gen
- 出力: `geojson_compatibility.png`
- 対応条件の正本: `../geojson_validation.md`
- 生成後に日本語、頂点数、許可・拒否の形状を目視確認。模式図のQRは読み取り用データではない。

## 最終プロンプト

```text
Use case: infographic-diagram
Asset type: Japanese technical documentation infographic for ARGUS README and GeoJSON validation docs.
Primary request: Create ONE polished, highly legible landscape comparison infographic with three equal columns: smartphone, QR (AGZ1), Garmin. Explain the real accepted GeoJSON geometry. Clean white background, dark navy text, teal-green accepted shapes, soft blue accents, muted red rejected shapes. Crisp flat vector-like educational rendering, generous whitespace, very clear Japanese typography, no photograph, no watermark, no invented logo. Landscape approximately 1536x1024, high resolution.
Exact top title: "ARGUS｜GeoJSON 対応早見表"
Subtitle: "1つの範囲を、スマホ・QR・Garminで"
A shared top band reads exactly:
"共通条件：単一Feature・単一Polygon・穴なし・閉じた外周"
"FeatureCollection形式／座標は経度・緯度／自己交差なし"
Then three clearly separated equal cards:
LEFT header "スマホ"
Draw a phone icon and one green concave simple closed polygon with 5–7 visible vertex dots, no hole. A green check badge. Main bold text "3〜1,000頂点"
Supporting text exactly two lines:
"ファイル・QRから読み込み"
"短い辺・小さい面積は警告"
MIDDLE header "QR（AGZ1）"
Draw a schematic QR icon and one green closed simple polygon identical to left, with a subtle encode-to-QR arrow. Main bold text "3〜1,000頂点"
Supporting text exactly two lines:
"1枚のQRに収まる容量"
"小数6桁に丸めても有効な形状"
RIGHT header "Garmin"
Draw a sports watch icon and one green closed simple polygon, same as other two, with a subtle square metre grid underneath. Main bold text "3〜100頂点"
Supporting text exactly two lines:
"1m単位に丸めても有効な形状"
"ローカルXYはint16範囲内・データ2KB以内"
Under the cards, a short centered note exactly:
"頂点数は、先頭と重なる閉路の終点を数えません"
Then a shared bottom rejection band titled exactly "すべてで使えない形状"
Show FOUR distinctly separated red outline mini illustrations, each with a red X and a concise label:
1. two disjoint polygons side by side, label "複数の範囲・MultiPolygon"
2. a polygon with a clear empty interior ring hole, label "穴あり"
3. bow-tie edges actually crossing at centre, label "自己交差・辺の重なり"
4. open polygon with a visibly missing final edge connecting first to last and two separate endpoint dots, label "外周が閉じていない"
Do not accidentally close illustration 4. The accepted polygons must have no self-crossing and no holes. A concave simple polygon is accepted. Do not imply multiple polygons are accepted on smartphone. Smartphone and QR max is 1,000; Garmin max is 100. Do not add fake precision guarantees or state that every 1,000-vertex file fits in a QR. No extra technical paragraphs. Accurate text and understandable geometry are the priority. All Japanese text above should be rendered verbatim and correctly, with comfortable readable size.
```

