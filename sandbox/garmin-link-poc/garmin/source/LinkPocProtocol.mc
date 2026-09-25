import Toybox.Lang;

(:background)
module LinkPocProtocol {
    function checksum(data) {
        return checksumInternal(data, false);
    }

    function checksumInternal(data, requirePrintable) {
        var a = 1l;
        var b = 0l;
        var length = data.length();
        // A full toCharArray() exhausts the fr55 background memory pool, while
        // converting one character at a time trips its 30-second watchdog.
        // Small chunks keep both peak memory and allocation count bounded.
        for (var offset = 0; offset < length; offset += 32) {
            var end = offset + 32;
            if (end > length) { end = length; }
            var chars = data.substring(offset, end).toCharArray();
            for (var i = 0; i < chars.size(); i++) {
                var c = chars[i].toNumber();
                if (requirePrintable && (c < 32 || c > 126)) { return null; }
                a = (a + c) % 65521l;
                b = (b + a) % 65521l;
            }
        }
        return (b * 65536l + a).toString();
    }

    function validEnvelope(data) {
        if (!(data instanceof Lang.Dictionary)) { return false; }
        if (!(data["type"] instanceof Lang.String)
            || !data["type"].equals("argus-poc") || data["v"] != 1) { return false; }
        if (!(data["requestId"] instanceof Lang.String) || data["requestId"].length() > 64) { return false; }
        if (!(data["courseId"] instanceof Lang.String)
            || !data["courseId"].equals("poc-square") || data["vertexCount"] != 4) { return false; }
        // Companion clients can deserialize the Unix timestamp as either
        // numeric representation, depending on the source value.
        if (!(data["armedUntil"] instanceof Lang.Number)
            && !(data["armedUntil"] instanceof Lang.Long)) { return false; }
        if (data["bytes"] != 512 && data["bytes"] != 1024 && data["bytes"] != 2048) { return false; }
        if (!(data["data"] instanceof Lang.String)) { return false; }
        if (!(data["checksum"] instanceof Lang.String)) { return false; }
        var body = data["data"];
        if (body.length() != data["bytes"]) { return false; }
        var prefix = "0,0;100,0;100,100;0,100|";
        return body.substring(0, prefix.length()).equals(prefix);
    }

    function valid(data) {
        if (!validEnvelope(data)) { return false; }
        // Validate printable ASCII and checksum in one bounded-memory pass.
        var actualChecksum = checksumInternal(data["data"], true);
        return actualChecksum != null && actualChecksum.equals(data["checksum"]);
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
