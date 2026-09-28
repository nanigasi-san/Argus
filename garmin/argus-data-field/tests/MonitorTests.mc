import Toybox.Math;
import Toybox.Application;
import Toybox.Background;
import Toybox.Test;
import Toybox.Time;

function squareCourse() {
    return {"data" => "AGW1|-100,-100;100,-100;100,100;-100,100",
        "vertexCount" => 4, "originLatE7" => 350000000,
        "originLonE7" => 1400000000};
}

(:test)
function geometryFindsBoundaryAndReturnDirection(logger) {
    var geometry = new ArgusGeometry(squareCourse());
    Test.assert(geometry.isValid());
    Test.assert(geometry.contains(0, 0));
    Test.assert(!geometry.contains(300, 0));
    var nearest = geometry.nearest(300, 0);
    Test.assert(nearest[0] > 199.99 && nearest[0] < 200.01);
    Test.assertEqual((new ArgusMonitor(geometry)).compass(nearest[1]), "W");
    return true;
}

(:test)
function monitorConfirmsAndClearsOutside(logger) {
    var monitor = new ArgusMonitor(new ArgusGeometry(squareCourse()));
    monitor.update(300, 0, 1000);
    Test.assertEqual(monitor.state(), "CANDIDATE");
    monitor.update(300, 0, 1001);
    Test.assertEqual(monitor.state(), "CANDIDATE");
    monitor.update(300, 0, 1002);
    Test.assertEqual(monitor.state(), "OUT");
    Test.assertEqual(monitor.direction(), "W");
    Test.assert(monitor.alertDue(1002));
    Test.assert(!monitor.alertDue(1005));
    Test.assert(monitor.alertDue(1006));
    monitor.update(0, 0, 1008);
    Test.assertEqual(monitor.state(), "OUT");
    monitor.update(0, 0, 1010);
    Test.assertEqual(monitor.state(), "IN");
    Test.assert(!monitor.alertDue(1012));
    return true;
}

(:test)
function gpsWaitBreaksOutsideCandidate(logger) {
    var monitor = new ArgusMonitor(new ArgusGeometry(squareCourse()));
    monitor.update(300, 0, 1000);
    Test.assertEqual(monitor.state(), "CANDIDATE");
    monitor.onGpsUnavailable();
    Test.assertEqual(monitor.state(), "ARMED");
    monitor.update(300, 0, 2000);
    Test.assertEqual(monitor.state(), "CANDIDATE");
    Test.assert(!monitor.alertDue(2000));
    monitor.update(300, 0, 2002);
    Test.assertEqual(monitor.state(), "OUT");
    return true;
}

(:test)
function gpsWaitKeepsOutButBreaksReturnCandidate(logger) {
    var monitor = new ArgusMonitor(new ArgusGeometry(squareCourse()));
    monitor.update(300, 0, 1000);
    monitor.update(300, 0, 1002);
    Test.assertEqual(monitor.state(), "OUT");
    monitor.update(0, 0, 1004);
    Test.assertEqual(monitor.state(), "OUT");
    monitor.onGpsUnavailable();
    Test.assertEqual(monitor.state(), "OUT");
    Test.assert(monitor.alertDue(1006));
    monitor.update(0, 0, 2000);
    Test.assertEqual(monitor.state(), "OUT");
    monitor.update(0, 0, 2002);
    Test.assertEqual(monitor.state(), "IN");
    return true;
}

(:test)
function geometryHandlesTenKilometreCourse(logger) {
    var course = {"data" => "AGW1|-5000,-5000;5000,-5000;5000,5000;-5000,5000",
        "vertexCount" => 4, "originLatE7" => 350000000,
        "originLonE7" => 1400000000};
    var geometry = new ArgusGeometry(course);
    Test.assert(geometry.isValid());
    Test.assert(geometry.contains(0, 0));
    Test.assert(!geometry.contains(8000, 0));
    var nearest = geometry.nearest(8000, 0);
    Test.assert(nearest[0] > 2999.9 && nearest[0] < 3000.1);
    return true;
}

