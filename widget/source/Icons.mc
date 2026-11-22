import Toybox.Graphics;
import Toybox.Lang;

// Small pictures made of lines and shapes. A bitmap has to stick to the 64 colours of
// this display or it gets dithered into speckles; shapes cannot go wrong that way.
// Unless said otherwise the caller chooses the colour.
module Icons {

    const FOOT_HEIGHT = 30;
    const THERMOMETER_HEIGHT = 20;
    const BATTERY_WIDTH = 18;
    const BATTERY_HEIGHT = 9;

    // A footprint, about 19 wide; x is the middle of its sole and y its top. The big
    // toe is on the inner side, so a left and a right foot next to each other face one
    // another.
    function foot(dc as Dc, x as Number, y as Number, left as Boolean) as Void {
        var inner = left ? 1 : -1;
        // Sole: ball, arch and heel.
        dc.fillEllipse(x, y + 15, 7, 7);
        dc.fillEllipse(x - inner, y + 21, 5, 6);
        dc.fillEllipse(x - inner, y + 25, 5, 5);
        // Toes, from the big one outwards and a little lower each time.
        dc.fillEllipse(x + inner * 5, y + 4, 3, 4);
        dc.fillCircle(x - inner, y + 3, 2);
        dc.fillCircle(x - inner * 6, y + 5, 2);
        dc.fillCircle(x - inner * 9, y + 10, 1);
    }

    // A thermometer, about 10 wide; x is the middle of its tube and y its top.
    function thermometer(dc as Dc, x as Number, y as Number) as Void {
        dc.fillRoundedRectangle(x - 2, y, 5, 14, 2);
        dc.fillCircle(x, y + 15, 4);
        dc.drawLine(x + 4, y + 2, x + 8, y + 2);
        dc.drawLine(x + 4, y + 6, x + 7, y + 6);
        dc.drawLine(x + 4, y + 10, x + 8, y + 10);
    }

    // A warning sign, 17 wide and 16 high, in place of the thermometer when a pack says
    // something is wrong; x is its middle and y its top. Sets its own colours.
    function warning(dc as Dc, x as Number, y as Number) as Void {
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, y], [x - 8, y + 15], [x + 8, y + 15]]);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - 1, y + 5, 2, 6);
        dc.fillRectangle(x - 1, y + 12, 2, 2);
    }

    const CLOCK_SIZE = 11;

    // A clock face showing a little past twelve; x is its left edge and y its top.
    function clock(dc as Dc, x as Number, y as Number) as Void {
        var cx = x + 5;
        var cy = y + 5;
        dc.drawCircle(cx, cy, 5);
        dc.drawLine(cx, cy, cx, cy - 4);
        dc.drawLine(cx, cy, cx + 3, cy);
    }

    // A small arrowhead pointing right, from a reading to its target; x is its left
    // edge and y its middle.
    function pointer(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([[x, y - 4], [x, y + 4], [x + 5, y]]);
    }

    // A battery filled as far as it is charged; x is its left edge and y its top.
    // Sets its own colours: grey outline, white charge, red charge when nearly empty.
    function battery(dc as Dc, x as Number, y as Number, percent as Number?) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, 16, BATTERY_HEIGHT);
        dc.fillRectangle(x + 16, y + 3, 2, 3);
        if (percent != null && percent > 0) {
            var width = 12 * percent / 100;
            if (width < 1) {
                width = 1;
            }
            dc.setColor((percent <= 15) ? Graphics.COLOR_RED : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + 2, y + 2, width, BATTERY_HEIGHT - 4);
        }
    }
}
