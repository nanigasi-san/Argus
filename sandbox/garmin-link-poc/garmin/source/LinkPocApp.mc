import Toybox.Application;
import Toybox.Background;
import Toybox.WatchUi;

(:background)
class LinkPocApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }

    function getInitialView() {
        // Open this data field once to enable reception when it is not displayed.
        Background.registerForPhoneAppMessageEvent();
        return [new LinkPocField()];
    }

    function getServiceDelegate() { return [new LinkPocReceiver()]; }
}

class LinkPocField extends WatchUi.SimpleDataField {
    var _lastId = null;
    function initialize() {
        SimpleDataField.initialize();
        label = "LINK POC";
        value = "READY";
        reload();
    }
    function compute(info) { reload(); }
    function reload() {
        var stored = Application.Storage.getValue("last");
        if (stored != null && stored["requestId"] != _lastId) {
            _lastId = stored["requestId"];
            value = stored["bytes"].toString() + " B OK";
        }
    }
}