(:test)
function monitorHasNoOutsideMarginAndRejectsBadCourse(logger) {
    var geometry = new ArgusGeometry(squareCourse());
    var monitor = new ArgusMonitor(geometry);
    monitor.update(95, 0, 1000);
    Test.assertEqual(monitor.state(), "IN");
    monitor.update(105, 0, 1010);
    Test.assertEqual(monitor.state(), "CANDIDATE");
    monitor.update(105, 0, 1012);
    Test.assertEqual(monitor.state(), "OUT");
    var bad = squareCourse();
    bad["vertexCount"] = 6;
    Test.assert(!(new ArgusGeometry(bad)).isValid());
    return true;
}

(:test)
function fieldShowsReceivedNameAndVertexCount(logger) {
    var course = squareCourse();
    course["requestId"] = "received-test";
    course["displayName"] = "chiba.geojson";
    course["armedUntil"] = Time.now().value() + 3600;
    course["receivedAt"] = Time.now().value() - 9;
    Application.Storage.setValue("course", course);
    var field = new ArgusField();
    field.compute(null);
    Test.assertEqual(field.courseName(), "chiba.geojson");
    Test.assertEqual(field.status(), "RECEIVED");
    Test.assertEqual(field.detail(), "4 PT");
    Application.Storage.deleteValue("course");
    return true;
}

(:test)
function fieldUsesJapaneseReturnDirection(logger) {
    var field = new ArgusField();
    Test.assertEqual(field.directionJa("NW"), "北西");
    Test.assertEqual(field.directionJa("E"), "東");
    return true;
}

(:test)
function courseIsDisabledAfterOneRunButNotBeforeIt(logger) {
    var course = squareCourse();
    course["requestId"] = "one-run-test";
    course["armedUntil"] = Time.now().value() + 3600;
    Application.Storage.setValue("course", course);
    var field = new ArgusField();
    field.compute(null);
    Test.assertEqual(field.status(), "ARMED");
    Test.assert(Application.Storage.getValue("course") != null);
    field.onTimerReset();
    Test.assert(Application.Storage.getValue("course") != null);
    Test.assert(field.claimRun(null));
    Test.assert(field.claimRun(1000));
    Test.assertEqual(Application.Storage.getValue("courseRun")["startTime"], 1000);
    // A stopped/paused timer is not the end of the activity.
    field.compute(null);
    Test.assert(Application.Storage.getValue("course") != null);
    field.onTimerReset();
    Test.assert(Application.Storage.getValue("course")["monitoringEnabled"] == false);
    Test.assert(Application.Storage.getValue("courseRun") == null);
    Test.assertEqual(field.status(), "OFF");
    Test.assert(!field.claimRun(2000));
    Application.Storage.deleteValue("course");
    return true;
}

(:test)
function oldCourseCannotBeReusedIfResetWasMissed(logger) {
    var course = squareCourse();
    course["requestId"] = "missed-reset-test";
    course["armedUntil"] = Time.now().value() + 3600;
    Application.Storage.setValue("course", course);
    var firstField = new ArgusField();
    Test.assert(firstField.claimRun(1000));
    var reloadedField = new ArgusField();
    Test.assert(reloadedField.claimRun(1000));
    Test.assert(!reloadedField.claimRun(2000));
    Test.assert(Application.Storage.getValue("course")["monitoringEnabled"] == false);
    Test.assert(Application.Storage.getValue("courseRun") == null);
    Application.Storage.deleteValue("course");
    return true;
}

