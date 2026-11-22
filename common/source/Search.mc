import Toybox.Lang;

// When to look for packs.
//
// Scanning costs the watch battery, and a data field can be looking for a pack for a
// whole activity. So the search runs without a break only for a while after the start
// and after a pack comes or goes, and in short bursts after that:
//
//   the first minute                      all the time
//   the next ten minutes, when no pack    12 s of every minute
//   is connected or one that was
//   connected is gone
//   after that, and straight after the    12 s of every five minutes
//   first minute when one pack is
//   connected and a second was never seen
//
// On the watch a pack was found 1 to 5 s after scanning began; that is where the
// length of a burst comes from.
module Search {

    const EAGER_MS = 60000;
    const BURST_MS = 12000;
    const EVERY_MS = 60000;
    const EVERY_SLOW_MS = 300000;
    const FAST_FOR_MS = 600000;

    // The time from the start of one burst to the start of the next, or 0 while the
    // search runs all the time.
    //   sinceChange  milliseconds since the start or since a pack last came or went
    //   packs        packs connected now
    //   most         the most packs that were connected at once since the start
    function period(sinceChange as Number, packs as Number, most as Number) as Number {
        if (sinceChange < EAGER_MS) {
            return 0;
        }
        var missed = (packs == 0) || (packs < most);
        if (missed && sinceChange < EAGER_MS + FAST_FOR_MS) {
            return EVERY_MS;
        }
        return EVERY_SLOW_MS;
    }

    // True while the radio should be scanning. A burst is the last part of its period,
    // so a quiet stretch comes first.
    function scanning(sinceChange as Number, packs as Number, most as Number) as Boolean {
        var every = period(sinceChange, packs, most);
        if (every == 0) {
            return true;
        }
        return ((sinceChange - EAGER_MS) % every) >= (every - BURST_MS);
    }
}
