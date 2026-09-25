import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Background;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
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

class ArgusField extends WatchUi.DataField {
    var _lastId = null;
    var _lastReload = -1;
    var _geometry = null;
    var _monitor = null;
    var _armedUntil = 0;
    var _receivedUntil = -1;
    var _courseName = "ARGUS";
    var _vertexCount = 0;
    var _status = "READY";
    var _detail = "";

    function initialize() {
        DataField.initialize();
        reload();
    }

    // Activity.Info arrives every second, including when another Run page is visible.
    function compute(info) {
        var now = Time.now().value();
        if (_lastReload < 0 || now - _lastReload >= 10) { reload(); }
        if (_geometry == null) {
            if (!_status.equals("DATA ERR")) { _status = "READY"; }
            _detail = "";
            return;
        }
        if (now >= _armedUntil) {
            _monitor.reset();
            _status = "EXPIRED";
            _detail = "";
            return;
        }
        if (info == null || info.timerState != Activity.TIMER_STATE_ON) {
            _monitor.reset();
            _status = "ARMED";
            _detail = "";
        } else if (info.currentLocation == null || info.currentLocationAccuracy == null
            || info.currentLocationAccuracy < Position.QUALITY_USABLE) {
            _status = _monitor.state().equals("OUT") ? "OUT" : "GPS WAIT";
            _detail = _monitor.state().equals("OUT") ? "GPS WAIT" : "";
            if (_monitor.alertDue(now)) { alertOut(); }
        } else {
            var point = _geometry.localPoint(info.currentLocation.toDegrees());
            _monitor.update(point[0], point[1], now);
            if (_monitor.alertDue(now)) { alertOut(); }
            if (_monitor.state().equals("OUT")) {
                _status = "OUT";
                _detail = directionJa(_monitor.direction()) + " " + _monitor.distance().toString() + "m";
            } else {
                _status = _monitor.state().equals("CANDIDATE") ? "CHECKING" : "IN";
                _detail = "";
            }
        }
        if (now < _receivedUntil && !_status.equals("OUT")) {
            _status = "RECEIVED";
            _detail = _vertexCount.toString() + " PT";
        }
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var center = width / 2;
        var background = getBackgroundColor();
        var foreground = background == Graphics.COLOR_WHITE
            ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
        var safeWidth = getObscurityFlags() == 0 ? width * 0.88 : width * 0.70;
        dc.setColor(foreground, background);
        dc.clear();
        if (height < 48) {
            dc.drawText(center, height / 2, Graphics.FONT_XTINY,
                fitText(dc, _status, Graphics.FONT_XTINY, safeWidth),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        if (height < 95) {
            dc.drawText(center, height * 0.27, Graphics.FONT_TINY,
                fitText(dc, _status, Graphics.FONT_TINY, safeWidth),
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(center, height * 0.62, Graphics.FONT_XTINY,
                fitText(dc, _detail, Graphics.FONT_XTINY, safeWidth),
                Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        dc.drawText(center, height * 0.12, Graphics.FONT_XTINY,
            fitText(dc, _courseName, Graphics.FONT_XTINY, safeWidth),
            Graphics.TEXT_JUSTIFY_CENTER);
        var statusFont = height >= 145 ? Graphics.FONT_LARGE : Graphics.FONT_MEDIUM;
        dc.drawText(center, height * 0.38, statusFont,
            fitText(dc, _status, statusFont, safeWidth),
            Graphics.TEXT_JUSTIFY_CENTER);
        var detailFont = height >= 145 ? Graphics.FONT_MEDIUM : Graphics.FONT_TINY;
        dc.drawText(center, height * 0.70, detailFont,
            fitText(dc, _detail, detailFont, safeWidth),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    function fitText(dc, value, font, maxWidth) {
        if (dc.getTextWidthInPixels(value, font) <= maxWidth) { return value; }
        var chars = value.toCharArray();
        var clipped = "";
        for (var i = 0; i < chars.size(); i++) {
            var next = clipped + chars[i].toString();
            if (dc.getTextWidthInPixels(next + "...", font) > maxWidth) { break; }
            clipped = next;
        }
        return clipped + "...";
    }

    function directionJa(direction) {
        var names = {"N" => "北", "NE" => "北東", "E" => "東", "SE" => "南東",
            "S" => "南", "SW" => "南西", "W" => "西", "NW" => "北西"};
        return names[direction];
    }

    function status() { return _status; }
    function detail() { return _detail; }
    function courseName() { return _courseName; }

    function reload() {
        _lastReload = Time.now().value();
        var stored = Application.Storage.getValue("course");
        if (!(stored instanceof Lang.Dictionary) || stored["requestId"] == null) { return; }
        if (_lastId != null && stored["requestId"].equals(_lastId)) { return; }
        var candidate = new ArgusGeometry(stored);
        if (!candidate.isValid()) {
            _status = "DATA ERR";
            _geometry = null;
            _monitor = null;
            return;
        }
        _lastId = stored["requestId"];
        _geometry = candidate;
        _monitor = new ArgusMonitor(candidate);
        _armedUntil = stored["armedUntil"];
        _vertexCount = candidate.count();
        _courseName = stored["displayName"] instanceof Lang.String
            ? stored["displayName"] : "ARGUS";
        var receivedAt = stored["receivedAt"];
        var now = Time.now().value();
        // Storage is polled every 10s. Start the confirmation when this field
        // notices the new course, not when the background service saves it.
        _receivedUntil = receivedAt instanceof Lang.Number
            && now >= receivedAt && now - receivedAt <= 20 ? now + 6 : -1;
    }

    function alertOut() {
        try {
            if (Attention has :vibrate) {
                Attention.vibrate([
                    new Attention.VibeProfile(100, 3000)
                ]);
            }
        } catch (e) {
            System.println("ARGUS vibration failed: " + e.toString());
        }
        try {
            if (Attention has :ToneProfile) {
                Attention.playTone({:toneProfile => [new Attention.ToneProfile(2500, 3000)]});
            } else if (Attention has :playTone) {
                Attention.playTone(Attention.TONE_ALERT_HI);
            }
        } catch (e) {
            System.println("ARGUS tone failed: " + e.toString());
        }
    }
}
