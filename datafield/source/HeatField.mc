import Toybox.Activity;
import Toybox.Attention;
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
// single value of a simple data field cannot give that. It shows numbers under a label
// of its own, as the fields of the watch do, and no icons, so that the numbers can be
// as large as the cell allows.
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
    // How many packs were connected a second ago, to notice one going.
    private var _packsBefore as Number = 0;
    // An alert also takes over the field's own cell for a while, in inverted colours:
    // whether this watch shows the pop-up is not known, and the simulator does not.
    // The cell then looks like a field of the watch itself, words on top and the value
    // below. The words come in several lengths, longest first, for cells of any width.
    private const FLASH_SECONDS = 10;
    private var _flashCaptions as Array<String> = [""] as Array<String>;
    private var _flashValue as String = "";
    private var _flashUntil as Number = 0;
    // Fonts for the line with the values, largest first.
    private var _fonts as Array<Graphics.FontType> = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM,
        Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontType>;
    // How many of them, counted from the largest, keep the values easy to read. The
    // label is given up before the values are set in a smaller one.
    private const READABLE_FONTS = 4;
    // Font of the other lines: label, batteries, the words of an alert.
    private var _small as Graphics.FontType = Graphics.FONT_XTINY;
    // The field's label. The owner asked for it on 2026-11-22: among the other fields
    // of a data screen, numbers alone do not say whose they are.
    private const LABEL = "THERM-IC";

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
        watch();
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

    // One pack: the label, "7 24°" under it and "64%" under that. Two packs: the values
    // and the batteries twice, the first pack in the left half of the cell and the
    // second in the right half. A cell too low for three lines gets two, the label
    // sharing its line with the batteries: "THERM-IC 64%" or "87% THERM-IC 64%". Where
    // even that does not fit, the label is left out.
    //
    // Which pack is "first" is the order in which they connected. Nothing in a pack
    // says which foot it is on, so the sides can differ from one activity to the next.
    public function onUpdate(dc as Dc) as Void {
        var background = getBackgroundColor();
        var dark = (background == Graphics.COLOR_BLACK);
        var strong = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var soft = dark ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
        var flash = (System.getTimer() / 1000) < _flashUntil;
        if (flash) {
            // The other way round, so that the cell stands out from its neighbours.
            soft = background;
            background = strong;
            strong = soft;
        }
        dc.setColor(strong, background);
        dc.clear();

        // Lines of text, top to bottom. One of them, `big`, is set in the largest font
        // that lets everything fit. The others are small.
        var rows = [] as Array<Array<String>>;
        var big = 0;
        // Which of the fonts the large line gets; negative while none is found.
        var index = -1;
        var label = [LABEL] as Array<String>;
        if (flash) {
            // The words of an alert go above its value, as the label of a field does.
            // Not in a cell at the top of the screen: there the upper line is the
            // narrow one, and the words, being the longer text, would not fit it.
            var flags = getObscurityFlags();
            var wordsFirst = ((flags & OBSCURE_TOP) == 0) || ((flags & OBSCURE_BOTTOM) != 0);
            var words = wordsFirst ? 0 : 1;
            big = 1 - words;
            var value = [_flashValue] as Array<String>;
            var shortest = [_flashCaptions[_flashCaptions.size() - 1]] as Array<String>;
            rows = (wordsFirst ? [shortest, value] : [value, shortest]) as Array<Array<String>>;
            // An alert without its words says nothing. So the value gets the largest
            // font that leaves room for them, at least in their shortest form, and
            // then the longest wording that fits is taken.
            index = largest(dc, rows, big, _fonts.size());
            var chosen = (index >= 0) ? _fonts[index] : _small;
            for (var i = 0; i < _flashCaptions.size(); i++) {
                rows[words] = [_flashCaptions[i]] as Array<String>;
                if (rowsFit(dc, rows, big, chosen)) {
                    break;
                }
            }
        } else if (_model.level() == null) {
            // Nothing to show for a pack yet: one word about what is going on.
            var state = [status()] as Array<String>;
            rows = [label, state] as Array<Array<String>>;
            big = 1;
            index = largest(dc, rows, big, READABLE_FONTS);
            if (index < 0) {
                rows = [state] as Array<Array<String>>;
                big = 0;
                index = largest(dc, rows, big, _fonts.size());
            }
        } else {
            var values = [] as Array<String>;
            var batteries = [] as Array<String>;
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
            // What the values get with no label at all.
            var plain = largest(dc, [values, batteries] as Array<Array<String>>, 0, _fonts.size());
            // A label may cost the values some size, but must not push them below
            // what is easy to read. Where they are that small anyway, for want of
            // width, it costs them nothing and may stay.
            var count = READABLE_FONTS;
            if (plain + 1 > count) {
                count = plain + 1;
            }
            // A tall cell: the label, the values, the batteries.
            rows = [label, values, batteries] as Array<Array<String>>;
            big = 1;
            index = largest(dc, rows, big, count);
            // For a lower cell: the label shares its line with the batteries.
            var header = LABEL + " " + batteries[0];
            if (batteries.size() > 1) {
                header = batteries[0] + " " + LABEL + " " + batteries[1];
            }
            var shared = [header] as Array<String>;
            if (index < 0) {
                rows = [shared, values] as Array<Array<String>>;
                index = largest(dc, rows, big, count);
            }
            if (index < 0) {
                // The same the other way round. In a cell at the top of the screen the
                // lower line is the wide one, and the shared line is the longer text.
                rows = [values, shared] as Array<Array<String>>;
                big = 0;
                index = largest(dc, rows, big, count);
            }
            if (index < 0) {
                // No room for the label: the values over the batteries, as large as
                // they can be.
                rows = [values, batteries] as Array<Array<String>>;
                big = 0;
                index = plain;
            }
        }
        // When nothing fits, the smallest font. A text that still does not fit its
        // line is left out by drawRow().
        drawRows(dc, rows, big, (index >= 0) ? _fonts[index] : _small, strong, soft, background);
    }

    // Which of the first `count` fonts is the largest with which the rows fit the
    // cell: its place in the list, or -1 when none of them does.
    private function largest(dc as Dc, rows as Array<Array<String>>, big as Number, count as Number) as Number {
        for (var i = 0; i < count; i++) {
            if (rowsFit(dc, rows, big, _fonts[i])) {
                return i;
            }
        }
        return -1;
    }

    // Whether the rows fit the cell in height, and each of them the part of its line
    // that is on the round screen, with the row `big` set in the given font.
    private function rowsFit(dc as Dc, rows as Array<Array<String>>, big as Number,
            font as Graphics.FontType) as Boolean {
        var total = heightOf(dc, rows, big, font);
        if (total > dc.getHeight()) {
            return false;
        }
        var y = firstLine(dc, total);
        for (var r = 0; r < rows.size(); r++) {
            var f = (r == big) ? font : _small;
            if (!fits(dc, rows[r], f, y)) {
                return false;
            }
            y += dc.getFontHeight(f);
        }
        return true;
    }

    private function drawRows(dc as Dc, rows as Array<Array<String>>, big as Number, font as Graphics.FontType,
            strong as Graphics.ColorType, soft as Graphics.ColorType, background as Graphics.ColorType) as Void {
        var y = firstLine(dc, heightOf(dc, rows, big, font));
        for (var r = 0; r < rows.size(); r++) {
            var f = (r == big) ? font : _small;
            drawRow(dc, rows[r], f, (r == big) ? strong : soft, background, y);
            y += dc.getFontHeight(f);
        }
    }

    private function heightOf(dc as Dc, rows as Array<Array<String>>, big as Number,
            font as Graphics.FontType) as Number {
        var total = 0;
        for (var r = 0; r < rows.size(); r++) {
            total += dc.getFontHeight((r == big) ? font : _small);
        }
        return total;
    }

    // Where the first of the lines goes when together they are `total` pixels high.
    // A cell at the top of a round screen is widest at its lower edge, one at the
    // bottom at its upper edge. The lines go to the wide end.
    private function firstLine(dc as Dc, total as Number) as Number {
        var h = dc.getHeight();
        var flags = getObscurityFlags();
        var top = (flags & OBSCURE_TOP) != 0;
        var bottom = (flags & OBSCURE_BOTTOM) != 0;
        if (top && !bottom) {
            return h - total - 1;
        } else if (bottom && !top) {
            return 1;
        }
        return (h - total) / 2;
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

    // Raises an alert when a pack is gone or its battery is nearly empty: the two
    // things the phone app tells its user as well. One alert at a time; what is still
    // wrong a second later gets its turn then.
    //
    // The words name the heater. "Low 9%, battery" was tried on the watch and its
    // owner could not tell what it was about: on a watch that reads as its own battery.
    private function watch() as Void {
        var count = _model.packs.size();
        if (count < _packsBefore) {
            var gone = _packsBefore - count;
            _packsBefore = count;
            if (count == 0) {
                alert(["Heater connection", "Heater"] as Array<String>, "LOST");
            } else {
                alert([gone + " of " + (gone + count) + " heaters", gone + " heater"] as Array<String>, "LOST");
            }
            return;
        }
        _packsBefore = count;
        for (var i = 0; i < count; i++) {
            var pack = _model.packs[i];
            var battery = pack.battery;
            if (battery == null) {
                continue;
            }
            if (battery > Protocol.LOW_BATTERY + 5) {
                // Charged again, or another pack: warn anew next time.
                pack.warned = false;
            } else if (battery <= Protocol.LOW_BATTERY && !pack.warned) {
                pack.warned = true;
                var value = battery + "%";
                if (count > 1) {
                    value = ((i == 0) ? "left " : "right ") + value;
                }
                alert(["Heater battery low", "Heater batt low", "Heater low"] as Array<String>, value);
                return;
            }
        }
    }

    // Three ways at once, because none is sure to reach the wearer on its own: the
    // field's cell, a pop-up over the activity, and a vibration.
    //
    // captions: what the alert is about, in several lengths with the longest first.
    private function alert(captions as Array<String>, value as String) as Void {
        note("alert: " + captions[0] + ", " + value);
        _flashCaptions = captions;
        _flashValue = value;
        _flashUntil = System.getTimer() / 1000 + FLASH_SECONDS;
        try {
            if (self has :showAlert) {
                showAlert(new $.PackAlert(captions[0], value));
            }
            if ((Attention has :vibrate) && System.getDeviceSettings().vibrateOn) {
                Attention.vibrate([new Attention.VibeProfile(75, 600)] as Array<Attention.VibeProfile>);
            }
        } catch (e) {
            note("alert could not be shown");
        }
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
