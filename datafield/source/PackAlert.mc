import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// A few seconds over the activity's own pages: something about a pack needs a look.
//
// Laid out like a data field of the watch itself: what it is about in words on top,
// the value below. The words say whose battery it is, because "battery low" alone on a
// watch reads as the watch's own battery.
class PackAlert extends WatchUi.DataFieldAlert {

    private var _caption as String;
    private var _value as String;

    public function initialize(caption as String, value as String) {
        DataFieldAlert.initialize();
        _caption = caption;
        _value = value;
    }

    public function onUpdate(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        // Room for a line near the middle of a round screen.
        var room = dc.getWidth() - 30;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 68, Graphics.FONT_XTINY, "THERM-IC", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        // The words start one size below the value, so that the value stays the larger.
        dc.drawText(cx, cy - 22, fitting(dc, _caption, room, 1), _caption,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 20, fitting(dc, _value, room, 0), _value,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The largest font in which the text fits the width. The search starts at the
    // given place in the list of fonts, 0 for the largest.
    private function fitting(dc as Dc, text as String, width as Number, first as Number) as Graphics.FontType {
        var fonts = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
            Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontType>;
        var font = fonts[first];
        for (var i = first; i < fonts.size(); i++) {
            font = fonts[i];
            if (dc.getTextWidthInPixels(text, font) <= width) {
                break;
            }
        }
        return font;
    }
}
