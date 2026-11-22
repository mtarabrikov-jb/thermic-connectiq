import Toybox.Graphics;
import Toybox.Lang;

// Drawing for the pages of the widget.
module Screen {

    // With two packs the ring is split at the top; this is half of the gap, in degrees.
    const SPLIT_GAP = 6;
    // How far each pack's column stands from the middle of the screen.
    const COLUMN = 46;

    // The main page and the level page.
    // control = false: what the packs report. control = true: the level being set.
    function draw(dc as Dc, model as Model, control as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = ((cx < cy) ? cx : cy) - 8;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Two packs on the main page get a column each, left and right. The level page
        // keeps one number, because a level is set for both packs at once.
        if (!control && model.packs.size() == 2) {
            drawPair(dc, model, cx, cy, radius);
        } else {
            drawSingle(dc, model, control, cx, cy, radius);
        }
    }

    // One level in the middle and under it what is known about each pack.
    function drawSingle(dc as Dc, model as Model, control as Boolean, cx as Number, cy as Number, radius as Number) as Void {
        var actual = model.level();
        var shown = control ? model.target : actual;
        if (shown == null) {
            shown = actual;
        }

        // Level ring: 270 degrees, from the lower left clockwise to the lower right.
        // Angles are counter-clockwise from three o'clock.
        dc.setPenWidth(8);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, 315);
        if (shown != null && shown > 0) {
            dc.setColor(control ? Graphics.COLOR_YELLOW : Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, wrap(225 - 270 * shown / Protocol.MAX_LEVEL));
        }
        dc.setPenWidth(1);

        var count = model.packs.size();
        drawTitle(dc, cx, cy, control ? "SET LEVEL" : "THERM-IC");
        drawLevel(dc, cx, cy - 14, shown, Graphics.FONT_NUMBER_HOT, Graphics.FONT_LARGE,
            !control && count == 1 && model.packs[0].trouble().length() > 0);

