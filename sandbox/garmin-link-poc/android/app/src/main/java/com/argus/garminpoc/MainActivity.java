package com.argus.garminpoc;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.View;
import android.widget.*;
import com.garmin.android.connectiq.ConnectIQ;
import com.garmin.android.connectiq.IQApp;
import com.garmin.android.connectiq.IQDevice;
import java.text.SimpleDateFormat;
import java.util.*;

public final class MainActivity extends Activity {
    private static final String CONNECT_PACKAGE = "com.garmin.android.apps.connectmobile";
    private static final int INK = Color.rgb(25, 46, 42), TEAL = Color.rgb(0, 121, 107);
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final List<IQDevice> devices = new ArrayList<>();
    private final ArrayDeque<String> logs = new ArrayDeque<>();
    private ConnectIQ sdk;
    private IQDevice device;
    private IQApp app;
    private boolean ready, destroyed;
    private int generation, sdkGeneration;
    private boolean appQueryPending;
    private Map<String, Object> pending;
    private long sentAt;
    private Runnable timeout;
    private boolean retriedAfterStaleAck;
    private TextView status, detail, deviceInfo, appInfo, logView;
    private Spinner devicePicker, sizePicker;
    private Button refresh, send;

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        buildUi();
        if (saved != null && saved.getBoolean("pending")) {
            log("画面の再作成で待機を中断しました。結果未確認です。再送してください。");
        }
        initialize();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(24), dp(24), dp(28));
        scroll.addView(root);
        setContentView(scroll);
        text(root, "SANDBOX  /  FORERUNNER 55", 12, TEAL, true);
        text(root, "Garmin Link PoC", 30, INK, true);
        text(root, "スマホ → 時計へ。保存できたことまで確認。", 14, INK, false);

        LinearLayout state = card(root);
        status = text(state, "接続を準備中", 23, TEAL, true);
        detail = text(state, "Garmin Connectを確認しています。", 14, INK, false);

        LinearLayout first = card(root);
        text(first, "01  時計を選択", 17, INK, true);
        devicePicker = new Spinner(this);
        first.addView(devicePicker, new LinearLayout.LayoutParams(-1, dp(52)));
        deviceInfo = text(first, "未選択", 14, INK, false);
        appInfo = text(first, "時計側には「Link PoC」Data Fieldが必要です。", 13, INK, false);
        refresh = button(first, "接続・インストール状態を再確認", false);
        refresh.setOnClickListener(v -> { if (ready) loadDevices(); else initialize(); });
        Button connect = button(first, "Garmin Connectを開く", false);
        connect.setOnClickListener(v -> openConnect());
        devicePicker.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            public void onNothingSelected(AdapterView<?> parent) {}
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                if (position < devices.size()) selectDevice(devices.get(position));
            }
        });

        LinearLayout second = card(root);
        text(second, "02  テストデータを送信", 17, INK, true);
        text(second, "架空の四角形＋サイズ検証用データ。競技用ではありません。", 13, INK, false);
        sizePicker = new Spinner(this);
        ArrayAdapter<String> sizes = new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
            new String[]{"512 B", "1 KB（1,024 B）", "2 KB（2,048 B）"});
        sizePicker.setAdapter(sizes);
        second.addView(sizePicker, new LinearLayout.LayoutParams(-1, dp(52)));
        text(second, "サイズはデータ本体。通信には識別子などが追加されます。", 12, INK, false);
        send = button(second, "送信して保存ACKを確認", true);
        send.setEnabled(false);
        send.setOnClickListener(v -> send());
        text(second, "送信受付だけでは成功になりません。保存済みデータの照合ACKを最大30秒待ちます。", 13, INK, false);

        LinearLayout third = card(root);
        text(third, "03  通信ログ", 17, INK, true);
        logView = text(third, "まだ通信していません。", 12, INK, false);
        logView.setTypeface(Typeface.MONOSPACE);
        logView.setTextIsSelectable(true);
        text(root, "独立した通信実験アプリ · v0.1.0\n位置情報の取得・エリア監視は行いません。", 12, INK, false);
    }

    private boolean hasConnect() {
        try { getPackageManager().getPackageInfo(CONNECT_PACKAGE, 0); return true; }
        catch (android.content.pm.PackageManager.NameNotFoundException e) { return false; }
    }

    private void initialize() {
        if (destroyed || pending != null) return;
        ready = false;
        app = null;
        updateButtons();
        if (!hasConnect()) {
            state("Garmin Connectが必要です", "Garmin Connectをインストールしてログインし、55をペアリングしてください。", false);
            log("Garmin Connect未インストール。SDK通信はまだ開始していません。");
            return;
        }
        releaseSdk();
        final int sdkToken = ++sdkGeneration;
        state("SDKに接続中", "Garmin Connectのサービスへ接続しています。", false);
        try {
            sdk = ConnectIQ.getInstance(this, ConnectIQ.IQConnectType.WIRELESS);
            sdk.initialize(this, false, new ConnectIQ.ConnectIQListener() {
                public void onSdkReady() { ui(() -> { if (sdkToken != sdkGeneration) return; ready = true; log("SDK準備完了 / WIRELESS"); loadDevices(); }); }
                public void onInitializeError(ConnectIQ.IQSdkErrorStatus error) {
                    ui(() -> { if (sdkToken != sdkGeneration) return; ready = false; state("SDK接続エラー", error.name() + "\nGarmin Connectを開いて再確認してください。", true); updateButtons(); log("SDK: " + error); });
                }
                public void onSdkShutDown() { ui(() -> { if (sdkToken != sdkGeneration) return; ready = false; app = null; failPending("SDKが切断されました"); updateButtons(); }); }
            });
        } catch (Exception e) { error("SDK初期化", e); }
    }

    private void loadDevices() {
        if (!ready || pending != null) return;
        generation++;
        app = null;
        device = null;
        devices.clear();
        updateButtons();
        try {
            sdk.unregisterAllForEvents();
            List<IQDevice> known = sdk.getKnownDevices();
            if (known != null) devices.addAll(known);
            List<String> names = new ArrayList<>();
            for (IQDevice d : devices) names.add(d.getFriendlyName());
            if (names.isEmpty()) names.add("ペアリング済みの時計がありません");
            devicePicker.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, names));
            log("ペアリング済み端末: " + devices.size());
            if (devices.isEmpty()) {
                deviceInfo.setText("未接続");
                appInfo.setText("Garmin ConnectでForerunner 55をペアリングしてください。");
                state("時計が見つかりません", "Garmin Connectでのペアリング完了後、再確認してください。", false);
            }
        } catch (Exception e) { error("端末取得", e); }
    }

    private void selectDevice(IQDevice selected) {
        if (!ready || pending != null) return;
        final int token = ++generation;
        device = selected;
        app = null;
        appInfo.setText("時計側PoCを確認中…");
        updateButtons();
        try {
            sdk.unregisterAllForEvents();
            IQDevice.IQDeviceStatus connection = sdk.getDeviceStatus(selected);
            final boolean[] wasConnected = {connection == IQDevice.IQDeviceStatus.CONNECTED};
            sdk.registerForDeviceEvents(selected, (d, s) -> ui(() -> {
                if (token != generation) return;
                deviceInfo.setText(d.getFriendlyName() + " · " + s.name());
                if (s != IQDevice.IQDeviceStatus.CONNECTED) {
                    wasConnected[0] = false;
                    appQueryPending = false;
                    app = null;
                    failPending("時計の接続が切れました。保存結果は未確認です。");
                    state("時計が未接続です", "BluetoothとGarmin Connectを確認してください。", false);
                    updateButtons();
                } else if (!wasConnected[0] && pending == null) {
                    wasConnected[0] = true;
                    selectDevice(d);
                }
            }));
            deviceInfo.setText(selected.getFriendlyName() + " · " + connection.name());
            log("時計の状態: " + connection.name());
            if (connection != IQDevice.IQDeviceStatus.CONNECTED) {
                appInfo.setText("接続後に時計側PoCを確認します。");
                state("時計が未接続です", "Garmin Connectを開いて、時計との接続を確認してください。", false);
                return;
            }
            state("時計側PoCを確認中", "時計の「Link PoC」インストール状態を確認しています。", false);
            appQueryPending = true;
            handler.postDelayed(() -> {
                if (!destroyed && token == generation && appQueryPending && pending == null) {
                    appQueryPending = false;
                    state("時計側PoCの確認待ち", "応答がありません。時計側の導入・同期後に再確認してください。", false);
                }
            }, 15000);
            sdk.getApplicationInfo(Protocol.APP_ID, selected, new ConnectIQ.IQApplicationInfoListener() {
                public void onApplicationInfoReceived(IQApp installed) { ui(() -> {
                    if (token != generation || !wasConnected[0]) return;
                    appQueryPending = false;
                    if (installed == null || installed.getStatus() != IQApp.IQAppStatus.INSTALLED) {
                        missingApp(); return;
                    }
                    try {
                        sdk.registerForAppEvents(selected, installed, (d, a, messages, result) -> ui(() -> {
                            if (token != generation || d.getDeviceIdentifier() != selected.getDeviceIdentifier()) return;
                            if (result != ConnectIQ.IQMessageStatus.SUCCESS) { failPending("受信エラー: " + result); return; }
                            receive(messages);
                        }));
                        app = installed;
                        appInfo.setText("Link PoC 導入済み");
                        state("送信できます", "時計側で一度Runのデータ画面に「Link PoC」を表示し、受信を有効にしてください。", false);
                        log("時計側PoCを確認。ACK受信を登録しました。");
                        updateButtons();
                    } catch (Exception e) { error("ACK受信登録", e); }
                }); }
                public void onApplicationNotInstalled(String id) { ui(() -> { if (token == generation && wasConnected[0]) missingApp(); }); }
            });
        } catch (Exception e) { error("時計の確認", e); }
    }

    private void missingApp() {
        appQueryPending = false;
        app = null;
        appInfo.setText("Link PoC が時計に未インストールです。");
        state("時計側PoCが必要です", "sandboxのgarmin側プログラムを55へUSB転送し、Runのデータ項目に追加してください。", false);
        log("対象アプリ未導入: " + Protocol.APP_ID);
        updateButtons();
    }

    private void send() {
        if (!ready || device == null || app == null || pending != null) return;
        int bytes = new int[]{512, 1024, 2048}[sizePicker.getSelectedItemPosition()];
        pending = Protocol.request(bytes, System.currentTimeMillis() / 1000);
        final Map<String, Object> request = pending;
        sentAt = SystemClock.elapsedRealtime();
        retriedAfterStaleAck = false;
        state("送信中", bytes + " Bのテストデータを送っています。", false);
        log("SEND " + bytes + " B / " + request.get("requestId") + " / checksum=" + request.get("checksum"));
        updateButtons();
        transmit(request, false);
    }

    private void transmit(Map<String, Object> request, boolean retry) {
        if (retry) {
            log("RETRY / 古いACKを受信したため同じrequestIdで再送します。");
            state("再送信中", "古いACKを破棄し、同じ要求を1回だけ再送しています。", false);
        }
        if (timeout != null) handler.removeCallbacks(timeout);
        timeout = () -> { if (pending == request) failPending("ACKが30秒以内に届きませんでした。保存結果は未確認です。再送できます。"); };
        handler.postDelayed(timeout, 30000);
        try {
            sdk.sendMessage(device, app, request, (d, a, result) -> ui(() -> {
                if (pending != request) return;
                log((retry ? "SDK再送結果: " : "SDK送信結果: ") + result);
                if (result == ConnectIQ.IQMessageStatus.SUCCESS) {
                    state("時計の保存ACK待ち", "送信は受け付けられました。時計での保存・照合結果を待っています。", false);
                } else failPending("送信エラー: " + result);
            }));
        } catch (Exception e) { error("送信", e); }
    }

    private void receive(Object message) {
        if (message instanceof List<?>) {
            for (Object part : (List<?>) message) receive(part);
            return;
        }
        if (!(message instanceof Map<?, ?>)) { log("未知の受信形式を無視しました。"); return; }
        Map<?, ?> ack = (Map<?, ?>) message;
        if (pending == null) {
            log("待機中の送信がないため、古いACKを無視しました。");
            return;
        }
        if (!pending.get("requestId").equals(ack.get("requestId"))) {
            log("古いACKを無視しました。 expected=" + pending.get("requestId")
                + " / actual=" + ack.get("requestId"));
            if (!retriedAfterStaleAck) {
                retriedAfterStaleAck = true;
                final Map<String, Object> request = pending;
                // Let the watch finish transmitting the queued ACK and exit its
                // background service before asking it to process the retry.
                handler.postDelayed(() -> {
                    if (pending == request) transmit(request, true);
                }, 1500);
            }
            return;
        }
        if (!Protocol.isMatchingAck(pending, ack)) {
            failPending("ACK照合失敗: " + (ack.get("error") == null ? "内容が一致しません" : ack.get("error")));
            return;
        }
        long elapsed = SystemClock.elapsedRealtime() - sentAt;
        int bytes = (Integer) pending.get("bytes");
        clearPending();
        state("時計への保存を確認", bytes + " B · " + elapsed + " ms\nバックグラウンド受信・保存後の読み戻し照合ACKを受信しました。", false);
        log("PASS / saved=true / " + bytes + " B / " + elapsed + " ms / checksum=" + ack.get("checksum"));
        updateButtons();
    }

    private void failPending(String message) {
        if (pending == null) return;
        clearPending();
        state("転送結果を確認できません", message, true);
        log("FAIL / " + message);
        updateButtons();
    }
    private void clearPending() { pending = null; if (timeout != null) handler.removeCallbacks(timeout); timeout = null; }
    private void updateButtons() {
        if (send == null) return;
        send.setEnabled(ready && app != null && device != null && pending == null);
        refresh.setEnabled(pending == null);
        devicePicker.setEnabled(pending == null);
        sizePicker.setEnabled(pending == null);
    }
    private void error(String action, Exception e) {
        failPending(action + ": " + e.getMessage());
        state(action + "に失敗", e.getClass().getSimpleName() + ": " + e.getMessage(), true);
        log(action + ": " + e);
        updateButtons();
    }
    private void openConnect() {
        Intent intent = getPackageManager().getLaunchIntentForPackage(CONNECT_PACKAGE);
        if (intent == null) intent = new Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=" + CONNECT_PACKAGE));
        try { startActivity(intent); } catch (Exception e) { error("Garmin Connectを開く操作", e); }
    }
    private void state(String title, String message, boolean error) {
        status.setText(title); detail.setText(message);
        status.setTextColor(error ? Color.rgb(170, 60, 35) : TEAL);
    }
    private void log(String message) {
        logs.addLast(new SimpleDateFormat("HH:mm:ss", Locale.US).format(new Date()) + "  " + message);
        while (logs.size() > 40) logs.removeFirst();
        logView.setText(String.join("\n\n", logs));
        Log.i("GarminLinkPoc", message);
    }
    private void ui(Runnable action) { handler.post(() -> { if (!destroyed) action.run(); }); }
    private void releaseSdk() {
        if (sdk != null) {
            try { sdk.unregisterAllForEvents(); sdk.shutdown(this); } catch (Exception e) { Log.d("GarminLinkPoc", "SDK cleanup", e); }
            sdk = null;
        }
    }
    @Override protected void onSaveInstanceState(Bundle out) {
        out.putBoolean("pending", pending != null);
        super.onSaveInstanceState(out);
    }
    @Override protected void onDestroy() {
        destroyed = true; generation++; handler.removeCallbacksAndMessages(null); releaseSdk(); super.onDestroy();
    }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private LinearLayout card(LinearLayout root) {
        LinearLayout card = new LinearLayout(this); card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(18), dp(18), dp(18), dp(18));
        GradientDrawable bg = new GradientDrawable(); bg.setColor(Color.WHITE); bg.setCornerRadius(dp(18));
        card.setBackground(bg);
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2); p.topMargin = dp(18); root.addView(card, p);
        return card;
    }
    private TextView text(LinearLayout parent, String value, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(value); t.setTextSize(size); t.setTextColor(color);
        t.setPadding(0, dp(4), 0, dp(6)); t.setLineSpacing(dp(3), 1);
        if (bold) t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        parent.addView(t); return t;
    }
    private Button button(LinearLayout parent, String label, boolean primary) {
        Button b = new Button(this); b.setText(label); b.setAllCaps(false); b.setTextSize(14);
        if (primary) {
            b.setBackgroundTintList(new android.content.res.ColorStateList(
                new int[][]{new int[]{-android.R.attr.state_enabled}, new int[]{}},
                new int[]{Color.rgb(180, 195, 190), TEAL}));
            b.setTextColor(Color.WHITE);
        }
        parent.addView(b, new LinearLayout.LayoutParams(-1, dp(56))); return b;
    }
}
