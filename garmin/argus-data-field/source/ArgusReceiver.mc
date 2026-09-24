import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

(:background)
class ArgusReceiver extends System.ServiceDelegate {
    function initialize() { ServiceDelegate.initialize(); }

    function onPhoneAppMessage(message) {
        var data = message.data;
        var expected = null;
        if (!(data instanceof Lang.Dictionary)) { Background.exit(null); return; }
        try {
            if (!ArgusProtocol.validEnvelope(data)) {
                reply(ArgusProtocol.ack(data, false, "invalid-payload")); return;
            }
            expected = {
                "requestId" => data["requestId"], "courseId" => data["courseId"],
                "bytes" => data["bytes"], "vertexCount" => data["vertexCount"],
                "checksum" => data["checksum"], "armedUntil" => data["armedUntil"]
            };
            Application.Storage.setValue("pending", data);
            data = null;
            message = null;
            var stored = Application.Storage.getValue("pending");
            if (!(stored instanceof Lang.Dictionary) || !ArgusProtocol.valid(stored)
                || !stored["requestId"].equals(expected["requestId"])
                || stored["armedUntil"] != expected["armedUntil"]
                || !stored["checksum"].equals(expected["checksum"])) {
                Application.Storage.deleteValue("pending");
                reply(ArgusProtocol.ack(expected, false, "readback-failed")); return;
            }
            Application.Storage.setValue("course", stored);
            Application.Storage.deleteValue("pending");
            reply(ArgusProtocol.ack(stored, true, ""));
        } catch (e) {
            System.println("ARGUS receiver failed: " + e.toString());
            if (expected != null) { reply(ArgusProtocol.ack(expected, false, "storage-error")); }
            else { Background.exit(null); }
        }
    }

    function reply(response) {
        try { Communications.transmit(response, null, new ArgusAckListener()); }
        catch (e) { Background.exit(null); }
    }
}

(:background)
class ArgusAckListener extends Communications.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() { Background.exit(null); }
    function onError() { Background.exit(null); }
}
