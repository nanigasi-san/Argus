import Toybox.Math;

// The phone sends local east/north metres around a WGS84 origin. Keep only
// two small vertex arrays in Data Field memory; parse ASCII in bounded chunks.
class ArgusGeometry {
    var _xs = [];
    var _ys = [];
    var _originLat;
    var _originLon;
    var _metresPerLon;
    var _valid = false;

    function initialize(course) {
        if (course == null || course["data"] == null
            || course["vertexCount"] == null
            || course["originLatE7"] == null || course["originLonE7"] == null) { return; }
        var body = course["data"];
        if (body.length() < 6 || !body.substring(0, 5).equals("AGW1|")) { return; }
        _originLat = course["originLatE7"] / 10000000.0;
        _originLon = course["originLonE7"] / 10000000.0;
        _metresPerLon = 111320.0 * Math.cos(_originLat * Math.PI / 180.0);
        var value = 0;
        var sign = 1;
        var digits = 0;
        var haveX = false;
        var x = 0;
        var length = body.length();
        for (var offset = 5; offset < length; offset += 32) {
            var end = offset + 32;
            if (end > length) { end = length; }
            var chars = body.substring(offset, end).toCharArray();
            for (var i = 0; i < chars.size(); i++) {
                var code = chars[i].toNumber();
                if (code == 45 && digits == 0 && sign == 1) { sign = -1; continue; }
                if (code >= 48 && code <= 57) {
                    value = value * 10 + code - 48;
                    if (value > 32768) { return; }
                    digits++;
                    continue;
                }
                if (digits == 0) { return; }
                if (code == 44 && !haveX) {
                    x = value * sign;
                    haveX = true;
                } else if (code == 59 && haveX) {
                    _xs.add(x);
                    _ys.add(value * sign);
                    haveX = false;
                } else { return; }
                value = 0;
                sign = 1;
                digits = 0;
            }
        }
        if (!haveX || digits == 0) { return; }
        _xs.add(x);
        _ys.add(value * sign);
        _valid = _xs.size() >= 3 && _xs.size() == course["vertexCount"];
    }

    function isValid() { return _valid; }
    function count() { return _xs.size(); }

    function localPoint(degrees) {
        return [
            (degrees[1] - _originLon) * _metresPerLon,
            (degrees[0] - _originLat) * 110540.0
        ];
    }

    function contains(x, y) {
        var inside = false;
        var previous = _xs.size() - 1;
        for (var i = 0; i < _xs.size(); i++) {
            var xi = _xs[i];
            var yi = _ys[i];
            var xj = _xs[previous];
            var yj = _ys[previous];
            if ((yi > y) != (yj > y)) {
                var intersection = xi + (y - yi) * (xj - xi) / (yj - yi);
                if (x < intersection) { inside = !inside; }
            }
            previous = i;
        }
        return inside;
    }

    // Returns [distance metres, absolute bearing radians clockwise from north].
    function nearest(x, y) {
        var bestSquared = null;
        var bestDx = 0.0;
        var bestDy = 0.0;
        var previous = _xs.size() - 1;
        for (var i = 0; i < _xs.size(); i++) {
            var ax = _xs[previous];
            var ay = _ys[previous];
            var dx = _xs[i] - ax;
            var dy = _ys[i] - ay;
            var lengthSquared = dx * dx + dy * dy;
            var t = 0.0;
            if (lengthSquared > 0) {
                t = ((x - ax) * dx + (y - ay) * dy) / (lengthSquared * 1.0);
                if (t < 0) { t = 0.0; }
                if (t > 1) { t = 1.0; }
            }
            var toX = ax + t * dx - x;
            var toY = ay + t * dy - y;
            var squared = toX * toX + toY * toY;
            if (bestSquared == null || squared < bestSquared) {
                bestSquared = squared;
                bestDx = toX;
                bestDy = toY;
            }
            previous = i;
        }
        var bearing = Math.atan2(bestDx, bestDy);
        if (bearing < 0) { bearing += 2 * Math.PI; }
        return [Math.sqrt(bestSquared), bearing];
    }
}
