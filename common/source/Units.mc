import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// How values are shown to the person. Packs and recordings always use degrees Celsius.
module Units {

    // "24°", in the unit the watch is set to.
    function temperature(celsius as Number) as String {
        return shown(celsius) + "°";
    }

    // The number of degrees in the unit the watch is set to.
    function shown(celsius as Number) as Number {
        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
            return Math.round(celsius * 9.0 / 5.0 + 32.0).toNumber();
        }
        return celsius;
    }

    // "45m", "1h05", or "12h" from ten hours up.
    function duration(minutes as Number) as String {
        if (minutes < 60) {
            return minutes + "m";
        }
        var hours = minutes / 60;
        if (hours >= 10) {
            return hours + "h";
        }
        return hours + "h" + (minutes % 60).format("%02d");
    }
}
