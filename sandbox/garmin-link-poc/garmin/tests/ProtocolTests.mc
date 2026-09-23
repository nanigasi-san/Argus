import Toybox.Test;

(:test)
function checksumKnownVectors(logger) {
    Test.assertEqual(LinkPocProtocol.checksum(""), "1");
    Test.assertEqual(LinkPocProtocol.checksum("Wikipedia"), "300286872");
    return true;
}

(:test)
function rejectsInvalidPayload(logger) {
    Test.assert(!LinkPocProtocol.valid(null));
    Test.assert(!LinkPocProtocol.valid({"type" => "other"}));
    return true;
}

(:test)
function validatesPayloadAndDetectsCorruption(logger) {
    var body = "0,0;100,0;100,100;0,100|";
    while (body.length() < 512) { body += "A"; }
    var data = {"type" => "argus-poc", "v" => 1, "requestId" => "test",
        "courseId" => "poc-square", "vertexCount" => 4, "armedUntil" => 1700003600,
        "bytes" => 512, "data" => body, "checksum" => LinkPocProtocol.checksum(body)};
    Test.assert(LinkPocProtocol.valid(data));
    data["checksum"] = "0";
    Test.assert(!LinkPocProtocol.valid(data));
    return true;
}
