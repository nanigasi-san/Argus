import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;
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
    var _lastReload = -1;
    var _geometry = null;
    var _monitor = null;
    var _armedUntil = 0;
    var _display = "READY";

    function initialize() {
        SimpleDataField.initialize();
        label = "ARGUS";
        reload();
    }

    function compute(info) {
        var now = Time.now().value();
        if (_lastReload < 0 || now - _lastReload >= 10) { reload(); }
        if (_geometry == null) { label = "ARGUS"; return _display; }
        if (now >= _armedUntil) {
            _monitor.reset();
            label = "ARGUS";
            return "EXPIRED";
        }
        if (info == null || info.timerState != Activity.TIMER_STATE_ON) {
            _monitor.reset();
            label = "ARGUS";
            return "ARMED";
        }
        if (info.currentLocation == null || info.currentLocationAccuracy == null
            || info.currentLocationAccuracy < Position.QUALITY_USABLE) {
            label = "ARGUS";
            return "GPS WAIT";
        }
        var point = _geometry.localPoint(info.currentLocation.toDegrees());
        _monitor.update(point[0], point[1], now);
        if (_monitor.takeAlert()) { alertOut(); }
        if (_monitor.state().equals("OUT")) {
            label = "MAP OUT";
            return _monitor.direction() + " " + _monitor.distance().toString() + "m";
        }
        label = "ARGUS";
        return _monitor.state().equals("CANDIDATE") ? "CHECKING" : "IN";
    }

    function reload() {
        _lastReload = Time.now().value();
        var stored = Application.Storage.getValue("course");
        if (!(stored instanceof Lang.Dictionary) || stored["requestId"] == null) { return; }
        if (_lastId != null && stored["requestId"].equals(_lastId)) { return; }
        var candidate = new ArgusGeometry(stored);
        if (!candidate.isValid()) {
            _display = "DATA ERR";
            _geometry = null;
            _monitor = null;
            return;
        }
        _lastId = stored["requestId"];
        _geometry = candidate;
        _monitor = new ArgusMonitor(candidate);
        _armedUntil = stored["armedUntil"];
        _display = candidate.count().toString() + " PT OK";
    }

    function alertOut() {
        try {
            if (Attention has :vibrate) {
                Attention.vibrate([
                    new Attention.VibeProfile(100, 500),
                    new Attention.VibeProfile(0, 250),
                    new Attention.VibeProfile(100, 500)
                ]);
            }
        } catch (e) { }
        try {
            if (Attention has :playTone) { Attention.playTone(Attention.TONE_ALERT_HI); }
        } catch (e) { }
    }
}
