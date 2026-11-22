import Toybox.BluetoothLowEnergy;
import Toybox.Lang;

// Therm-ic battery pack protocol, taken from the decompiled phone app
// (com.thermic.app 1.0.3) and confirmed against that app with pack_emulator.py.
//
// Every property is its own GATT characteristic. A UUID is the family template with a
// 16-bit code in place of XXXX:
//   0001  service
//   0002  heat level, 1 byte, 0..10, read / write / notify
//   0005  battery level, 1 byte, percent, read / notify
//   0010  remaining heat time, 2 bytes, minutes, read / notify
//   0012  internal temperature, 1 byte, value - 40 = degrees Celsius, read
//   0013  external temperature, 1 byte, value - 40 = degrees Celsius, read / notify
//   0015  target temperature regulation, 1 byte, 1 on / 0 off, read / write
//   0016  target temperature, 1 byte, value - 40 = degrees Celsius, read / write
//
// Family templates:
//   S-Pack    73cbXXXX-b806-43bd-9612-e3de0a18ccb6
//   C-Pack    dabeXXXX-1e1c-4f9e-931c-1ac4c235254b
//   B-Pack    04f9XXXX-a0e9-4111-b3bd-0221dff2d442
//   I-Pack    c1f2XXXX-b64c-4b4f-9482-cf47b4b5cfa4
//   BodyPack  28b3XXXX-98a2-4c6d-9287-2fc3d1f37682
// The watch registers at most three profiles, so one family is compiled in.
module Protocol {

    const MAX_LEVEL = 10;

    const CODE_SERVICE = 0x0001;
    const CODE_HEAT = 0x0002;
    const CODE_BATTERY = 0x0005;
    // "External temperature": the one a pack regulates by, so it is taken to be the
    // temperature at the heated gear. What it measures on real gear is not known.
    const CODE_TEMPERATURE = 0x0013;

    // The phone app takes an external temperature as present only from -20 to 214
    // degrees and otherwise acts as if the gear had no sensor. The same range is used
    // here; a raw FF, for example, falls outside it.
    const TEMPERATURE_OFFSET = 40;
    const TEMPERATURE_MIN = -20;
    const TEMPERATURE_MAX = 214;

    // What only the widget reads.
    const CODE_REMAINING = 0x0010;
    const CODE_INSIDE = 0x0012;
    const CODE_REGULATION = 0x0015;
    const CODE_TARGET = 0x0016;

    // The phone app lets the target temperature be set from 15 to 35 degrees and starts
    // a new product at 25.
    const TARGET_MIN = 15;
    const TARGET_MAX = 35;
    const TARGET_DEFAULT = 25;

    // S-Pack template split into two 64-bit halves, code bits left as zero.
    const FAMILY_HIGH = 0x73CB0000B80643BDL;
    const FAMILY_LOW = 0x9612E3DE0A18CCB6L;

    // Degrees Celsius for the raw byte, or null when it does not hold a reading.
    function temperature(raw as Number) as Number? {
        var degrees = raw - TEMPERATURE_OFFSET;
        return (degrees >= TEMPERATURE_MIN && degrees <= TEMPERATURE_MAX) ? degrees : null;
    }

    // Degrees Celsius for the raw byte of the other temperatures, which have no value
    // that stands for "no reading".
    function degrees(raw as Number) as Number {
        return raw - TEMPERATURE_OFFSET;
    }

    // A two-byte value, low byte first, or null when the bytes are not all there.
    function word(bytes as ByteArray) as Number? {
        if (bytes.size() < 2) {
            return null;
        }
        return bytes[0] | (bytes[1] << 8);
    }

    // A target temperature brought into the range a pack is given.
    function clampTarget(degrees as Number) as Number {
        if (degrees < TARGET_MIN) {
            return TARGET_MIN;
        }
        return (degrees > TARGET_MAX) ? TARGET_MAX : degrees;
    }

    function uuid(code as Number) as Uuid {
        return BluetoothLowEnergy.longToUuid(FAMILY_HIGH | (code.toLong() << 32), FAMILY_LOW);
    }
}
