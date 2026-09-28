import Toybox.Activity;
import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
module ArgusExpiry {
    const CLEANUP_GRACE_SECONDS = 300;

    function matches(course, requestId) {
        return course instanceof Lang.Dictionary
            && course["requestId"] instanceof Lang.String
            && requestId instanceof Lang.String
            && course["requestId"].equals(requestId);
    }

    function hasActiveRun(course) {
        if (course["monitoringEnabled"] == false) { return false; }
        var claim = Application.Storage.getValue("courseRun");
        var claimed = matches(claim, course["requestId"]);
        // A Run may have just started before the Data Field persisted its claim.
        try {
            var info = Activity.getActivityInfo();
            if (info != null && info.timerState == Activity.TIMER_STATE_OFF) {
                return false;
            }
            if (info != null && info.startTime != null) {
                var recording = info.timerState == Activity.TIMER_STATE_ON
                    || info.timerState == Activity.TIMER_STATE_STOPPED
                    || info.timerState == Activity.TIMER_STATE_PAUSED;
                var started = info.startTime.value();
                var receivedAt = course["receivedAt"];
                var sameClaim = claimed && (!(claim["startTime"] instanceof Lang.Number)
                    || claim["startTime"] == started);
                var startedAfterReceipt = !(receivedAt instanceof Lang.Number)
                    || started >= receivedAt;
                return recording && started < course["armedUntil"]
                    && (sameClaim || startedAfterReceipt);
            }
        } catch (e) {
            System.println("ARGUS activity check failed: " + e.toString());
        }
        return claimed; // Keep a claimed course if activity info is unavailable.
    }

    function disableCourse(requestId) {
        var course = Application.Storage.getValue("course");
        if (!matches(course, requestId)) { return false; }
        course["monitoringEnabled"] = false;
        Application.Storage.setValue("course", course);
        var saved = Application.Storage.getValue("course");
        if (!matches(saved, requestId) || saved["monitoringEnabled"] != false) {
            return false;
        }
        var claim = Application.Storage.getValue("courseRun");
        if (matches(claim, requestId)) {
            Application.Storage.deleteValue("courseRun");
        }
        return true;
    }

    function cleanupExpired(nowSeconds) {
        var course = Application.Storage.getValue("course");
        if (!(course instanceof Lang.Dictionary)
            || !(course["requestId"] instanceof Lang.String)
            || !(course["armedUntil"] instanceof Lang.Number)
            || nowSeconds < course["armedUntil"]
            || hasActiveRun(course)) { return false; }
        var current = Application.Storage.getValue("course");
        if (!matches(current, course["requestId"])
            || current["armedUntil"] != course["armedUntil"]
            || hasActiveRun(current)) { return false; }
        Application.Storage.deleteValue("course");
        var claim = Application.Storage.getValue("courseRun");
        if (matches(claim, course["requestId"])) {
            Application.Storage.deleteValue("courseRun");
        }
        var job = Application.Storage.getValue("expiryJob");
        if (matches(job, course["requestId"])) {
            Application.Storage.deleteValue("expiryJob");
        }
        return true;
    }

    function schedule(course) {
        var requestId = course["requestId"];
        var deadline = course["armedUntil"];
        try {
            Application.Storage.setValue("expiryJob",
                {"requestId" => requestId, "armedUntil" => deadline});
            var earliest = Time.now().value() + CLEANUP_GRACE_SECONDS;
            var scheduled = deadline + CLEANUP_GRACE_SECONDS;
            if (scheduled < earliest) { scheduled = earliest; }
            var lastEvent = Background.getLastTemporalEventTime();
            if (lastEvent != null
                && scheduled <= lastEvent.value() + CLEANUP_GRACE_SECONDS) {
                scheduled = lastEvent.value() + CLEANUP_GRACE_SECONDS + 1;
            }
            Background.registerForTemporalEvent(new Time.Moment(scheduled));
        } catch (e) {
            // The Data Field's lazy expiry check still rejects and removes old data.
            System.println("ARGUS expiry schedule failed: " + e.toString());
        }
    }

    function onTemporal(nowSeconds) {
        var job = Application.Storage.getValue("expiryJob");
        var course = Application.Storage.getValue("course");
        if (!(job instanceof Lang.Dictionary)
            || !matches(course, job["requestId"])
            || course["armedUntil"] != job["armedUntil"]
            || nowSeconds < job["armedUntil"] + CLEANUP_GRACE_SECONDS) {
            return false;
        }
        if (cleanupExpired(nowSeconds)) { return true; }
        // If the deadline fell during a Run, keep monitoring and check again
        // after completion. The activity-completed callback is the fast path.
        var current = Application.Storage.getValue("course");
        if (matches(current, job["requestId"])
            && current["armedUntil"] == job["armedUntil"]
            && hasActiveRun(current)) {
            try {
                Background.registerForTemporalEvent(new Time.Moment(nowSeconds + 1800));
            } catch (e) {
                System.println("ARGUS expiry retry failed: " + e.toString());
            }
        }
        return false;
    }

    function onActivityCompleted(nowSeconds) {
        var course = Application.Storage.getValue("course");
        var claim = Application.Storage.getValue("courseRun");
        if (course instanceof Lang.Dictionary
            && matches(claim, course["requestId"])) {
            // A delayed completion callback must not retire a newer active Run.
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
            var current = Application.Storage.getValue("course");
            var currentClaim = Application.Storage.getValue("courseRun");
            if (matches(current, claim["requestId"])
                && matches(currentClaim, claim["requestId"])
                && currentClaim["startTime"] == claim["startTime"]) {
                if (disableCourse(claim["requestId"])) {
                    if (nowSeconds >= current["armedUntil"] + CLEANUP_GRACE_SECONDS) {
                        cleanupExpired(nowSeconds);
                    }
                    return true;
                }
            }
        }
        return cleanupExpired(nowSeconds);
    }
}
