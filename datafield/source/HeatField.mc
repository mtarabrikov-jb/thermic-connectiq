import Toybox.Activity;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// All the field may do with a transport: keep its housekeeping going. Handing the
// field this narrow type, not Transport, leaves it nothing to write to a pack with.
typedef Ticker as interface {
    function onTick() as Void;
};

// Shows, for each pack, the heat level and the temperature at the gear, with the
// batteries underneath, and records level, temperature and battery.
//
// The field draws itself. With two packs it needs a left and a right half, and the
// single value of a simple data field cannot give that. It shows numbers only, with no
// label and no icons, so that they can be as large as the cell allows.
class HeatField extends WatchUi.DataField {

    // Ids of the recorded fields; resources/fit/fit.xml refers to them.
    private const FIELD_HEAT = 0;
    private const FIELD_BATTERY = 1;
    private const FIELD_BATTERY_USED = 2;
    private const FIELD_TEMPERATURE = 3;

    // FIT's "no value" for an unsigned byte. Written while no pack is connected, so
    // the recording has a gap instead of repeating the last known value.
    private const NO_VALUE = 0xFF;
    // The same for a signed 16-bit value. The temperature gets two bytes because a
    // signed byte ends at 126 and a pack may report up to 214 degrees.
    private const NO_VALUE_SIGNED = 0x7FFF;

    // Pixels kept free at the ends of a line.
    private const MARGIN = 3;
    // Pixels kept free between the two packs' values, so that they do not read as one.
    private const COLUMN_GAP = 12;

    private var _model as Model;
    private var _ticker as Ticker;
    private var _heat as FitContributor.Field;
    private var _battery as FitContributor.Field;
    private var _used as FitContributor.Field;
    private var _temperature as FitContributor.Field;
    // Lowest battery seen when the activity timer first ran; null until then.
    private var _startBattery as Number? = null;
    private var _memoryLogged as Number = 0;
    // For the log: when compute() last ran, in seconds of uptime, and how often.
    private var _lastCompute as Number = 0;
    private var _computes as Number = 0;
    // Fonts for the line with the values, largest first.
    private var _fonts as Array<Graphics.FontType> = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM,
        Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontType>;

