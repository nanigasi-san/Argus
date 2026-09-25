import Toybox.Application;
import Toybox.Lang;
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
    var data = null;
    for (var sizeIndex = 0; sizeIndex < 3; sizeIndex++) {
        var bytes = [512, 1024, 2048][sizeIndex];
        var body = "0,0;100,0;100,100;0,100|";
        while (body.length() < bytes) { body += "A"; }
        // Build protocol strings at runtime to match deserialized phone messages.
        data = {"type" => "xargus-poc".substring(1, 10), "v" => 1, "requestId" => "test",
            "courseId" => "xpoc-square".substring(1, 11), "vertexCount" => 4, "armedUntil" => 1700003600,
            "bytes" => bytes, "data" => body, "checksum" => LinkPocProtocol.checksum(body)};
        Test.assert(data["armedUntil"] instanceof Lang.Number);
        Test.assert(LinkPocProtocol.valid(data));

        data["armedUntil"] = 1700003600l;
        Test.assert(LinkPocProtocol.valid(data));
    }
    data["checksum"] = "0";
    Test.assert(LinkPocProtocol.validEnvelope(data));
    Test.assert(!LinkPocProtocol.valid(data));
    return true;
}

(:test)
function dataFieldReturnsDisplayValue(logger) {
    Application.Storage.deleteValue("last");
    var field = new LinkPocField();
    Test.assertEqual(field.compute(null), "READY");

    Application.Storage.setValue("last", {"requestId" => "display-test", "bytes" => 512});
    Test.assertEqual(field.compute(null), "512 B OK");
    Application.Storage.deleteValue("last");
    return true;
}
