import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

(:background)
module ArgusCourseLifecycle {
    function matches(course, requestId) {
        return course instanceof Lang.Dictionary
            && course["requestId"] instanceof Lang.String
            && requestId instanceof Lang.String
            && course["requestId"].equals(requestId);
    }

    function clearRunClaim(requestId) {
        var claim = Application.Storage.getValue("courseRun");
        if (matches(claim, requestId)) {
            Application.Storage.deleteValue("courseRun");
        }
    }

    // A late Run-completion callback must never remove a newer transfer.
    function removeCourse(requestId) {
        var course = Application.Storage.getValue("course");
        if (!matches(course, requestId)) { return false; }
        Application.Storage.deleteValue("course");
        if (matches(Application.Storage.getValue("course"), requestId)) {
            return false;
        }
        clearRunClaim(requestId);
        return true;
    }

    function onActivityCompleted() {
        var claim = Application.Storage.getValue("courseRun");
        if (!(claim instanceof Lang.Dictionary)
            || !(claim["requestId"] instanceof Lang.String)) { return false; }
        try {
            var info = Activity.getActivityInfo();
            var running = info != null
                && (info.timerState == Activity.TIMER_STATE_ON
                    || info.timerState == Activity.TIMER_STATE_STOPPED
                    || info.timerState == Activity.TIMER_STATE_PAUSED);
            if (running
                && (claim["startTime"] == null || (info.startTime != null
                    && info.startTime.value() == claim["startTime"]))) {
                return false;
            }
        } catch (e) {
            System.println("ARGUS completion check failed: " + e.toString());
            return false;
        }
        var currentClaim = Application.Storage.getValue("courseRun");
        if (!matches(currentClaim, claim["requestId"])
            || currentClaim["startTime"] != claim["startTime"]) { return false; }
        if (removeCourse(claim["requestId"])) { return true; }
        clearRunClaim(claim["requestId"]);
        return false;
    }
}