    public function initialize(model as Model, ticker as Ticker) {
        DataField.initialize();
        _model = model;
        _ticker = ticker;
        _heat = createField("heat_level", FIELD_HEAT, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "level"});
        _battery = createField("pack_battery", FIELD_BATTERY, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "%"});
        _used = createField("pack_battery_used", FIELD_BATTERY_USED, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"});
        // Always degrees Celsius, whatever unit the watch shows.
        _temperature = createField("gear_temperature", FIELD_TEMPERATURE, FitContributor.DATA_TYPE_SINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "C"});
        _heat.setData(NO_VALUE);
        _battery.setData(NO_VALUE);
        _used.setData(NO_VALUE);
        _temperature.setData(NO_VALUE_SIGNED);
    }

    // Called by the watch once per second, whether or not the field is on screen.
    // This is the only clock a data field has, so it also drives the transport.
    //
    // The recording keeps one value of each kind: the highest level, the lowest
    // temperature and the lowest battery of the packs.
    public function compute(info as Activity.Info) as Void {
        var now = System.getTimer() / 1000;
        if (_lastCompute != 0 && now - _lastCompute > 5) {
            note("compute was not called for " + (now - _lastCompute) + " s");
        }
        _lastCompute = now;
        _computes++;
        _ticker.onTick();
        var level = _model.level();
        var battery = lowestBattery();
        var temperature = lowestTemperature();
        if (_computes % 60 == 0) {
            note("alive, timer state " + info.timerState + ", level " + level
                + ", temperature " + temperature + ", battery " + battery);
        }
        _heat.setData(level != null ? level : NO_VALUE);
        _battery.setData(battery != null ? battery : NO_VALUE);
        _temperature.setData(temperature != null ? temperature : NO_VALUE_SIGNED);
        if (battery != null && info.timerState == Activity.TIMER_STATE_ON) {
            if (_startBattery == null) {
                _startBattery = battery;
            }
            var used = (_startBattery as Number) - battery;
            _used.setData(used > 0 ? used : 0);
        }
        logMemory();
    }

    // One pack: "7 24°" with "64%" under it. Two packs: the same twice, the first pack
    // in the left half of the cell and the second in the right half.
    //
    // Which pack is "first" is the order in which they connected. Nothing in a pack
    // says which foot it is on, so the sides can differ from one activity to the next.
    public function onUpdate(dc as Dc) as Void {
        var background = getBackgroundColor();
        var dark = (background == Graphics.COLOR_BLACK);
        var strong = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var soft = dark ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
        dc.setColor(strong, background);
        dc.clear();

        var values = [] as Array<String>;
        var batteries = [] as Array<String>;
        if (_model.level() == null) {
            // Nothing to show for a pack yet: one word about what is going on.
            values.add(status());
        } else {
            for (var i = 0; i < _model.packs.size(); i++) {
                var pack = _model.packs[i];
                var level = pack.level;
                var degrees = pack.temperature;
                var battery = pack.battery;
                var text = (level != null) ? level.toString() : "--";
                if (degrees != null) {
                    text += " " + Units.temperature(degrees);
                }
                values.add(text);
                batteries.add((battery != null) ? (battery + "%") : "--");
            }
        }

        var h = dc.getHeight();
        var small = Graphics.FONT_XTINY;
        var batteryHeight = (batteries.size() > 0) ? dc.getFontHeight(small) : 0;
        var flags = getObscurityFlags();
        var top = (flags & OBSCURE_TOP) != 0;
        var bottom = (flags & OBSCURE_BOTTOM) != 0;

        // The largest font with which the lines fit the cell and the values fit the
        // part of their line that is on the round screen.
        var font = small;
        var y = 0;
        for (var i = 0; i < _fonts.size(); i++) {
            font = _fonts[i];
            var total = dc.getFontHeight(font) + batteryHeight;
            // A cell at the top of a round screen is widest at its lower edge, one at
            // the bottom at its upper edge. The lines go to the wide end.
            if (top && !bottom) {
                y = h - total - 1;
            } else if (bottom && !top) {
                y = 1;
            } else {
                y = (h - total) / 2;
            }
            if (total <= h && fits(dc, values, font, y)) {
                break;
            }
        }

        drawRow(dc, values, font, strong, background, y);
        if (batteryHeight > 0) {
            drawRow(dc, batteries, small, soft, background, y + dc.getFontHeight(font));
        }
    }

    public function onTimerReset() as Void {
        note("timer reset");
        _startBattery = null;
        _used.setData(NO_VALUE);
    }

    // The rest of the callbacks only leave a line in the log. They show what the watch
    // was doing when something went wrong with the recording.
    public function onTimerStart() as Void {
        note("timer start");
    }

    public function onTimerStop() as Void {
        note("timer stop");
    }

    public function onTimerPause() as Void {
        note("timer pause");
    }

    public function onTimerResume() as Void {
        note("timer resume");
    }

    public function onTimerLap() as Void {
        note("lap");
    }

    // What to show while no pack has reported a level.
    private function status() as String {
        if (!_model.note.equals("")) {
            return _model.note;
        }
        return _model.connecting ? "..." : "--";
    }

    // One text in the middle of the line, or two texts in its left and right halves.
    // A text that does not fit is left out rather than cut off.
    private function drawRow(dc as Dc, texts as Array<String>, font as Graphics.FontType,
            color as Graphics.ColorType, background as Graphics.ColorType, y as Number) as Void {
        var range = room(dc, y, y + dc.getFontHeight(font));
        var width = (range[1] - range[0]) / texts.size();
        dc.setColor(color, background);
        for (var i = 0; i < texts.size(); i++) {
            if (dc.getTextWidthInPixels(texts[i], font) <= width) {
                dc.drawText(range[0] + width * i + width / 2, y, font, texts[i], Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
    }

    private function fits(dc as Dc, texts as Array<String>, font as Graphics.FontType, y as Number) as Boolean {
        var range = room(dc, y, y + dc.getFontHeight(font));
        var width = (range[1] - range[0]) / texts.size();
        if (texts.size() > 1) {
            width -= COLUMN_GAP;
        }
        for (var i = 0; i < texts.size(); i++) {
            if (dc.getTextWidthInPixels(texts[i], font) > width) {
                return false;
            }
        }
        return true;
    }

    // The stretch of a line, from yTop to yBottom in cell coordinates, that lies on the
    // screen: [first x, last x]. Worked out for a round screen, the only kind this
    // field is built for. A cell is not told where it sits, only which edges of the
    // screen it touches, and that is enough here.
    private function room(dc as Dc, yTop as Number, yBottom as Number) as Array<Number> {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var size = System.getDeviceSettings().screenWidth;
        var radius = size / 2;
        var flags = getObscurityFlags();
        var cellY = (size - h) / 2;
        if ((flags & OBSCURE_TOP) != 0) {
            cellY = 0;
        } else if ((flags & OBSCURE_BOTTOM) != 0) {
            cellY = size - h;
        }
        var cellX = (size - w) / 2;
        if ((flags & OBSCURE_LEFT) != 0) {
            cellX = 0;
        } else if ((flags & OBSCURE_RIGHT) != 0) {
            cellX = size - w;
        }
        // The end of the line that is further from the middle of the screen is the
        // narrower one, and it decides.
        var above = (cellY + yTop - radius).abs();
        var below = (cellY + yBottom - radius).abs();
        var distance = (above > below) ? above : below;
        var half = 0;
        if (distance < radius) {
            half = Math.sqrt(radius * radius - distance * distance).toNumber();
        }
        var from = radius - half - cellX + MARGIN;
        var to = radius + half - cellX - MARGIN;
        if (from < MARGIN) {
            from = MARGIN;
        }
        if (to > w - MARGIN) {
            to = w - MARGIN;
        }
        if (to < from) {
            to = from;
        }
        return [from, to] as Array<Number>;
    }

    // The colder of the two when there are two packs: that is the one to worry about.
    private function lowestTemperature() as Number? {
        var value = null as Number?;
        for (var i = 0; i < _model.packs.size(); i++) {
            var t = _model.packs[i].temperature;
            if (t != null && (value == null || t < (value as Number))) {
                value = t;
            }
        }
        return value;
    }

    private function lowestBattery() as Number? {
        var value = null as Number?;
        for (var i = 0; i < _model.packs.size(); i++) {
            var b = _model.packs[i].battery;
            if (b != null && (value == null || b < (value as Number))) {
                value = b;
            }
        }
        return value;
    }

    // A data field has 128 KB for everything. Log the memory in use each time it has
    // grown noticeably, so the log shows how close the field gets to the limit.
    private function logMemory() as Void {
        var stats = System.getSystemStats();
        if (stats.usedMemory > _memoryLogged + 2048) {
            _memoryLogged = stats.usedMemory;
            System.println("field: memory " + stats.usedMemory + " of " + stats.totalMemory);
        }
    }

    // One line for the field's log on the watch, stamped like the transport's lines.
    private function note(text as String) as Void {
        System.println("field " + (System.getTimer() / 1000) + " " + text);
    }
}
