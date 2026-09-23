import Toybox.Lang;

(:background)
module LinkPocProtocol {
    function checksum(data) {
        var a = 1l;
        var b = 0l;
        for (var i = 0; i < data.length(); i++) {
            a = (a + data.substring(i, i + 1).toCharArray()[0].toNumber()) % 65521l;
            b = (b + a) % 65521l;
        }
        return (b * 65536l + a).toString();
    }

    function valid(data) {
        if (!(data instanceof Lang.Dictionary)) { return false; }
        if (data["type"] != "argus-poc" || data["v"] != 1) { return false; }
        if (!(data["requestId"] instanceof Lang.String) || data["requestId"].length() > 64) { return false; }
        if (data["courseId"] != "poc-square" || data["vertexCount"] != 4) { return false; }
        if (!(data["armedUntil"] instanceof Lang.Number)) { return false; }
        if (data["bytes"] != 512 && data["bytes"] != 1024 && data["bytes"] != 2048) { return false; }
        if (!(data["data"] instanceof Lang.String)) { return false; }
        var body = data["data"];
        if (body.length() != data["bytes"]) { return false; }
        var prefix = "0,0;100,0;100,100;0,100|";
        if (!body.substring(0, prefix.length()).equals(prefix)) { return false; }
        // Restrict the test body to printable ASCII, so bytes == characters.
        for (var i = 0; i < body.length(); i++) {
            var c = body.substring(i, i + 1).toCharArray()[0].toNumber();
            if (c < 32 || c > 126) { return false; }
        }
        return checksum(body).equals(data["checksum"]);
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
