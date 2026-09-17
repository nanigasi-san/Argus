"""Render the documented E2E scenarios as diagrams, not device screenshots.

Requires Pillow (pip install Pillow). Run from any directory:
  python scripts/generate_e2e_diagrams.py --font C:/Windows/Fonts/meiryo.ttc
On other systems, pass a Japanese font file, e.g. NotoSansCJK-Regular.ttc.
Scenario descriptions must be kept in sync with integration_test/*_test.dart.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "images" / "e2e"
INK = "#182C43"
MUTED = "#465B70"
BACKGROUND = "#F3F6FA"
COLORS = {
    "ready": ("#E7F0FF", "#3265B2"),
    "safe": ("#E1F4EC", "#247655"),
    "pending": ("#FFF2D5", "#9A660B"),
    "outer": ("#FCE6E6", "#B33D47"),
    "gps": ("#EEE6FA", "#7555A5"),
    "ui": ("#E2F3F7", "#287789"),
    "process": ("#E9EDF3", "#5B6D83"),
}


def step(kind, title, detail, action="", short=None):
    return dict(kind=kind, title=title, detail=detail, action=action,
                short=short or title)


READY = step("ready", "WAIT START", "共通準備済み。GeoJSONをQRから復元・保存。", short="開始待ち")
INNER = step("safe", "INNER", "範囲内。通知・音・振動は停止。", "START → inside / t=0", "範囲内")
CONFIRMED = step("outer", "OUTER", "C1と同じ位置入力で確定済み。通知・音・振動が作動。", short="範囲外・警告")

SCENARIOS = [
    dict(id="C1", slug="monitor-exit-recover", title="範囲外の確定と復帰", test="monitor-exit-recover",
         steps=[READY, INNER,
                step("pending", "OUTER_PENDING", "範囲外サンプル1個 → 2個。警告はまだ出さない。", "outside / t=1 → t=5", "判定待ち"),
                step("outer", "OUTER", "3サンプル ＋ 最初のoutsideから10秒。警告開始は1回。", "outside / t=11", "範囲外・警告"),
                step("safe", "INNER", "通知を取り消し、音・振動を停止。", "inside / t=12", "範囲内・解除")],
         note="範囲外の確定にはサンプル数と経過時間の両方が必要。tは注入した経過秒数。",
         summary="outsideをt=1・5・11で入力。3サンプル＋10秒で警告し、insideで解除。"),
    dict(id="C2", slug="gps-bad-recover", title="GPS精度の悪化と回復", test="gps-bad-recover",
         steps=[READY, INNER,
                step("gps", "GPS_BAD", "未確定の範囲外位置でも、低精度のため警告しない。", "outside / t=1 / 精度100m", "GPS低精度"),
                step("safe", "INNER", "精度が戻り、範囲内判定へ復旧。全行程で警告なし。", "inside / t=2 / 精度5m", "範囲内")],
         note="GPS_BAD閾値は40m。精度の悪い未確定位置から誤警告を出さない。",
         summary="範囲外でも精度100mならGPS_BAD。精度5mの範囲内位置で回復。警告は0回。"),
    dict(id="C3", slug="outer-survives-low-accuracy", title="警告中の低精度化", test="outer-survives-low-accuracy",
         steps=[CONFIRMED,
                step("outer", "OUTERを維持", "警告は継続。音の停止・通知取消・通知の追加発行なし。", "outside / t=12 / 精度100m", "範囲外・維持"),
                step("safe", "INNER", "範囲内と判定できた位置で警告を解除。", "inside / t=13 / 精度100m", "範囲内・解除")],
         note="OUTER確定後は精度悪化だけで警告を消さない。復帰位置も精度100mで検証。",
         summary="確定後の低精度outsideでは警告維持。精度100mのinsideで範囲内へ復帰。"),
    dict(id="C4", slug="stop-restart-clears-pending", title="判定待ちで停止・再開", test="stop-restart-clears-pending",
         steps=[step("pending", "OUTER_PENDING", "START → inside t=0 → outside t=1・5。サンプル2個。", short="判定待ち・2個"),
                step("ready", "WAIT START", "位置サービス停止・購読0。警告は停止。", "終了ボタンを5秒長押し", "停止"),
                step("ready", "WAIT STARTを維持", "停止中の位置は無視。処理・ログ記録なし。", "停止中にoutside / t=100", "停止・入力無視"),
                step("pending", "OUTER_PENDING", "新しい監視のサンプル1個。旧2個は引き継がない。購読1。", "再START → outside / t=50", "判定待ち・1個"),
                step("safe", "INNER", "開始は合計2回。位置1個につきログ1件。警告なし。", "inside / t=51", "範囲内")],
         note="5秒はUI長押しの時間。再開時は判定待ちをリセットし、位置購読を重複させない。",
         summary="停止中の位置は無視。再開後のoutsideは1サンプル目として判定し直す。"),
    dict(id="C5", slug="stop-restart-clears-alarm", title="警告中に停止・再開", test="stop-restart-clears-alarm",
         steps=[CONFIRMED,
                step("ready", "WAIT START", "通知・音・振動を解除。位置サービス停止・購読0。", "終了ボタンを5秒長押し", "停止・警告解除"),
                step("ready", "WAIT STARTを維持", "停止中の位置は無視。状態は変更されない。", "停止中にoutside / t=100", "停止・入力無視"),
                step("pending", "OUTER_PENDING", "判定を新たに開始。旧警告は停止したまま。", "再START → outside / t=50", "判定待ち"),
                step("safe", "INNER", "開始は合計2回・購読1。位置を重複処理しない。", "inside / t=51", "範囲内")],
         note="停止時に旧OUTER状態・警告・判定待ちを解放し、再開後へ残さない。",
         summary="警告を完全に解除して停止。再開しても旧アラームは再生されない。"),
    dict(id="C6", slug="permission-setup-refresh-start", title="権限の確認と監視開始", test="permission-setup-refresh-start",
         steps=[step("ready", "WAIT START / 開始不可", "GeoJSON読込済み。権限denied、Homeにセットアップカード。", short="権限不足"),
                step("ui", "開示画面", "バックグラウンド位置情報の説明を表示。", "「監視開始前に設定する」をタップ", "開示画面"),
                step("ready", "WAIT START / 開始不可", "権限はdeniedのまま。Homeへ戻り、位置サービス未開始。", "Android: 同意ボタン / iOS:「続ける」", "同意・未許可"),
                step("ready", "WAIT START / 開始可能", "セットアップカードが消える。OSダイアログは操作しない。", "gatewayをgrantedへ変更 →「状態を更新」", "権限更新"),
                step("safe", "INNER", "位置サービスが開始し、範囲内。警告なし。", "START → inside / t=0", "監視開始・範囲内")],
         note="開示への同意とOS権限付与は別。テスト用gatewayで権限状態を切り替える。",
         summary="同意だけでは開始不可。権限状態を更新してからSTARTできることを確認。"),
    dict(id="C7", slug="settings-update-monitoring-buffer", title="境界バッファ変更と自動再開", test="settings-update-monitoring-buffer",
         steps=[step("safe", "INNER / バッファ30m", "START後、境界から約36mの同じbufferProbeを入力。", short="範囲内・30m"),
                step("ui", "設定フォーム", "Homeのメニューから設定へ。境界バッファに50を入力。", "メニュー →「設定」→ 50を入力", "設定変更"),
                step("process", "停止 → 保存 → 再開", "設定を反映。Controller・位置サービス・保存ファイルが全て50m。", "スクロール →「設定を反映」をタップ", "保存・自動再開"),
                step("safe", "NEAR / バッファ50m", "同一座標が境界付近の判定に変わる。開始2回・購読1。警告なし。", "Homeへ戻る → 同じbufferProbe / t=0", "境界付近・50m")],
         note="同じ位置で30m → 50mの判定差を検証。灰色の箱は設定反映の処理。",
         summary="境界から約36mの同一座標。30mではINNER、保存・自動再開後の50mではNEAR。"),
    dict(id="C8", slug="outer-snooze-keeps-state", title="スヌーズ中の状態と復帰", test="outer-snooze-keeps-state",
         steps=[CONFIRMED,
                step("outer", "OUTER / スヌーズ中", "isAlarmSnoozed=true。音・振動を停止。範囲外状態は維持。", "「1分間音を停止する」をタップ", "範囲外・消音"),
                step("outer", "OUTERを維持", "音は再開しない。通知の追加発行なし。", "outside / t=12", "範囲外・消音維持"),
                step("safe", "INNER", "isAlarmSnoozed=false。音・振動は停止、通知を取り消す。", "inside / t=13", "範囲内・解除")],
         note="1分満了後の再開はこのE2Eでは検証しない。タイマーの網羅はUnit test側。",
         summary="消音してもOUTERのまま。outsideで音を再開せず、insideで状態とスヌーズを解除。"),
    dict(id="S1", slug="home-permission-card", title="Homeの権限不足表示", test="home shows setup card when monitoring permissions are incomplete",
         steps=[step("process", "権限不足を準備", "GeoJSONあり。通知・常に位置許可はdenied、使用中の位置許可はgranted。", short="通知・常に未許可"),
                step("ui", "Home / セットアップカード", "「監視開始前に位置情報の設定が必要です」「監視開始前に設定する」「通知を許可」を表示。", "Homeを描画", "設定カード表示")],
         note="UI smoke。表示のみを検証し、権限付与や監視開始は操作しない。",
         summary="通知とバックグラウンド位置権限が不足したHomeに、設定カードと通知許可の導線を表示。"),
    dict(id="S2", slug="background-location-disclosure", title="Homeから位置情報の開示画面へ", test="home can open background location disclosure",
         steps=[step("ui", "Home / 権限不足", "通知・使用中の位置許可はgranted、常に位置許可はdenied。", short="Home"),
                step("ui", "開示画面", "タイトルとボタンを表示。Androidは同意ボタン、iOSは「続ける」。", "「監視開始前に設定する」をタップ", "開示画面")],
         note="UI smoke。開示画面の表示まで。続行ボタンのタップや権限付与はこのテストの対象外。",
         summary="Homeの設定導線から開示画面へ。プラットフォーム別ボタンの表示まで検証。"),
    dict(id="S3", slug="settings-form", title="設定フォームとiOSの警告音ボタン", test="settings page renders the monitoring card and form",
         steps=[step("process", "監視可能な状態を準備", "GeoJSONと許可済みの権限状態をHarnessで準備。", short="準備"),
                step("ui", "Settings / フォーム", "「設定」「監視を開始できる状態です。」「境界バッファ距離」を表示。", "Settingsを直接描画（Android・iOS共通）", "設定フォーム"),
                step("ui", "iOSのみ / 警告音ボタン", "「警告音をテスト」のボタンが見えることを確認。", "iOSではボタンまでスクロール", "iOS: 音テスト表示")],
         note="Androidはフォーム表示まで。設定保存・音の再生は操作しない。Homeからの遷移はS5。",
         summary="設定フォームを直接描画。iOSはスクロール後の音テストボタン表示も確認（再生なし）。"),
    dict(id="S4", slug="qr-camera-permission-denied", title="カメラ未許可のQR画面", test="qr page shows retry UI when camera permission is denied",
         steps=[step("process", "カメラ権限denied", "QRスキャナーはテスト用表示へ差し替え。実カメラを起動しない。", short="カメラ未許可"),
                step("ui", "QR画面 / 権限エラー", "カメラ権限のエラー文と「再試行」を表示。", "QR画面を描画", "エラー・再試行表示")],
         note="UI smoke。再試行のタップ、カメラ許可、QR読取の成功は検証しない。",
         summary="カメラ未許可なら権限エラーと再試行ボタンを表示。再試行やQR読取は操作しない。"),
    dict(id="S5", slug="home-to-settings", title="Homeのメニューから設定へ", test="home can navigate to settings from overflow menu",
         steps=[step("ui", "Home", "GeoJSONと許可済みの権限状態を準備して表示。", short="Home"),
                step("ui", "メニュー", "Homeのオーバーフローメニューを開く。", "メニューボタンをタップ", "メニュー"),
                step("ui", "Settings", "設定画面へ遷移。「設定」の表示を確認。", "メニューの「設定」をタップ", "設定画面")],
         note="UI smoke。画面遷移のみ。設定の変更・保存はC7で検証する。",
         summary="Home → メニュー → 設定画面。画面遷移と「設定」の表示を確認。"),
    dict(id="N1", slug="compass-navigation", title="境界へ戻る距離・方向案内", test="outside navigation follows location and device heading",
         steps=[step("safe", "INNER", "ポインターなし。位置は緯度0.5・経度0.5。", short="範囲内"),
                step("outer", "OUTER / 約111m", "START後、東側の範囲外へ。目標方位は約270°。方位未取得なら「方角を確認中」。", "outside (0.5, 1.001) / t=1・3", "範囲外・111m"),
                step("outer", "OUTER / 方位表示を更新", "端末方位に応じて方向案内を更新。位置のOUTER状態は変わらない。", "端末方位を順番に注入（下の6ケース）", "方向案内更新"),
                step("outer", "OUTER / 約56m", "境界までの距離表示を更新。", "位置 (0.5, 1.0005) / t=4", "範囲外・56m"),
                step("safe", "INNER", "方向案内とポインターを消す。", "inside (0.5, 0.5) / t=5", "範囲内"),
                step("ready", "WAIT START", "位置サービス停止を確認。", "終了ボタンを長押し（テストでは6秒）", "停止")],
         headings=[("目標 − 90°", "90度右を向く"), ("目標 ＋ 90°", "90度左を向く"),
                   ("目標 − 29°", "前へ"), ("目標 − 31°", "31度右を向く"),
                   ("null", "確認中・矢印なし"), ("目標と一致", "前へ")],
         note="最初のINNERはSTART＋inside t=0で確認。方位は仮想入力で、磁気センサーを使用しない。",
         summary="OUTER中に右90° → 左90° → 前へ(29°) → 右31° → 方位なし → 前へ。復帰で案内解除。"),
    dict(id="N2", slug="ios-native-virtual-gps", title="iOS仮想GPS経由の案内と復帰", test="iOS native virtual GPS enters and leaves navigation",
         optional=True,
         steps=[step("process", "Simulatorを準備", "SIMULATOR_GPS=true ＋ ARGUS_SIMULATOR_ID。simctlで位置権限を付与。", short="iOS: 権限付与"),
                step("process", "実Geolocatorで位置受信", "UIからSTART。driverが2秒ごとに仮想位置を注入。", "simctlで範囲外の位置を送信", "仮想GPS受信"),
                step("outer", "OUTER", "境界距離は50m超。「方角を確認中」の案内を表示。", "範囲外の位置を受信して確定", "範囲外・案内表示"),
                step("safe", "INNER", "案内とポインターを解除。driver終了前に位置注入とタイマーを解放。", "simctlが範囲内へ移動（約20秒の区間）", "範囲内・案内解除")],
         note="任意モード・通常CI対象外。この図は実装の説明であり、今回の実行成功を示すものではない。",
         summary="任意モード。simctl → 実Geolocator → OUTERの案内 → INNERで解除。通常CIには含めない。"),
]


def wrapped(draw, text, font, width):
    lines = []
    for paragraph in text.split("\n"):
        line = []
        tokens = re.findall(r"[0-9]+(?:秒|回|個|件|m|°)|[A-Za-z0-9_]+|.", paragraph)
        for token in tokens:
            if not line and token.isspace():
                continue
            if line and draw.textlength("".join(line) + token, font=font) > width:
                # Keep Japanese closing punctuation off the start of a line.
                if token in "、。，．！？）」』】" and len(line) > 1:
                    carry = line.pop()
                    lines.append("".join(line).rstrip())
                    line = [carry, token]
                    continue
                carry = line.pop() if line[-1] in "（「『【" else ""
                lines.append("".join(line).rstrip())
                line = [carry] if carry else []
            if line or not token.isspace():
                line.append(token)
        lines.append("".join(line).rstrip())
    return lines


def write(draw, text, xy, font, width, fill=INK, spacing=10):
    x, y = xy
    height = font.size + spacing
    for line in wrapped(draw, text, font, width):
        draw.text((x, y), line, font=font, fill=fill)
        y += height
    return y


def render_scenario(scenario, fonts):
    f = fonts
    steps = scenario["steps"]
    measure = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    subtitle = wrapped(measure, scenario["test"], f[24], 1250)
    y = 116 + 34 * len(subtitle) + 66
    layout = []
    for index, node in enumerate(steps):
        title_height = len(wrapped(measure, node["title"], f[32], 380)) * 42
        body_height = len(wrapped(measure, node["detail"], f[30], 735)) * 40
        card_height = max(126, max(title_height, body_height) + 48)
        if index:
            y += max(78, len(wrapped(measure, node["action"], f[28], 1050)) * 38 + 22)
        layout.append((y, card_height))
        y += card_height
    inset_height = 260 if scenario.get("headings") else 0
    note_height = len(wrapped(measure, scenario["note"], f[28], 1250)) * 38 + 70
    image = Image.new("RGB", (1400, y + inset_height + note_height + 30), BACKGROUND)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((40, 32, 144, 104), radius=18, fill=INK)
    draw.text((58, 40), scenario["id"], font=f[44], fill="white")
    write(draw, scenario["title"], (166, 39), f[44], 1160)
    write(draw, scenario["test"], (56, 116), f[24], 1250, MUTED)
    category = "任意: iOS仮想GPS / 通常CI対象外" if scenario.get("optional") else (
        "UI smoke / 画面の表示・遷移" if scenario["id"].startswith("S") else "監視状態の遷移 / 入力・操作は矢印に表示")
    draw.text((56, 119 + 34 * len(subtitle)), category, font=f[26], fill=MUTED)
    previous_bottom = None
    for index, (node, (top, card_height)) in enumerate(zip(steps, layout)):
        if previous_bottom is not None:
            draw.line((94, previous_bottom, 94, top - 12), fill="#718298", width=4)
            draw.polygon(((84, top - 22), (104, top - 22), (94, top - 8)), fill="#718298")
            write(draw, node["action"], (166, previous_bottom + 16), f[28], 1050, MUTED)
        bg, color = COLORS[node["kind"]]
        draw.rounded_rectangle((130, top, 1344, top + card_height), radius=20, fill="white", outline="#DAE2EC", width=2)
        draw.rounded_rectangle((130, top, 562, top + card_height), radius=20, fill=bg)
        draw.rectangle((544, top + 2, 562, top + card_height - 2), fill=bg)
        draw.ellipse((68, top + 40, 120, top + 92), fill=color)
        draw.text((83, top + 46), str(index + 1), font=f[26], fill="white")
        write(draw, node["title"], (164, top + 27), f[32], 380, color)
        write(draw, node["detail"], (588, top + 24), f[30], 735)
        previous_bottom = top + card_height
    if inset_height:
        top = previous_bottom + 30
        draw.text((56, top), "OUTER中の方位入力 → 方向案内（左から順に確認）", font=f[30], fill=INK)
        for index, (heading, guidance) in enumerate(scenario["headings"]):
            row, column = divmod(index, 3)
            left = 56 + column * 432
            card_top = top + 50 + row * 86
            draw.rounded_rectangle((left, card_top, left + 414, card_top + 76), radius=12, fill="#E2F3F7")
            draw.text((left + 14, card_top + 4), heading, font=f[26], fill=MUTED)
            draw.text((left + 14, card_top + 37), guidance, font=f[28], fill=INK)
    note_top = y + inset_height + 24
    draw.line((56, note_top, 1344, note_top), fill="#DAE2EC", width=2)
    write(draw, scenario["note"], (56, note_top + 18), f[28], 1250, MUTED)
    image.save(OUTPUT / f'{scenario["id"].lower()}-{scenario["slug"]}.png', optimize=True)


def render_gallery(name, title, scenarios, fonts):
    f = fonts
    width, row_height = 1680, 304
    image = Image.new("RGB", (width, 162 + row_height * len(scenarios) + 65), BACKGROUND)
    draw = ImageDraw.Draw(image)
    draw.text((52, 30), title, font=f[44], fill=INK)
    draw.text((52, 98), "箱: 状態・画面・準備処理   →: 入力または操作   /   詳細は各シナリオの図を参照", font=f[28], fill=MUTED)
    for index, scenario in enumerate(scenarios):
        top = 162 + index * row_height
        draw.rounded_rectangle((32, top, 1648, top + row_height - 20), radius=18, fill="white", outline="#DAE2EC", width=2)
        draw.text((56, top + 14), f'{scenario["id"]}  {scenario["title"]}', font=f[36], fill=INK)
        nodes = scenario["steps"]
        cell_width = (1552 - 32 * (len(nodes) - 1)) / len(nodes)
        for j, node in enumerate(nodes):
            left = 56 + j * (cell_width + 32)
            bg, color = COLORS[node["kind"]]
            draw.rounded_rectangle((left, top + 76, left + cell_width, top + 180), radius=14, fill=bg)
            lines = wrapped(draw, node["short"], f[30], cell_width - 28)
            text_top = top + 76 + (104 - len(lines) * 38) / 2
            write(draw, node["short"], (left + 14, text_top), f[30], cell_width - 28, color, spacing=8)
            if j < len(nodes) - 1:
                arrow_left = left + cell_width + 4
                draw.line((arrow_left, top + 128, arrow_left + 22, top + 128), fill=MUTED, width=3)
                draw.polygon(((arrow_left + 17, top + 122), (arrow_left + 17, top + 134), (arrow_left + 27, top + 128)), fill=MUTED)
        write(draw, scenario["summary"], (56, top + 194), f[30], 1540, MUTED)
    draw.text((52, image.height - 54), "ARGUS E2E / 実装済みテストの説明図。スクリーンショットではありません。", font=f[26], fill=MUTED)
    image.save(OUTPUT / f'{name}.png', optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, required=True, help="Japanese TrueType/OpenType font")
    args = parser.parse_args()
    if not args.font.is_file():
        parser.error(f"Font does not exist: {args.font}")
    fonts = {size: ImageFont.truetype(str(args.font), size) for size in (24, 26, 28, 30, 32, 36, 44)}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for scenario in SCENARIOS:
        render_scenario(scenario, fonts)
    render_gallery("overview-core-1", "Core E2E ① / 範囲外・精度・判定待ち", SCENARIOS[:4], fonts)
    render_gallery("overview-core-2", "Core E2E ② / 再開・権限・設定・スヌーズ", SCENARIOS[4:8], fonts)
    render_gallery("overview-ui", "UI smoke / 画面の表示と遷移", SCENARIOS[8:13], fonts)
    render_gallery("overview-navigation", "コンパス案内 / 通常テストと任意のiOS仮想GPS", SCENARIOS[13:], fonts)
    print(f"Generated {len(SCENARIOS)} scenario diagrams and 4 overview images in {OUTPUT}")


if __name__ == "__main__":
    main()
