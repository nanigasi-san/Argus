import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

(:background)
class LinkPocReceiver extends System.ServiceDelegate {
    function initialize() { ServiceDelegate.initialize(); }

    function onPhoneAppMessage(message) {
        var data = message.data;
        var expected = null;
        if (!(data instanceof Lang.Dictionary)) { Background.exit(null); return; }
        try {
            // Perform cheap structural checks before writing. The expensive
            // printable/checksum pass is done once, on the Storage read-back.
            if (!LinkPocProtocol.validEnvelope(data)) {
                reply(LinkPocProtocol.ack(data, false, "invalid-payload"));
                return;
            }
            // Keep only the small fields needed for read-back comparison so the
            // incoming payload can be released before Storage allocates a copy.
            expected = {
                "requestId" => data["requestId"], "courseId" => data["courseId"],
                "bytes" => data["bytes"], "vertexCount" => data["vertexCount"],
                "checksum" => data["checksum"], "armedUntil" => data["armedUntil"]
            };
            Application.Storage.setValue("pending", data);
            data = null;
            message = null;
            var stored = Application.Storage.getValue("pending");
            if (!LinkPocProtocol.valid(stored)
                || !stored["requestId"].equals(expected["requestId"])
                || stored["armedUntil"] != expected["armedUntil"]
                || !stored["checksum"].equals(expected["checksum"])) {
                Application.Storage.deleteValue("pending");
                reply(LinkPocProtocol.ack(expected, false, "readback-failed"));
                return;
            }
            // Promote the validated Storage read-back without recalculating its
            // checksum, then ACK from that same validated value.
            Application.Storage.setValue("last", stored);
            Application.Storage.deleteValue("pending");
            reply(LinkPocProtocol.ack(stored, true, ""));
        } catch (e) {
            System.println("Link PoC receiver failed: " + e.toString());
            if (expected != null) {
                reply(LinkPocProtocol.ack(expected, false, "storage-or-receiver-error"));
            } else if (data != null) {
                reply(LinkPocProtocol.ack(data, false, "storage-or-receiver-error"));
            } else {
                Background.exit(null);
            }
        }
    }

    function reply(response) {
        try {
            Communications.transmit(response, null, new LinkPocAckListener());
        } catch (e) {
            System.println("Link PoC ACK failed: " + e.toString());
            Background.exit(null);
        }
    }
}

(:background)
class LinkPocAckListener extends Communications.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() { Background.exit(null); }
    function onError() { Background.exit(null); }
}
