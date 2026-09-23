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
        if (!(data instanceof Lang.Dictionary)) { Background.exit(null); return; }
        try {
            if (!LinkPocProtocol.valid(data)) {
                reply(LinkPocProtocol.ack(data, false, "invalid-payload"));
                return;
            }
            Application.Storage.setValue("last", data);
            var stored = Application.Storage.getValue("last");
            if (!LinkPocProtocol.valid(stored) || !stored["requestId"].equals(data["requestId"])
                || stored["armedUntil"] != data["armedUntil"] || !stored["data"].equals(data["data"])) {
                reply(LinkPocProtocol.ack(data, false, "readback-failed"));
                return;
            }
            // ACK is formed from the data read back from persistent storage.
            reply(LinkPocProtocol.ack(stored, true, ""));
        } catch (e) {
            System.println("Link PoC receiver failed: " + e.toString());
            reply(LinkPocProtocol.ack(data, false, "storage-or-receiver-error"));
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
