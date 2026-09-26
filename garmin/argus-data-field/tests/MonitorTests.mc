import Toybox.Math;
import Toybox.Application;
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
function courseIsDiscardedAfterOneRunButNotBeforeIt(logger) {
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
    Test.assert(Application.Storage.getValue("course") == null);
    Test.assert(Application.Storage.getValue("courseRun") == null);
    Test.assertEqual(field.status(), "READY");
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
    Test.assert(Application.Storage.getValue("course") == null);
    Test.assert(Application.Storage.getValue("courseRun") == null);
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
    Test.assertEqual(secondField.status(), "READY");
    Test.assert(!secondField.claimRun(2000));
    Test.assert(Application.Storage.getValue("course") == null);
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
    Test.assert(Application.Storage.getValue("course") == null);
    return true;
}
