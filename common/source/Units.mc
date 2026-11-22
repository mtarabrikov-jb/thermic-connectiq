import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// How values are shown to the person. Packs and recordings always use degrees Celsius.
module Units {

    // "24°", in the unit the watch is set to.
    function temperature(celsius as Number) as String {
        var value = celsius;
        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
            value = Math.round(celsius * 9.0 / 5.0 + 32.0).toNumber();
        }
        return value + "°";
    }
}
