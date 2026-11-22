import Toybox.Lang;
import Toybox.Test;

// Unit tests for the search schedule in Search.mc. They are built only by
// widget/monkey-test.jungle with monkeyc --unit-test and run in the simulator.

// How many of the seconds from..to the search is on.
function searchSeconds(from as Number, to as Number, packs as Number, most as Number) as Number {
    var on = 0;
    for (var second = from; second < to; second++) {
        if (Search.scanning(second * 1000, packs, most)) {
            on++;
        }
    }
    return on;
}

(:test)
function searchRunsAllTheTimeAtFirst(logger as Test.Logger) as Boolean {
    return searchSeconds(0, 60, 0, 0) == 60 && searchSeconds(0, 60, 1, 1) == 60
        && Search.period(59999, 0, 0) == 0;
}

(:test)
function searchGoesInBurstsWithoutAPack(logger as Test.Logger) as Boolean {
    // Each of the ten minutes after the first: quiet for 48 s, then a burst of 12 s.
    var firstMinute = searchSeconds(60, 120, 0, 0);
    var tenMinutes = searchSeconds(60, 660, 0, 0);
    logger.debug("on for " + firstMinute + " s of the first minute, " + tenMinutes + " s of ten");
    return firstMinute == 12 && tenMinutes == 120
        && !Search.scanning(60000, 0, 0) && !Search.scanning(107999, 0, 0)
        && Search.scanning(108000, 0, 0) && Search.scanning(119999, 0, 0);
}

(:test)
function searchSlowsDownAfterTenMinutes(logger as Test.Logger) as Boolean {
    // From the twelfth minute on: 12 s of every five minutes.
    var first = searchSeconds(660, 960, 0, 0);
    var second = searchSeconds(960, 1260, 0, 0);
    logger.debug("on for " + first + " s and " + second + " s of two five-minute stretches");
    return first == 12 && second == 12
        && Search.period(659999, 0, 0) == Search.EVERY_MS
        && Search.period(660000, 0, 0) == Search.EVERY_SLOW_MS;
}

(:test)
function searchForASecondPackIsSlowFromTheStart(logger as Test.Logger) as Boolean {
    // One pack connected and a second never seen: no bursts every minute at all.
    return Search.period(60000, 1, 1) == Search.EVERY_SLOW_MS
        && searchSeconds(60, 348, 1, 1) == 0 && searchSeconds(348, 360, 1, 1) == 12;
}

(:test)
function searchForALostPackIsFast(logger as Test.Logger) as Boolean {
    // Two were connected and one of them is gone.
    return Search.period(120000, 1, 2) == Search.EVERY_MS && searchSeconds(60, 120, 1, 2) == 12;
}

(:test)
function searchNeverStopsForGood(logger as Test.Logger) as Boolean {
    // However long it has been, the next burst still comes.
    var day = 24 * 3600;
    return searchSeconds(day, day + 300, 0, 0) == 12 && searchSeconds(day, day + 300, 1, 1) == 12;
}
