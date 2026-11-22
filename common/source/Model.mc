import Toybox.Lang;
import Toybox.WatchUi;

// What the widget knows about one pack. The pack is the source of truth: values come
// from reads and notifications, never from what the watch last asked for.
class Pack {
    public var level as Number? = null;
    public var battery as Number? = null;
    // Degrees Celsius at the heated gear; null when the pack reports no reading.
    public var temperature as Number? = null;

    // The rest is read only when Model.details is set.
    // Minutes of heating the pack expects to have left.
    public var remaining as Number? = null;
    // Degrees Celsius inside the pack.
    public var inside as Number? = null;
    // Whether the pack regulates to a target temperature, and that target in degrees
    // Celsius. Both are settings kept in the pack.
    public var regulating as Boolean? = null;
    public var goal as Number? = null;
    // Heater resistance as the pack gives it, unit unknown. Protocol.RESISTANCE_OPEN
    // is taken to mean that no heating element is attached.
    public var resistance as Number? = null;
    // Whether the pack lets itself heat.
    public var allowed as Boolean? = null;

    // Read only when Transport.readDiagnostics() asks. Numbers as the pack gives them
    // where the unit is not known, degrees Celsius for the three temperatures.
    public var capacity as Number? = null;
    public var current as Number? = null;
    public var design as Number? = null;
    public var gauge as Number? = null;
    public var coldest as Number? = null;
    public var coldestBefore as Number? = null;

    // Set by an app once it has warned about this pack's battery, so that it warns
    // once and not every second.
    public var warned as Boolean = false;

    // What is wrong with this pack as far as it tells, in a few words, or "" when
    // nothing is.
    public function trouble() as String {
        if (resistance == Protocol.RESISTANCE_OPEN) {
            // With a question mark: what that resistance means is a guess.
            return "no heater?";
        }
        if (allowed == false) {
            return "heat blocked";
        }
        return "";
    }
}

// Anything that can find packs and set their level. The views only use this
// interface, so the Bluetooth link can later be swapped for a phone relay.
typedef Transport as interface {
    function start() as Void;
    function stop() as Void;
    // Housekeeping. The host calls it once a second: a widget from a timer, a data
    // field from compute(), because a data field is not allowed a timer of its own.
    function onTick() as Void;
    // The three writes. Each is called for one press of a button and stores one value
    // in every connected pack: the heat level, the target temperature in degrees
    // Celsius, and whether the pack regulates to that target.
    function setLevel(level as Number) as Void;
    function setTarget(degrees as Number) as Void;
    function setRegulation(on as Boolean) as Void;
    // Reads the values of the diagnostics page from every connected pack. Nothing is
    // written. Only with Model.details.
    function readDiagnostics() as Void;
};

// State shared by the transport and the views.
class Model {

    public const MAX_PACKS = 2;

    public var packs as Array<Pack> = [] as Array<Pack>;
    // Set by an app before the transport starts when it also shows remaining heat time,
    // the temperature inside the pack, the target temperature, what is wrong with a
    // pack and its diagnostics. Reading them makes connecting take longer, so an app
    // that does not show them leaves this off.
    public var details as Boolean = false;
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
