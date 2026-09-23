import Toybox.Lang;

(:background)
module ArgusProtocol {
    function checksum(data) {
        var a = 1l;
        var b = 0l;
        var length = data.length();
        for (var offset = 0; offset < length; offset += 32) {
            var end = offset + 32;
            if (end > length) { end = length; }
            var chars = data.substring(offset, end).toCharArray();
            for (var i = 0; i < chars.size(); i++) {
                var c = chars[i].toNumber();
                if (c < 32 || c > 126) { return null; }
                a = (a + c) % 65521l;
                b = (b + a) % 65521l;
            }
        }
        return (b * 65536l + a).toString();
    }

    function validEnvelope(data) {
        if (!(data instanceof Lang.Dictionary)) { return false; }
        if (!(data["type"] instanceof Lang.String) || !data["type"].equals("argus-course") || data["v"] != 1) { return false; }
        if (!(data["requestId"] instanceof Lang.String) || data["requestId"].length() > 64) { return false; }
        if (!(data["courseId"] instanceof Lang.String) || data["courseId"].length() > 64) { return false; }
        if (data["vertexCount"] < 3 || data["vertexCount"] > 100) { return false; }
        if (data["bytes"] < 1 || data["bytes"] > 2048) { return false; }
        if (!(data["data"] instanceof Lang.String) || data["data"].length() != data["bytes"]) { return false; }
        if (!(data["checksum"] instanceof Lang.String)) { return false; }
        var prefix = "AGW1|";
        return data["data"].substring(0, prefix.length()).equals(prefix);
    }

    function valid(data) {
        if (!validEnvelope(data)) { return false; }
        var actual = checksum(data["data"]);
        return actual != null && actual.equals(data["checksum"]);
    }

    function ack(data, saved, error) {
        return {
            "type" => "ack", "v" => 1, "receiver" => "background",
            "requestId" => data["requestId"], "courseId" => data["courseId"],
            "saved" => saved, "bytes" => data["bytes"],
            "vertexCount" => data["vertexCount"], "checksum" => data["checksum"],
            "armedUntil" => data["armedUntil"], "error" => error
        };
    }
}
