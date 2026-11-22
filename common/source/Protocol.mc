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

    // S-Pack template split into two 64-bit halves, code bits left as zero.
    const FAMILY_HIGH = 0x73CB0000B80643BDL;
    const FAMILY_LOW = 0x9612E3DE0A18CCB6L;

    function uuid(code as Number) as Uuid {
        return BluetoothLowEnergy.longToUuid(FAMILY_HIGH | (code.toLong() << 32), FAMILY_LOW);
    }
}
