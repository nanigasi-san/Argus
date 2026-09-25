import Toybox.Math;

class ArgusMonitor {
    var _geometry;
    var _state = "ARMED";
    var _lastCheck = -1;
    var _outsideCount = 0;
    var _insideCount = 0;
    var _candidateSince = -1;
    var _direction = "N";
    var _distance = 0;
    var _lastAlert = -1;

    function initialize(geometry) { _geometry = geometry; }

    function state() { return _state; }
    function distance() { return _distance; }
    function direction() { return _direction; }

    function alertDue(nowSeconds) {
        if (!_state.equals("OUT")) { return false; }
        // A three-second alert followed by a one-second break while OUT.
        if (_lastAlert >= 0 && nowSeconds - _lastAlert < 4) { return false; }
        _lastAlert = nowSeconds;
        return true;
    }

    function reset() {
        _state = "ARMED";
        _lastCheck = -1;
        _outsideCount = 0;
        _insideCount = 0;
        _candidateSince = -1;
        _lastAlert = -1;
    }

    function update(x, y, nowSeconds) {
        var interval = (_state.equals("CANDIDATE") || _state.equals("OUT")) ? 2 : 10;
        if (_lastCheck >= 0 && nowSeconds - _lastCheck < interval) { return; }
        _lastCheck = nowSeconds;
        var inside = _geometry.contains(x, y);
        var nearest = null;
        if (!inside) {
            nearest = _geometry.nearest(x, y);
            // A small inner buffer suppresses noisy fixes on the boundary.
            if (nearest[0] <= 10.0) { inside = true; }
        }
        if (inside) {
            _outsideCount = 0;
            _candidateSince = -1;
            if (_state.equals("OUT")) {
                _insideCount++;
                if (_insideCount >= 2) { _state = "IN"; _lastAlert = -1; }
            } else {
                _state = "IN";
                _insideCount = 0;
            }
            return;
        }

        _insideCount = 0;
        _distance = nearest[0].toNumber();
        _direction = compass(nearest[1]);
        if (_state.equals("OUT")) { return; }
        if (_candidateSince < 0) { _candidateSince = nowSeconds; }
        _outsideCount++;
        if (_outsideCount >= 2 && nowSeconds - _candidateSince >= 2) {
            _state = "OUT";
        } else {
            _state = "CANDIDATE";
        }
    }

    function compass(bearing) {
        var sector = Math.floor((bearing * 180.0 / Math.PI + 22.5) / 45.0).toNumber() % 8;
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][sector];
    }
}
