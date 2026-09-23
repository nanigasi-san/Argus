import Toybox.Application;
import Toybox.Background;
import Toybox.WatchUi;

(:background)
class LinkPocApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
        // Event registration belongs to the application lifecycle, not view
        // creation. This keeps phone-message delivery active after Run exits.
        if (!Background.getPhoneAppMessageEventRegistered()) {
            Background.registerForPhoneAppMessageEvent();
        }
    }

    function getInitialView() {
        return [new LinkPocField()];
    }

    function getServiceDelegate() { return [new LinkPocReceiver()]; }
}

class LinkPocField extends WatchUi.SimpleDataField {
    var _lastId = null;
    var _display = "READY";

    function initialize() {
        SimpleDataField.initialize();
        label = "LINK POC";
        reload();
    }

    function compute(info) {
        reload();
        return _display;
    }

    function reload() {
        var stored = Application.Storage.getValue("last");
        if (stored != null && stored["requestId"] != _lastId) {
            _lastId = stored["requestId"];
            _display = stored["bytes"].toString() + " B OK";
        }
    }
}
