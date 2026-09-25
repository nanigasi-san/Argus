package com.argus.garminpoc;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/** Transport-only fixture, not a real competition course or navigation format. */
public final class Protocol {
    public static final String APP_ID = "e9af7de8169f4a3e8c38763cdd2e4d55";
    public static final String PREFIX = "0,0;100,0;100,100;0,100|";
    private Protocol() {}

    public static Map<String, Object> request(int bytes, long nowSeconds) {
        if (bytes != 512 && bytes != 1024 && bytes != 2048) {
            throw new IllegalArgumentException("Unsupported payload size");
        }
        StringBuilder body = new StringBuilder(PREFIX);
        while (body.length() < bytes) body.append((char) ('A' + body.length() % 26));
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("type", "argus-poc");
        request.put("v", 1);
        request.put("requestId", UUID.randomUUID().toString());
        request.put("courseId", "poc-square");
        request.put("armedUntil", (int) (nowSeconds + 3600));
        request.put("vertexCount", 4);
        request.put("bytes", bytes);
        request.put("data", body.toString());
        request.put("checksum", checksum(body.toString()));
        return request;
    }

    /** Adler-32 as unsigned decimal text, avoiding signed 32-bit cross-platform differences. */
    public static String checksum(String data) {
        long a = 1, b = 0;
        for (int i = 0; i < data.length(); i++) {
            if (data.charAt(i) > 127) throw new IllegalArgumentException("ASCII required");
            a = (a + data.charAt(i)) % 65521;
            b = (b + a) % 65521;
        }
        return Long.toString(b * 65536 + a);
    }

    public static boolean isMatchingAck(Map<String, Object> request, Map<?, ?> ack) {
        return "ack".equals(ack.get("type"))
            && Boolean.TRUE.equals(ack.get("saved"))
            && "background".equals(ack.get("receiver"))
            && equalNumber(1, ack.get("v"))
            && request.get("requestId").equals(ack.get("requestId"))
            && request.get("courseId").equals(ack.get("courseId"))
            && request.get("checksum").equals(ack.get("checksum"))
            && equalNumber((Number) request.get("bytes"), ack.get("bytes"))
            && equalNumber((Number) request.get("vertexCount"), ack.get("vertexCount"))
            && equalNumber((Number) request.get("armedUntil"), ack.get("armedUntil"));
    }

    private static boolean equalNumber(Number expected, Object actual) {
        return actual instanceof Number
            && ((Number) actual).doubleValue() == expected.doubleValue();
    }
}