(:test)
function endingOldRunDoesNotDiscardNewTransfer(logger) {
    var oldCourse = squareCourse();
    oldCourse["requestId"] = "old-run-test";
    oldCourse["armedUntil"] = Time.now().value() + 3600;
    Application.Storage.setValue("course", oldCourse);
    var field = new ArgusField();
    Test.assert(field.claimRun(1000));
    var newCourse = squareCourse();
    newCourse["requestId"] = "new-transfer-test";
    newCourse["armedUntil"] = Time.now().value() + 3600;
    Application.Storage.setValue("course", newCourse);
    field.onTimerReset();
    Test.assertEqual(Application.Storage.getValue("course")["requestId"],
        "new-transfer-test");
    Test.assert(Application.Storage.getValue("courseRun") == null);
    Application.Storage.deleteValue("course");
    return true;
}

(:test)
function twoFieldsCannotReviveDiscardedCourse(logger) {
    var course = squareCourse();
    course["requestId"] = "two-fields-test";
    course["armedUntil"] = Time.now().value() + 3600;
    Application.Storage.setValue("course", course);
    var firstField = new ArgusField();
    var secondField = new ArgusField();
    Test.assert(firstField.claimRun(1000));
    Test.assert(secondField.claimRun(1000));
    firstField.onTimerReset();
    secondField.onTimerReset();
    secondField.compute(null);
    Test.assertEqual(secondField.status(), "OFF");
    Test.assert(!secondField.claimRun(2000));
    Test.assert(Application.Storage.getValue("course")["monitoringEnabled"] == false);
    Application.Storage.deleteValue("course");
    return true;
}

(:test)
function oldFieldCannotDiscardAnotherRunClaim(logger) {
    var oldCourse = squareCourse();
    oldCourse["requestId"] = "old-field-test";
    oldCourse["armedUntil"] = Time.now().value() + 3600;
    Application.Storage.setValue("course", oldCourse);
    var oldField = new ArgusField();
    Test.assert(oldField.claimRun(1000));
    var newCourse = squareCourse();
    newCourse["requestId"] = "new-field-test";
    newCourse["armedUntil"] = Time.now().value() + 3600;
    Application.Storage.setValue("course", newCourse);
    var newField = new ArgusField();
    Test.assert(newField.claimRun(2000));
    oldField.onTimerReset();
    Test.assertEqual(Application.Storage.getValue("course")["requestId"],
        "new-field-test");
    Test.assertEqual(Application.Storage.getValue("courseRun")["requestId"],
        "new-field-test");
    newField.onTimerReset();
    Test.assert(Application.Storage.getValue("course")["monitoringEnabled"] == false);
    Application.Storage.deleteValue("course");
    return true;
}

(:test)
function runStartedBeforeDeadlineSurvivesExpiry(logger) {
    var now = Time.now().value();
    var course = squareCourse();
    course["requestId"] = "running-across-deadline";
    course["armedUntil"] = now - 5;
    Application.Storage.setValue("course", course);
    var field = new ArgusField();
    Test.assert(field.claimRun(now - 10));
    field.compute(null);
    Test.assertEqual(field.status(), "ARMED");
    Test.assert(Application.Storage.getValue("course") != null);
    field.onTimerReset();
    Test.assert(Application.Storage.getValue("course")["monitoringEnabled"] == false);
    Application.Storage.deleteValue("course");
    return true;
}

(:test)
function runStartedAfterDeadlineCannotClaimCourse(logger) {
    var now = Time.now().value();
    var course = squareCourse();
    course["requestId"] = "late-run";
    course["armedUntil"] = now - 5;
    Application.Storage.setValue("course", course);
    var field = new ArgusField();
    Test.assert(!field.claimRun(now));
    Test.assertEqual(field.status(), "EXPIRED");
    Test.assert(Application.Storage.getValue("courseRun") == null);
    Application.Storage.deleteValue("course");
    return true;
}

(:test)
function staleTemporalEventCannotDeleteReplacement(logger) {
    var now = Time.now().value();
    var course = squareCourse();
    course["requestId"] = "replacement";
    course["armedUntil"] = now + 3600;
    Application.Storage.setValue("course", course);
    Application.Storage.setValue("expiryJob",
        {"requestId" => "old-course", "armedUntil" => now - 301});
    Test.assert(!ArgusExpiry.onTemporal(now));
    Test.assertEqual(Application.Storage.getValue("course")["requestId"],
        "replacement");
    Application.Storage.deleteValue("course");
    Application.Storage.deleteValue("expiryJob");
    return true;
}

