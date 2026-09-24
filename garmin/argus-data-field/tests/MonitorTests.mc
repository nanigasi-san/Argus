import Toybox.Math;
import Toybox.Test;

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
    Test.assert(monitor.takeAlert());
    Test.assert(!monitor.takeAlert());
    monitor.update(0, 0, 1004);
    Test.assertEqual(monitor.state(), "OUT");
    monitor.update(0, 0, 1006);
    Test.assertEqual(monitor.state(), "IN");
    return true;
}

(:test)
function monitorBuffersBoundaryAndRejectsBadCourse(logger) {
    var geometry = new ArgusGeometry(squareCourse());
    var monitor = new ArgusMonitor(geometry);
    monitor.update(105, 0, 1000);
    Test.assertEqual(monitor.state(), "IN");
    var bad = squareCourse();
    bad["vertexCount"] = 6;
    Test.assert(!(new ArgusGeometry(bad)).isValid());
    return true;
}
