import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Shows every step of the probe on the watch face, so no log file is needed.
class ProbeView extends WatchUi.View {

    private var _probe as Probe;

    public function initialize(probe as Probe) {
        View.initialize();
        _probe = probe;
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var cx = dc.getWidth() / 2;
        var lines = [
            _probe.stage,
            _probe.detail,
            "level " + show(_probe.level) + "  batt " + show(_probe.battery),
            "write " + _probe.lastWrite + "  n=" + _probe.writes,
            "notif " + _probe.notifies + "  drops " + _probe.drops,
            "in " + _probe.lastInput + "  #" + _probe.inputs,
            "seen " + _probe.seen + "/" + _probe.distinct + "  by " + _probe.matchedBy
        ] as Array<String>;

        dc.drawText(cx, 10, Graphics.FONT_XTINY, "Therm-ic probe", Graphics.TEXT_JUSTIFY_CENTER);
        var y = 32;
        for (var i = 0; i < lines.size(); i++) {
            var font = (i == 0) ? Graphics.FONT_SMALL : Graphics.FONT_XTINY;
            dc.drawText(cx, y, font, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += (i == 0) ? 30 : 25;
        }
    }

    private function show(value as Number?) as String {
        return value != null ? value.toString() : "-";
    }
}

class ProbeInput extends WatchUi.BehaviorDelegate {

    private var _probe as Probe;

    public function initialize(probe as Probe) {
        BehaviorDelegate.initialize();
        _probe = probe;
    }

    // Raw key events arrive here before they are turned into behaviors. Returning
    // false lets the behavior callbacks below run as usual.
    public function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        _probe.noteInput("k" + keyEvent.getKey() + "." + keyEvent.getType());
        return false;
    }

    // START
    public function onSelect() as Boolean {
        _probe.noteInput("select");
        _probe.cycle();
        return true;
    }

    // UP
    public function onPreviousPage() as Boolean {
        _probe.noteInput("prev");
        _probe.bump(1);
        return true;
    }

    // DOWN
    public function onNextPage() as Boolean {
        _probe.noteInput("next");
        _probe.bump(-1);
        return true;
    }

    // MENU (hold UP)
    public function onMenu() as Boolean {
        _probe.noteInput("menu");
        _probe.rescan();
        return true;
    }

    // BACK: only recorded, the system still closes the widget.
    public function onBack() as Boolean {
        _probe.noteInput("back");
        return false;
    }
}