(:test)
function missedTemporalEventIsCleanedOnNextFieldWake(logger) {
    var now = Time.now().value();
    var course = squareCourse();
    course["requestId"] = "missed-expiry";
    course["armedUntil"] = now - 301;
    Application.Storage.setValue("course", course);
    Application.Storage.setValue("expiryJob",
        {"requestId" => "missed-expiry", "armedUntil" => now - 301});
    var field = new ArgusField();
    field.compute(null);
    Test.assertEqual(field.status(), "READY");
    Test.assert(Application.Storage.getValue("course") == null);
    Test.assert(Application.Storage.getValue("expiryJob") == null);
    return true;
}

(:test)
function temporalEventDeletesUnusedExpiredCourse(logger) {
    var now = Time.now().value();
    var course = squareCourse();
    course["requestId"] = "scheduled-expiry";
    course["armedUntil"] = now - 301;
    Application.Storage.setValue("course", course);
    Application.Storage.setValue("expiryJob",
        {"requestId" => "scheduled-expiry", "armedUntil" => now - 301});
    Test.assert(ArgusExpiry.onTemporal(now));
    Test.assert(Application.Storage.getValue("course") == null);
    Test.assert(Application.Storage.getValue("expiryJob") == null);
    return true;
}

(:test)
function activityCompletionDisablesOnlyItsClaimedCourse(logger) {
    var now = Time.now().value();
    var course = squareCourse();
    course["requestId"] = "completed-run";
    course["armedUntil"] = now + 3600;
    Application.Storage.setValue("course", course);
    Application.Storage.setValue("courseRun",
        {"requestId" => "completed-run", "startTime" => now - 60});
    Application.Storage.setValue("expiryJob",
        {"requestId" => "completed-run", "armedUntil" => now + 3600});
    Test.assert(ArgusExpiry.onActivityCompleted(now));
    Test.assert(Application.Storage.getValue("course")["monitoringEnabled"] == false);
    Test.assert(Application.Storage.getValue("courseRun") == null);
    Test.assert(Application.Storage.getValue("expiryJob") != null);
    Application.Storage.deleteValue("course");
    Application.Storage.deleteValue("expiryJob");
    return true;
}

(:test)
function resetDisablesActiveCourseAndKeepsItsFile(logger) {
    var now = Time.now().value();
    var course = squareCourse();
    course["requestId"] = "active-reset";
    course["displayName"] = "chiba.geojson";
    course["armedUntil"] = now + 3600;
    course["monitoringEnabled"] = true;
    Application.Storage.setValue("course", course);
    var field = new ArgusField();
    Test.assert(field.claimRun(now));
    Test.assert(ArgusExpiry.disableCourse("active-reset"));
    Test.assert(Application.Storage.getValue("courseRun") == null);
    field.reload();
    field.compute(null);
    Test.assertEqual(field.status(), "OFF");
    Test.assertEqual(field.courseName(), "chiba.geojson");
    Test.assert(!field.claimRun(now));
    Application.Storage.deleteValue("course");
    return true;
}

(:test)
function disabledCourseExpiresEvenWithAnOldRunClaim(logger) {
    var now = Time.now().value();
    var course = squareCourse();
    course["requestId"] = "disabled-expiry";
    course["armedUntil"] = now - 301;
    course["monitoringEnabled"] = false;
    Application.Storage.setValue("course", course);
    Application.Storage.setValue("courseRun",
        {"requestId" => "disabled-expiry", "startTime" => now - 400});
    Test.assert(ArgusExpiry.cleanupExpired(now));
    Test.assert(Application.Storage.getValue("course") == null);
    Test.assert(Application.Storage.getValue("courseRun") == null);
    return true;
}

