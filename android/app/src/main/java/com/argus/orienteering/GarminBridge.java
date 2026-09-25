package com.argus.orienteering;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import com.garmin.android.connectiq.ConnectIQ;
import com.garmin.android.connectiq.IQApp;
import com.garmin.android.connectiq.IQDevice;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Connect IQ transport. A transfer succeeds only after a matching storage ACK. */
public final class GarminBridge implements MethodChannel.MethodCallHandler {
    private static final String APP_ID = "a86f7de8169f4a3e8c38763cdd2e4d55";
    private final Activity activity;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final MethodChannel channel;
    private ConnectIQ sdk;
    private boolean ready;
    private boolean closed;
    private final List<MethodChannel.Result> deviceWaiters = new ArrayList<>();
    private MethodChannel.Result pendingResult;
    private Map<String, Object> pendingRequest;
    private IQDevice pendingDevice;
    private IQApp pendingApp;
    private long sentAt;
    private Runnable timeout;
    private Runnable appQueryTimeout;
    private Runnable sdkTimeout;
    private boolean retried;

    public GarminBridge(Activity activity, BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, "argus/garmin");
        channel.setMethodCallHandler(this);
        initialize();
    }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if ("getDevices".equals(call.method)) {
            if (ready) returnDevices(result); else { deviceWaiters.add(result); initialize(); }
        } else if ("sendCourse".equals(call.method)) {
            sendCourse(call, result);
        } else {
            result.notImplemented();
        }
    }

    private void initialize() {
        if (closed || sdk != null) return;
        try {
            sdk = ConnectIQ.getInstance(activity, ConnectIQ.IQConnectType.WIRELESS);
            sdkTimeout = () -> failDeviceWaiters("sdk_timeout", "Garmin Connectの応答がありません。アプリを開いて再検索してください。");
            handler.postDelayed(sdkTimeout, 15000);
            sdk.initialize(activity, false, new ConnectIQ.ConnectIQListener() {
                @Override public void onSdkReady() {
                    handler.post(() -> {
                        if (closed) return;
                        clearSdkTimeout();
                        ready = true;
                        flushDeviceWaiters();
                    });
                }
                @Override public void onInitializeError(ConnectIQ.IQSdkErrorStatus error) {
                    handler.post(() -> {
                        clearSdkTimeout();
                        ready = false;
                        releaseSdk();
                        failDeviceWaiters("sdk_init", "Garmin Connectに接続できません: " + error.name());
                    });
                }
                @Override public void onSdkShutDown() {
                    handler.post(() -> {
                        ready = false;
                        sdk = null;
                        failDeviceWaiters("sdk_shutdown", "Garmin Connectとの接続が切れました。");
                        failTransfer("sdk_shutdown", "Garmin Connectとの接続が切れました。");
                    });
                }
            });
        } catch (Exception e) {
            clearSdkTimeout();
            releaseSdk();
            failDeviceWaiters("sdk_init", message(e));
        }
    }

    private void flushDeviceWaiters() {
        for (MethodChannel.Result waiter : new ArrayList<>(deviceWaiters)) returnDevices(waiter);
        deviceWaiters.clear();
    }

    private void returnDevices(MethodChannel.Result result) {
        try {
            List<Map<String, Object>> values = new ArrayList<>();
            List<IQDevice> known = sdk.getKnownDevices();
            if (known != null) for (IQDevice device : known) {
                Map<String, Object> value = new HashMap<>();
                value.put("id", Long.toString(device.getDeviceIdentifier()));
                value.put("name", device.getFriendlyName());
                value.put("connected", sdk.getDeviceStatus(device) == IQDevice.IQDeviceStatus.CONNECTED);
                values.add(value);
            }
            result.success(values);
        } catch (Exception e) {
            result.error("device_search", "GARMINを検索できません: " + message(e), null);
        }
    }

    @SuppressWarnings("unchecked")
    private void sendCourse(MethodCall call, MethodChannel.Result result) {
        if (!ready) { result.error("sdk_not_ready", "Garmin Connectを起動して再検索してください。", null); return; }
        if (pendingResult != null) { result.error("transfer_busy", "別の転送を実行中です。", null); return; }
        Map<String, Object> args = new HashMap<>((Map<String, Object>) call.arguments);
        String deviceId = (String) args.remove("deviceId");
        IQDevice selected = null;
        try {
            List<IQDevice> known = sdk.getKnownDevices();
            if (known != null) for (IQDevice device : known) {
                if (Long.toString(device.getDeviceIdentifier()).equals(deviceId)) selected = device;
            }
            if (selected == null || sdk.getDeviceStatus(selected) != IQDevice.IQDeviceStatus.CONNECTED) {
                result.error("device_disconnected", "選択したGARMINが接続されていません。", null); return;
            }
            args.put("requestId", UUID.randomUUID().toString());
            pendingResult = result;
            pendingRequest = args;
            pendingDevice = selected;
            sentAt = SystemClock.elapsedRealtime();
            retried = false;
            final IQDevice target = selected;
            appQueryTimeout = () -> failTransfer("app_query_timeout", "GARMINのData Field確認が15秒以内に終わりませんでした。再検索してください。");
            handler.postDelayed(appQueryTimeout, 15000);
            sdk.getApplicationInfo(APP_ID, target, new ConnectIQ.IQApplicationInfoListener() {
                @Override public void onApplicationInfoReceived(IQApp app) {
                    handler.post(() -> { clearAppQueryTimeout(); prepareAndSend(target, app); });
                }
                @Override public void onApplicationNotInstalled(String id) {
                    handler.post(() -> {
                        clearAppQueryTimeout();
                        failTransfer("app_not_installed", "ARGUS Data FieldがGARMINにインストールされていません。");
                    });
                }
            });
        } catch (Exception e) {
            failTransfer("transfer_prepare", message(e));
        }
    }

    private void prepareAndSend(IQDevice device, IQApp app) {
        if (pendingResult == null) return;
        if (app == null || app.getStatus() != IQApp.IQAppStatus.INSTALLED) {
            failTransfer("app_not_installed", "ARGUS Data FieldがGARMINにインストールされていません。"); return;
        }
        try {
            pendingApp = app;
            sdk.unregisterAllForEvents();
            sdk.registerForAppEvents(device, app, (d, a, messages, status) -> handler.post(() -> {
                if (status != ConnectIQ.IQMessageStatus.SUCCESS) {
                    failTransfer("ack_receive", "ACKの受信に失敗しました: " + status); return;
                }
                receive(messages);
            }));
            transmit(false);
        } catch (Exception e) {
            failTransfer("ack_register", message(e));
        }
    }

    private void transmit(boolean retry) {
        if (pendingResult == null) return;
        if (timeout != null) handler.removeCallbacks(timeout);
        timeout = () -> failTransfer("ack_timeout", "保存・照合ACKが30秒以内に届きませんでした。再送してください。");
        handler.postDelayed(timeout, 30000);
        try {
            sdk.sendMessage(pendingDevice, pendingApp, pendingRequest, (d, a, status) -> handler.post(() -> {
                if (pendingResult != null && status != ConnectIQ.IQMessageStatus.SUCCESS) {
                    failTransfer("send_failed", "GARMINへの送信に失敗しました: " + status);
                }
            }));
        } catch (Exception e) {
            failTransfer("send_failed", message(e));
        }
    }

    private void receive(Object message) {
        if (message instanceof List<?>) {
            for (Object part : (List<?>) message) receive(part);
            return;
        }
        if (!(message instanceof Map<?, ?>) || pendingRequest == null) return;
        Map<?, ?> ack = (Map<?, ?>) message;
        if (!pendingRequest.get("requestId").equals(ack.get("requestId"))) {
            if (!retried) {
                retried = true;
                handler.postDelayed(() -> transmit(true), 1500);
            }
            return;
        }
        if (!"ack".equals(ack.get("type")) || !Boolean.TRUE.equals(ack.get("saved"))
                || !"background".equals(ack.get("receiver"))
                || !numberEquals(1, ack.get("v"))
                || !pendingRequest.get("courseId").equals(ack.get("courseId"))
                || !pendingRequest.get("displayName").equals(ack.get("displayName"))
                || !pendingRequest.get("checksum").equals(ack.get("checksum"))
                || !numberEquals(pendingRequest.get("bytes"), ack.get("bytes"))
                || !numberEquals(pendingRequest.get("vertexCount"), ack.get("vertexCount"))
                || !numberEquals(pendingRequest.get("armedUntil"), ack.get("armedUntil"))) {
            failTransfer("ack_mismatch", "GARMINの保存・照合結果が一致しません: " + ack.get("error")); return;
        }
        MethodChannel.Result result = pendingResult;
        Map<String, Object> response = new HashMap<>();
        response.put("deviceName", pendingDevice.getFriendlyName());
        response.put("elapsedMs", SystemClock.elapsedRealtime() - sentAt);
        clearTransfer();
        result.success(response);
    }

    private boolean numberEquals(Object a, Object b) {
        return a instanceof Number && b instanceof Number
                && ((Number) a).doubleValue() == ((Number) b).doubleValue();
    }

    private void failDeviceWaiters(String code, String text) {
        for (MethodChannel.Result waiter : new ArrayList<>(deviceWaiters)) waiter.error(code, text, null);
        deviceWaiters.clear();
    }

    private void failTransfer(String code, String text) {
        if (pendingResult == null) return;
        MethodChannel.Result result = pendingResult;
        clearTransfer();
        result.error(code, text, null);
    }

    private void clearTransfer() {
        clearAppQueryTimeout();
        if (timeout != null) handler.removeCallbacks(timeout);
        timeout = null;
        pendingResult = null;
        pendingRequest = null;
        pendingDevice = null;
        pendingApp = null;
    }

    private void clearAppQueryTimeout() {
        if (appQueryTimeout != null) handler.removeCallbacks(appQueryTimeout);
        appQueryTimeout = null;
    }

    private void clearSdkTimeout() {
        if (sdkTimeout != null) handler.removeCallbacks(sdkTimeout);
        sdkTimeout = null;
    }

    private void releaseSdk() {
        if (sdk == null) return;
        try {
            sdk.unregisterAllForEvents();
            sdk.shutdown(activity);
        } catch (Exception ignored) { }
        sdk = null;
    }

    private String message(Exception e) {
        return e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
    }

    public void close() {
        closed = true;
        handler.removeCallbacksAndMessages(null);
        clearSdkTimeout();
        failDeviceWaiters("activity_closed", "アプリが終了したため検索を中断しました。");
        failTransfer("activity_closed", "画面が終了したため転送を中断しました。");
        releaseSdk();
        channel.setMethodCallHandler(null);
    }
}
