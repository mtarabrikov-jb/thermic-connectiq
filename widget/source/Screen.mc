import Toybox.Graphics;
import Toybox.Lang;

// Drawing shared by the main page and the control page.
module Screen {

    // With two packs the ring is split at the top; this is half of the gap, in degrees.
    const SPLIT_GAP = 6;
    // How far each pack's column stands from the middle of the screen.
    const COLUMN = 46;

    // control = false: what the packs report. control = true: the level being set.
    function draw(dc as Dc, model as Model, control as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = ((cx < cy) ? cx : cy) - 8;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Two packs on the main page get a column each, left and right. The control page
        // keeps one number, because a level is set for both packs at once.
        if (!control && model.packs.size() == 2) {
            drawPair(dc, model, cx, cy, radius);
        } else {
            drawSingle(dc, model, control, cx, cy, radius);
        }
    }

    // One level in the middle. Under it, for each pack, the temperature at its gear
    // when any pack reports one, and its battery.
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

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 80, Graphics.FONT_XTINY, control ? "SET LEVEL" : "THERM-IC", Graphics.TEXT_JUSTIFY_CENTER);
        drawLevel(dc, cx, cy - 14, shown, Graphics.FONT_NUMBER_HOT, Graphics.FONT_LARGE);

        var count = model.packs.size();
        var warm = anyTemperature(model);
        if (count == 0) {
            var status = model.connecting ? "connecting..." : (model.searching ? "searching..." : "no pack");
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 30, Graphics.FONT_TINY, status, Graphics.TEXT_JUSTIFY_CENTER);
        }
        for (var i = 0; i < count; i++) {
            var pack = model.packs[i];
            var x = cx;
            if (count > 1) {
                x += (i == 0) ? -40 : 40;
            }
            if (warm) {
                drawTemperature(dc, x, cy + 22, pack.temperature);
            }
            drawBattery(dc, x, cy + (warm ? 48 : 32), pack.battery);
        }
        if (count == 1 && model.searching) {
            // Still looking for a second pack.
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 44, cy + (warm ? 48 : 32), Graphics.FONT_XTINY, "+", Graphics.TEXT_JUSTIFY_CENTER);
        }
        drawHint(dc, model, control, cx, cy + (warm ? 70 : 58));
    }

    // The first pack on the left, the second on the right. Each has a foot above it, its
    // own half of the ring, its level, its temperature and its battery.
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
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx, cy - 52, cx, cy + (warm ? 52 : 28));

        for (var i = 0; i < 2; i++) {
            var pack = model.packs[i];
            var x = cx + ((i == 0) ? -COLUMN : COLUMN);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            Icons.foot(dc, x, cy - 92, i == 0);
            drawLevel(dc, x, cy - 30, pack.level, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_MEDIUM);
            if (warm) {
                drawTemperature(dc, x, cy - 4, pack.temperature);
            }
            drawBattery(dc, x, cy + (warm ? 26 : 2), pack.battery);
        }
        drawHint(dc, model, false, cx, cy + (warm ? 58 : 36));
    }

    // A level with a thermometer in front of it: a big number, "OFF" for zero and "--"
    // while it is not known. x and y are the middle of the two together.
    function drawLevel(dc as Dc, x as Number, y as Number, level as Number?,
            numberFont as Graphics.FontType, textFont as Graphics.FontType) as Void {
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
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        Icons.thermometer(dc, start + 3, y - Icons.THERMOMETER_HEIGHT / 2);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start + 16 + width / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // "24°", or "--" for a pack without a reading. x is the middle, y the top.
    function drawTemperature(dc as Dc, x as Number, y as Number, degrees as Number?) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_TINY, (degrees != null) ? Units.temperature(degrees) : "--", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // A battery and "87%" next to it. x is the middle of the two together, y the top.
    function drawBattery(dc as Dc, x as Number, y as Number, percent as Number?) as Void {
        var font = Graphics.FONT_XTINY;
        var text = (percent != null) ? (percent + "%") : "--";
        var start = x - (Icons.BATTERY_WIDTH + 4 + dc.getTextWidthInPixels(text, font)) / 2;
        Icons.battery(dc, start, y + (dc.getFontHeight(font) - Icons.BATTERY_HEIGHT) / 2, percent);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start + Icons.BATTERY_WIDTH + 4, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Bottom line: what the buttons do, or in red what went wrong.
    function drawHint(dc as Dc, model as Model, control as Boolean, cx as Number, y as Number) as Void {
        var hint = control ? "UP/DN  START on/off" : "START to set";
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (model.note.length() > 0) {
            hint = model.note;
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        } else if (control && model.packs.size() == 0) {
            hint = "no pack connected";
        }
        dc.drawText(cx, y, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
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
