import Toybox.Graphics;
import Toybox.Lang;

// Drawing shared by the main page and the control page.
module Screen {

    // control = false: what the packs report. control = true: the level being set.
    function draw(dc as Dc, model as Model, control as Boolean) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var actual = model.level();
        var shown = control ? model.target : actual;
        if (shown == null) {
            shown = actual;
        }

        // Level ring: 270 degrees, from the lower left clockwise to the lower right.
        // Angles are counter-clockwise from three o'clock.
        var radius = ((w < h) ? w : h) / 2 - 8;
        dc.setPenWidth(8);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, 315);
        if (shown != null && shown > 0) {
            var end = 225 - 270 * shown / Protocol.MAX_LEVEL;
            if (end < 0) {
                end += 360;
            }
            dc.setColor(control ? Graphics.COLOR_YELLOW : Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, end);
        }
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 80, Graphics.FONT_XTINY, control ? "SET LEVEL" : "THERM-IC", Graphics.TEXT_JUSTIFY_CENTER);

        var text = "--";
        var font = Graphics.FONT_LARGE;
        if (shown != null) {
            if (shown == 0) {
                text = "OFF";
            } else {
                text = shown.toString();
                font = Graphics.FONT_NUMBER_HOT;
            }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 14, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 30, Graphics.FONT_TINY, packsLine(model), Graphics.TEXT_JUSTIFY_CENTER);

        var hint = control ? "UP/DN  START on/off" : "START to set";
        if (model.note.length() > 0) {
            hint = model.note;
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        } else if (control && model.packs.size() == 0) {
            hint = "no pack connected";
        }
        dc.drawText(cx, cy + 60, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // "87%   64%", with each pack's own level in front when the packs disagree.
    function packsLine(model as Model) as String {
        var count = model.packs.size();
        if (count == 0) {
            if (model.connecting) {
                return "connecting...";
            }
            return model.searching ? "searching..." : "no pack";
        }
        var differ = model.levelsDiffer();
        var line = "";
        for (var i = 0; i < count; i++) {
            var pack = model.packs[i];
            if (i > 0) {
                line += "   ";
            }
            if (differ && pack.level != null) {
                line += pack.level + ": ";
            }
            line += (pack.battery != null) ? (pack.battery + "%") : "--";
        }
        if (model.searching && count < model.MAX_PACKS) {
            line += "  +";
        }
        return line;
    }
}