(:test)
function controlAckRequiresDisableRequest(logger) {
    var request = {"type" => "argus-control", "v" => 1,
        "action" => "disable", "requestId" => "reset-test"};
    Test.assert(ArgusProtocol.validDisable(request));
    var ack = ArgusProtocol.disableAck(request, true, "");
    Test.assert(ack["disabled"] == true);
    Test.assertEqual(ack["requestId"], "reset-test");
    request["action"] = "enable";
    Test.assert(!ArgusProtocol.validDisable(request));
    return true;
}

(:test)
function invalidCourseMetadataCannotReceiveSuccessAck(logger) {
    var course = squareCourse();
    course["type"] = "argus-course";
    course["v"] = 1;
    course["requestId"] = "invalid-meta";
    course["courseId"] = "invalid-meta";
    course["displayName"] = "invalid.geojson";
    course["bytes"] = course["data"].length();
    course["checksum"] = ArgusProtocol.checksum(course["data"]);
    course["armedUntil"] = Time.now().value() + 3600;
    Test.assert(ArgusProtocol.valid(course));
    course["originLatE7"] = null;
    Test.assert(!ArgusProtocol.valid(course));
    course["originLatE7"] = 350000000;
    course["armedUntil"] = null;
    Test.assert(!ArgusProtocol.valid(course));
    course["armedUntil"] = Time.now().value() + 3600;
    course["data"] = "AGW1|1,2;3,4";
    course["bytes"] = course["data"].length();
    course["checksum"] = ArgusProtocol.checksum(course["data"]);
    Test.assert(!ArgusProtocol.valid(course));
    return true;
}

(:test)
function protocolValidatesHundredVertexCourseOnFr55(logger) {
    var body = "AGW1|";
    for (var i = 0; i < 100; i++) {
        if (i > 0) { body += ";"; }
        body += i.toString() + "," + (i % 10).toString();
    }
    var course = {"type" => "argus-course", "v" => 1,
        "requestId" => "hundred-vertices", "courseId" => "hundred-vertices",
        "displayName" => "hundred.geojson", "armedUntil" => Time.now().value() + 3600,
        "vertexCount" => 100, "originLatE7" => 350000000,
        "originLonE7" => 1400000000, "bytes" => body.length(),
        "data" => body, "checksum" => ArgusProtocol.checksum(body)};
    Test.assert(ArgusProtocol.valid(course));
    return true;
}

(:test)
function oldCompletionCannotDiscardNewTransfer(logger) {
    var now = Time.now().value();
    var course = squareCourse();
    course["requestId"] = "new-after-old-run";
    course["armedUntil"] = now + 3600;
    Application.Storage.setValue("course", course);
    Application.Storage.setValue("courseRun",
        {"requestId" => "old-completed-run", "startTime" => now - 60});
    Test.assert(!ArgusExpiry.onActivityCompleted(now));
    Test.assertEqual(Application.Storage.getValue("course")["requestId"],
        "new-after-old-run");
    Application.Storage.deleteValue("course");
    Application.Storage.deleteValue("courseRun");
    return true;
}

(:test)
function expiryScheduleRegistersTemporalEvent(logger) {
    var course = {"requestId" => "scheduled-event-test",
        "armedUntil" => Time.now().value() + 3600};
    ArgusExpiry.schedule(course);
    Test.assert(Background.getTemporalEventRegisteredTime() != null);
    Test.assertEqual(Application.Storage.getValue("expiryJob")["requestId"],
        "scheduled-event-test");
    Background.deleteTemporalEvent();
    Application.Storage.deleteValue("expiryJob");
    return true;
}

(:test)
function missedEventIsCleanedWhenAppStarts(logger) {
    var course = squareCourse();
    course["requestId"] = "wake-cleanup";
    course["armedUntil"] = Time.now().value() - 301;
    Application.Storage.setValue("course", course);
    new ArgusApp();
    Test.assert(Application.Storage.getValue("course") == null);
    Test.assert(Background.getActivityCompletedEventRegistered());
    return true;
}
