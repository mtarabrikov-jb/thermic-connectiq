import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// What the list of widgets shows for this one: its name. It does not look for packs.
// Connecting takes half a minute and the list is passed in seconds, a glance has 32 KB
// to live in, and scanning there would cost battery every time the list is opened.
(:glance)
class ThermicGlance extends WatchUi.GlanceView {

    public function initialize() {
        GlanceView.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        var middle = dc.getHeight() / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, middle - 22, Graphics.FONT_GLANCE, "THERM-IC", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, middle + 2, Graphics.FONT_XTINY, "heated gear", Graphics.TEXT_JUSTIFY_LEFT);
    }
}