        var warm = anyTemperature(model);
        var bottom = cy + 54;
        if (count == 0) {
            var status = model.connecting ? "connecting..." : (model.searching ? "searching..." : "no pack");
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 30, Graphics.FONT_TINY, status, Graphics.TEXT_JUSTIFY_CENTER);
        }
        for (var i = 0; i < count; i++) {
            var x = cx;
            if (count > 1) {
                x += (i == 0) ? -40 : 40;
            }
            // The level page stays short: remaining time and the temperature inside the
            // pack are for the main page.
            var end = drawPack(dc, x, cy + (warm ? 22 : 32), model.packs[i], warm, !control);
            if (end > bottom) {
                bottom = end;
            }
        }
        if (count == 1 && model.searching) {
            // Still looking for a second pack.
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 52, cy + (warm ? 46 : 32), Graphics.FONT_XTINY, "+", Graphics.TEXT_JUSTIFY_CENTER);
        }
        drawHint(dc, model, control ? "UP/DN  START on/off" : "START to set", cx, bottom + 2);
        if (control && count > 0 && model.note.length() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, bottom + 20, Graphics.FONT_XTINY, "MENU: more", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // The first pack on the left, the second on the right. Each has a foot above it, its
    // own half of the ring, its level and what else is known about it.
    //
    // Which pack is "first" is the order in which they connected. Nothing in a pack
    // says which foot it is on, so the sides can differ from one session to the next.
    function drawPair(dc as Dc, model as Model, cx as Number, cy as Number, radius as Number) as Void {
        var half = 135 - SPLIT_GAP;
        dc.setPenWidth(8);
        for (var i = 0; i < 2; i++) {
            // The left half runs clockwise from the lower left up to the top, the right
            // half counter-clockwise from the lower right.
            var from = (i == 0) ? 225 : 315;
            var sign = (i == 0) ? -1 : 1;
            var direction = (i == 0) ? Graphics.ARC_CLOCKWISE : Graphics.ARC_COUNTER_CLOCKWISE;
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, direction, from, wrap(from + sign * half));
            var level = model.packs[i].level;
            if (level != null && level > 0) {
                dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, direction, from, wrap(from + sign * half * level / Protocol.MAX_LEVEL));
            }
        }
        dc.setPenWidth(1);

        var warm = anyTemperature(model);
        var bottom = cy;
        for (var i = 0; i < 2; i++) {
            var pack = model.packs[i];
            var x = cx + ((i == 0) ? -COLUMN : COLUMN);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            Icons.foot(dc, x, cy - 92, i == 0);
            drawLevel(dc, x, cy - 30, pack.level, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_MEDIUM,
                pack.trouble().length() > 0);
            var end = drawPack(dc, x, cy + (warm ? -6 : 0), pack, warm, true);
            if (end > bottom) {
                bottom = end;
            }
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx, cy - 52, cx, bottom - 2);
        drawHint(dc, model, "START to set", cx, bottom + 2);
    }

    // The target temperature page: the target as a big number, whether the packs
    // regulate to it, and what the gear reads now.
    function drawTarget(dc as Dc, model as Model, state as TargetState) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = ((cx < cy) ? cx : cy) - 8;
        var value = state.value;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // The ring shows where the target lies between the lowest and the highest one.
        dc.setPenWidth(8);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, 315);
        if (state.on && value != null) {
            var share = 270 * (Protocol.clampTarget(value) - Protocol.TARGET_MIN) / (Protocol.TARGET_MAX - Protocol.TARGET_MIN);
            if (share > 0) {
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, wrap(225 - share));
            }
        }
        dc.setPenWidth(1);

        drawTitle(dc, cx, cy, "SET TEMP");
        if (!anyTemperature(model)) {
            // The phone app does the same: no sensor, no temperature to regulate by.
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 26, Graphics.FONT_TINY, "the gear reports", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, cy, Graphics.FONT_TINY, "no temperature", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var text = "--";
        var font = Graphics.FONT_LARGE;
        if (value != null) {
            text = Units.shown(value).toString();
            font = Graphics.FONT_NUMBER_HOT;
        }
        dc.setColor(state.on ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 14, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (value != null) {
            // The degree sign is drawn: a number font may come without one.
            dc.setPenWidth(2);
            dc.drawCircle(cx + dc.getTextWidthInPixels(text, font) / 2 + 8, cy - 30, 4);
            dc.setPenWidth(1);
        }

        dc.setColor(state.on ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 22, Graphics.FONT_TINY, state.on ? "ON" : "OFF", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 48, Graphics.FONT_XTINY, "now " + temperatureLine(model), Graphics.TEXT_JUSTIFY_CENTER);
        drawHint(dc, model, "UP/DN  START on/off", cx, cy + 70);
    }

    // What is known about one pack, as lines one under another: the temperature at its
    // gear when any pack reports one, then its battery, and with details the
    // temperature inside it and how long its heat will last. x is the middle of the
    // lines and y the top of the first. Returns the top of the line after the last.
    function drawPack(dc as Dc, x as Number, y as Number, pack as Pack, warm as Boolean, details as Boolean) as Number {
        if (warm) {
            drawTemperature(dc, x, y, pack);
            y += 24;
        }
        drawBattery(dc, x, y, pack.battery, details ? pack.inside : null);
        y += 18;
        var remaining = pack.remaining;
        if (details && remaining != null) {
            drawRemaining(dc, x, y, remaining);
            y += 18;
        }
        return y;
    }

    function drawTitle(dc as Dc, cx as Number, cy as Number, text as String) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 80, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // A level with a thermometer in front of it: a big number, "OFF" for zero and "--"
    // while it is not known. A warning sign takes the thermometer's place when the pack
    // says something is wrong. x and y are the middle of the two together.
    function drawLevel(dc as Dc, x as Number, y as Number, level as Number?,
            numberFont as Graphics.FontType, textFont as Graphics.FontType, troubled as Boolean) as Void {
        var text = "--";
        var font = textFont;
        if (level != null) {
            if (level == 0) {
                text = "OFF";
            } else {
                text = level.toString();
                font = numberFont;
            }
        }
        var width = dc.getTextWidthInPixels(text, font);
        var start = x - (16 + width) / 2;
        if (troubled) {
            Icons.warning(dc, start + 4, y - 8);
        } else {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            Icons.thermometer(dc, start + 3, y - Icons.THERMOMETER_HEIGHT / 2);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start + 16 + width / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // "24°", or "--" for a pack without a reading. While the pack regulates to a target
    // the target follows in the level's colour, after an arrowhead. x is the middle,
    // y the top.
    function drawTemperature(dc as Dc, x as Number, y as Number, pack as Pack) as Void {
        var font = Graphics.FONT_TINY;
        var degrees = pack.temperature;
        var goal = pack.goal;
        var text = (degrees != null) ? Units.temperature(degrees) : "--";
        if (pack.regulating == true && goal != null) {
            var target = Units.temperature(goal);
            var width = dc.getTextWidthInPixels(text, font);
            var start = x - (width + 13 + dc.getTextWidthInPixels(target, font)) / 2;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(start, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            Icons.pointer(dc, start + width + 4, y + dc.getFontHeight(font) / 2);
            dc.drawText(start + width + 13, y, font, target, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // A battery with "87%" next to it and, when it is given, the temperature inside the
    // pack after that. x is the middle of it all, y the top.
    function drawBattery(dc as Dc, x as Number, y as Number, percent as Number?, inside as Number?) as Void {
        var font = Graphics.FONT_XTINY;
        var text = (percent != null) ? (percent + "%") : "--";
        if (inside != null) {
            text += "  " + Units.temperature(inside);
        }
        var start = x - (Icons.BATTERY_WIDTH + 4 + dc.getTextWidthInPixels(text, font)) / 2;
        Icons.battery(dc, start, y + (dc.getFontHeight(font) - Icons.BATTERY_HEIGHT) / 2, percent);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start + Icons.BATTERY_WIDTH + 4, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // A clock with "1h35" next to it: how long the pack expects its heat to last.
    // x is the middle of the two together, y the top.
    function drawRemaining(dc as Dc, x as Number, y as Number, minutes as Number) as Void {
        var font = Graphics.FONT_XTINY;
        var text = Units.duration(minutes);
        var start = x - (Icons.CLOCK_SIZE + 4 + dc.getTextWidthInPixels(text, font)) / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        Icons.clock(dc, start, y + (dc.getFontHeight(font) - Icons.CLOCK_SIZE) / 2);
        dc.drawText(start + Icons.CLOCK_SIZE + 4, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Bottom line: what the buttons do; in red what went wrong with the link; in yellow
    // what a pack says is wrong with itself.
    function drawHint(dc as Dc, model as Model, hint as String, cx as Number, y as Number) as Void {
        var trouble = "";
        for (var i = 0; i < model.packs.size() && trouble.length() == 0; i++) {
            trouble = model.packs[i].trouble();
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (model.note.length() > 0) {
            hint = model.note;
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        } else if (trouble.length() > 0) {
            hint = trouble;
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        } else if (model.packs.size() == 0 && !hint.equals("START to set")) {
            hint = "no pack connected";
        }
        dc.drawText(cx, y, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // The diagnostics page: a line for each value and a column for each pack. Where the
    // unit is not known the number is shown as the pack gives it.
    function drawDiagnostics(dc as Dc, model as Model) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var font = Graphics.FONT_XTINY;
        var count = model.packs.size();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 98, font, "DIAGNOSTICS", Graphics.TEXT_JUSTIFY_CENTER);
        if (count == 0) {
            dc.drawText(cx, cy - 12, Graphics.FONT_TINY, "no pack connected", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var labels = ["current", "capacity", "design", "heater", "gauge", "coldest", "before"] as Array<String>;
        var y = cy - 74;
        for (var row = 0; row < labels.size(); row++) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - 86, y, font, labels[row], Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < count; i++) {
                var x = (count == 1) ? cx + 70 : cx + 34 + 50 * i;
                dc.drawText(x, y, font, diagnostic(model.packs[i], row), Graphics.TEXT_JUSTIFY_RIGHT);
            }
            y += 19;
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 3, font, "START: read again", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // The value for one line of the diagnostics page, "--" until it has been read.
    function diagnostic(pack as Pack, row as Number) as String {
        var value = null as Number?;
        if (row == 0) {
            value = pack.current;
        } else if (row == 1) {
            value = pack.capacity;
        } else if (row == 2) {
            value = pack.design;
        } else if (row == 3) {
            value = pack.resistance;
            if (value == Protocol.RESISTANCE_OPEN) {
                return "open";
            }
        } else if (row == 4) {
            value = pack.gauge;
        } else if (row == 5) {
            value = pack.coldest;
        } else {
            value = pack.coldestBefore;
        }
        if (value == null) {
            return "--";
        }
        return (row >= 4) ? Units.temperature(value) : value.toString();
    }

    // "24°   26°", one per pack, with "--" for a pack that has no reading.
    function temperatureLine(model as Model) as String {
        var line = "";
        for (var i = 0; i < model.packs.size(); i++) {
            var degrees = model.packs[i].temperature;
            if (i > 0) {
                line += "   ";
            }
            line += (degrees != null) ? Units.temperature(degrees) : "--";
        }
        return line;
    }

    // True when at least one pack reports a temperature. Gear without a sensor never
    // does, and then the pages leave the temperature out altogether.
    function anyTemperature(model as Model) as Boolean {
        for (var i = 0; i < model.packs.size(); i++) {
            if (model.packs[i].temperature != null) {
                return true;
            }
        }
        return false;
    }

    // An angle brought into 0..359.
    function wrap(degrees as Number) as Number {
        return ((degrees % 360) + 360) % 360;
    }
}
