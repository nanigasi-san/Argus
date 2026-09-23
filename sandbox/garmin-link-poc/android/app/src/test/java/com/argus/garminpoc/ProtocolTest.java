package com.argus.garminpoc;

import org.junit.Test;
import java.util.*;
import java.nio.charset.StandardCharsets;
import java.util.zip.Adler32;
import static org.junit.Assert.*;

public class ProtocolTest {
    private Map<String, Object> ack(Map<String, Object> request) {
        Map<String, Object> result = new HashMap<>(request);
        result.put("type", "ack"); result.put("saved", true); result.put("receiver", "background");
        result.remove("data"); return result;
    }
    @Test public void payloadSizesAndChecksumMatchJavaStandardLibrary() {
        for (int bytes : new int[]{512, 1024, 2048}) {
            Map<String, Object> request = Protocol.request(bytes, 1700000000);
            byte[] data = ((String) request.get("data")).getBytes(StandardCharsets.US_ASCII);
            assertEquals(bytes, data.length);
            Adler32 reference = new Adler32(); reference.update(data);
            assertEquals(Long.toString(reference.getValue()), request.get("checksum"));
        }
    }
    @Test public void acceptsOnlySavedMatchingBackgroundAck() {
        Map<String, Object> request = Protocol.request(512, 1700000000);
        assertTrue(Protocol.isMatchingAck(request, ack(request)));
        assertFalse(Protocol.isMatchingAck(request, request));
        for (String field : new String[]{"requestId", "courseId", "checksum", "bytes", "vertexCount", "armedUntil", "saved", "receiver", "v", "type"}) {
            Map<String, Object> changed = ack(request); changed.remove(field);
            assertFalse(field, Protocol.isMatchingAck(request, changed));
        }
    }
    @Test public void staleRetryAndCorruptedChecksumCannotPass() {
        Map<String, Object> first = Protocol.request(1024, 1700000000);
        Map<String, Object> retry = Protocol.request(1024, 1700000000);
        assertFalse(Protocol.isMatchingAck(retry, ack(first)));
        Map<String, Object> corrupted = ack(first); corrupted.put("checksum", "0");
        assertFalse(Protocol.isMatchingAck(first, corrupted));
        corrupted = ack(first); corrupted.put("saved", false);
        assertFalse(Protocol.isMatchingAck(first, corrupted));
        corrupted = ack(first); corrupted.put("bytes", 1024.5);
        assertFalse(Protocol.isMatchingAck(first, corrupted));
    }
    @Test public void sdkLongValuesAreAccepted() {
        Map<String, Object> request = Protocol.request(2048, 1700000000);
        Map<String, Object> response = ack(request);
        for (String field : new String[]{"v", "bytes", "vertexCount", "armedUntil"}) response.put(field, ((Number) response.get(field)).longValue());
        assertTrue(Protocol.isMatchingAck(request, response));
    }
    @Test(expected = IllegalArgumentException.class) public void rejectsUnsupportedSize() { Protocol.request(8192, 1700000000); }

    @Test public void kotlinRuntimeRequiredByGarminSdkIsAvailable() throws Exception {
        assertNotNull(Class.forName("kotlin.jvm.internal.Intrinsics"));
    }
}
