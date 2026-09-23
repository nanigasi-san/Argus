import Toybox.Application;
import Toybox.Background;
import Toybox.WatchUi;

(:background)
class ArgusApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
        if (!Background.getPhoneAppMessageEventRegistered()) {
            Background.registerForPhoneAppMessageEvent();
        }
    }

    function getInitialView() { return [new ArgusField()]; }
    function getServiceDelegate() { return [new ArgusReceiver()]; }
}

class ArgusField extends WatchUi.SimpleDataField {
    var _lastId = null;
    var _display = "READY";

    function initialize() {
        SimpleDataField.initialize();
        label = "ARGUS";
        reload();
    }

    function compute(info) {
        reload();
        return _display;
    }

    function reload() {
        var stored = Application.Storage.getValue("course");
        if (stored != null && stored["requestId"] != _lastId) {
            _lastId = stored["requestId"];
            _display = stored["vertexCount"].toString() + " PT OK";
        }
    }
}
