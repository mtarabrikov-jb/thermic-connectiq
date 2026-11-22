import Toybox.Lang;
import Toybox.WatchUi;

// What the widget knows about one pack. The pack is the source of truth: values come
// from reads and notifications, never from what the watch last asked for.
class Pack {
    public var level as Number? = null;
    public var battery as Number? = null;
    // Degrees Celsius at the heated gear; null when the pack reports no reading.
    public var temperature as Number? = null;
}

// Anything that can find packs and set their level. The views only use this
// interface, so the Bluetooth link can later be swapped for a phone relay.
typedef Transport as interface {
    function start() as Void;
    function stop() as Void;
    // Housekeeping. The host calls it once a second: a widget from a timer, a data
    // field from compute(), because a data field is not allowed a timer of its own.
    function onTick() as Void;
    function setLevel(level as Number) as Void;
};

// State shared by the transport and the views.
class Model {

    public const MAX_PACKS = 2;

    public var packs as Array<Pack> = [] as Array<Pack>;
    public var searching as Boolean = false;
    // A pack was found and the connection is being set up. This takes a while:
    // about 25 seconds were measured from link up to the first read.
    public var connecting as Boolean = false;
    // Level shown on the control page. It follows what the packs report, except while
    // a change made by the user is still on its way to them.
    public var target as Number? = null;
    // True from the moment the user picks a level until the packs have taken it.
    public var userPending as Boolean = false;
    // Short message for the bottom line when something goes wrong.
    public var note as String = "";

    public function changed() as Void {
        WatchUi.requestUpdate();
    }

    // A transport calls this whenever a pack reports its level or a pack comes or goes.
    // Without it the control page would keep counting from a stale value after the
    // level was changed with the button on the pack.
    public function packReported() as Void {
        if (!userPending) {
            target = level();
        }
        changed();
    }

    // A transport calls this when the user's change has been delivered or given up on.
    public function userDone() as Void {
        userPending = false;
        packReported();
    }

    // Highest level reported by any pack, null when none is known yet.
    public function level() as Number? {
        var value = null as Number?;
        for (var i = 0; i < packs.size(); i++) {
            var l = packs[i].level;
            if (l != null && (value == null || l > (value as Number))) {
                value = l;
            }
        }
        return value;
    }

    public function levelsDiffer() as Boolean {
        var first = null as Number?;
        for (var i = 0; i < packs.size(); i++) {
            var l = packs[i].level;
            if (l == null) {
                continue;
            }
            if (first == null) {
                first = l;
            } else if (l != first) {
                return true;
            }
        }
        return false;
    }
}
