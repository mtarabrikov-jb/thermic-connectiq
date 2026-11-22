import Toybox.Lang;
import Toybox.Test;

// Unit tests for how raw values from a pack are read and how values are shown. They
// are built only by widget/monkey-test.jungle with monkeyc --unit-test.

(:test)
function durationIsMinutesThenHours(logger as Test.Logger) as Boolean {
    return Units.duration(0).equals("0m") && Units.duration(45).equals("45m")
        && Units.duration(59).equals("59m") && Units.duration(60).equals("1h00")
        && Units.duration(65).equals("1h05") && Units.duration(599).equals("9h59")
        && Units.duration(600).equals("10h") && Units.duration(1234).equals("20h");
}

(:test)
function temperatureOutsideTheRangeIsNoReading(logger as Test.Logger) as Boolean {
    return Protocol.temperature(60) == 20 && Protocol.temperature(20) == -20
        && Protocol.temperature(19) == null && Protocol.temperature(0) == null
        && Protocol.temperature(254) == 214 && Protocol.temperature(255) == null;
}

(:test)
function targetStaysWithinWhatThePhoneAppAllows(logger as Test.Logger) as Boolean {
    return Protocol.clampTarget(14) == 15 && Protocol.clampTarget(15) == 15
        && Protocol.clampTarget(25) == 25 && Protocol.clampTarget(35) == 35
        && Protocol.clampTarget(36) == 35 && Protocol.degrees(65) == 25;
}

(:test)
function wordIsTwoBytesLowFirst(logger as Test.Logger) as Boolean {
    return Protocol.word([0x2d, 0x00]b) == 45 && Protocol.word([0x00, 0x01]b) == 256
        && Protocol.word([0x05]b) == null;
}

(:test)
function troubleNamesWhatAPackSaysIsWrong(logger as Test.Logger) as Boolean {
    var pack = new Pack();
    var nothing = pack.trouble().equals("");
    pack.resistance = 840;
    pack.allowed = true;
    var fine = pack.trouble().equals("");
    pack.allowed = false;
    var blocked = pack.trouble().equals("heat blocked");
    pack.resistance = Protocol.RESISTANCE_OPEN;
    var open = pack.trouble().equals("no heater?");
    return nothing && fine && blocked && open;
}
