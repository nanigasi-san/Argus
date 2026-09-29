import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
class ArgusReceiver extends System.ServiceDelegate {
    function initialize() { ServiceDelegate.initialize(); }

    function onPhoneAppMessage(message) {
        var data = message.data;
        var expected = null;
        var control = null;
        if (!(data instanceof Lang.Dictionary)) { Background.exit(null); return; }
        try {
            if (data["type"] instanceof Lang.String
                && data["type"].equals("argus-control")) {
                if (!ArgusProtocol.validClear(data)) {
                    reply(ArgusProtocol.clearAck(data, false, "invalid-control")); return;
                }
                control = data;
                var currentCourse = Application.Storage.getValue("course");
                if (currentCourse instanceof Lang.Dictionary) {
                    if (!(currentCourse["requestId"] instanceof Lang.String)
                        || !ArgusCourseLifecycle.removeCourse(currentCourse["requestId"])) {
                        reply(ArgusProtocol.clearAck(data, false, "clear-readback-failed")); return;
                    }
                }
                reply(ArgusProtocol.clearAck(data, true, "")); return;
            }
            if (!ArgusProtocol.validEnvelope(data)) {
                reply(ArgusProtocol.ack(data, false, "invalid-payload")); return;
            }
            expected = {
                "requestId" => data["requestId"], "courseId" => data["courseId"],
                "displayName" => data["displayName"],
                "bytes" => data["bytes"], "vertexCount" => data["vertexCount"],
                "checksum" => data["checksum"], "armedUntil" => data["armedUntil"],
                "originLatE7" => data["originLatE7"],
                "originLonE7" => data["originLonE7"]
            };
            if (data["armedUntil"] <= Time.now().value()) {
                reply(ArgusProtocol.ack(expected, false, "expired-payload")); return;
            }
            data["receivedAt"] = Time.now().value();
            data["monitoringEnabled"] = true;
            Application.Storage.setValue("pending", data);
            data = null;
            message = null;
            var stored = Application.Storage.getValue("pending");
            if (!(stored instanceof Lang.Dictionary) || !ArgusProtocol.valid(stored)
                || !stored["requestId"].equals(expected["requestId"])
                || stored["armedUntil"] != expected["armedUntil"]
                || stored["originLatE7"] != expected["originLatE7"]
                || stored["originLonE7"] != expected["originLonE7"]
                || !stored["checksum"].equals(expected["checksum"])
                || (expected["displayName"] != null
                    && !stored["displayName"].equals(expected["displayName"]))) {
                Application.Storage.deleteValue("pending");
                reply(ArgusProtocol.ack(expected, false, "readback-failed")); return;
            }
            Application.Storage.setValue("course", stored);
            var saved = Application.Storage.getValue("course");
            if (!(saved instanceof Lang.Dictionary) || !ArgusProtocol.valid(saved)
                || !saved["requestId"].equals(expected["requestId"])
                || saved["armedUntil"] != expected["armedUntil"]
                || saved["originLatE7"] != expected["originLatE7"]
                || saved["originLonE7"] != expected["originLonE7"]
                || saved["monitoringEnabled"] != true
                || (expected["displayName"] != null
                    && !saved["displayName"].equals(expected["displayName"]))) {
                Application.Storage.deleteValue("pending");
                reply(ArgusProtocol.ack(expected, false, "course-readback-failed")); return;
            }
            Application.Storage.deleteValue("pending");
            reply(ArgusProtocol.ack(saved, true, ""));
        } catch (e) {
            System.println("ARGUS receiver failed: " + e.toString());
            if (control != null) {
                reply(ArgusProtocol.clearAck(control, false, "storage-error"));
            } else if (expected != null) { reply(ArgusProtocol.ack(expected, false, "storage-error")); }
            else { Background.exit(null); }
        }
    }

    function reply(response) {
        try { Communications.transmit(response, null, new ArgusAckListener()); }
        catch (e) { Background.exit(null); }
    }

    function onActivityCompleted(activity) {
        try { ArgusCourseLifecycle.onActivityCompleted(); }
        catch (e) { System.println("ARGUS Run completion failed: " + e.toString()); }
        Background.exit(null);
    }

    // Ignore an event left registered by an older Data Field version.
    function onTemporalEvent() { Background.exit(null); }
}

(:background)
class ArgusAckListener extends Communications.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() { Background.exit(null); }
    function onError() { Background.exit(null); }
}
