import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Scans for the pack, connects without bonding, then runs GATT operations one at a
// time: read heat level, read battery, subscribe to heat level, write a level.
// Connect IQ accepts only one pending GATT request, hence the step queue.
class Probe extends BluetoothLowEnergy.BleDelegate {

    // S-Pack family: 73cbXXXX-b806-43bd-9612-e3de0a18ccb6.
    // XXXX: 0001 service, 0002 heat level (1 byte, 0..10), 0005 battery (1 byte, %).
    private const SERVICE = BluetoothLowEnergy.longToUuid(0x73CB0001B80643BDL, 0x9612E3DE0A18CCB6L);
    private const HEAT = BluetoothLowEnergy.longToUuid(0x73CB0002B80643BDL, 0x9612E3DE0A18CCB6L);
    private const BATTERY = BluetoothLowEnergy.longToUuid(0x73CB0005B80643BDL, 0x9612E3DE0A18CCB6L);
    // Fallback match in case the service UUID is not parsed from the advertisement.
    private const EMULATOR_NAME = "SPackEmu";

    public var stage as String = "init";
    public var detail as String = "";
    public var level as Number? = null;
    public var battery as Number? = null;
    public var rssi as Number? = null;
    public var seen as Number = 0;      // advertisements looked at
    public var writes as Number = 0;    // writes confirmed by the pack
    public var notifies as Number = 0;  // notifications received
    public var drops as Number = 0;     // disconnects
    public var lastWrite as String = "-";
    public var matchedBy as String = "-";
    public var distinct as Number = 0;  // different advertisement payloads seen
    public var bestRssi as Number? = null;
    public var inputs as Number = 0;    // input events delivered to the widget
    public var lastInput as String = "-";
    private var _recent as Array<String> = [] as Array<String>;

    // Payloads already written to the log, to print each advertiser once.
    private var _logged as Array<String> = [] as Array<String>;

    private var _device as Device?;
    private var _heat as Characteristic?;
    private var _battery as Characteristic?;
    private var _steps as Array<Symbol> = [] as Array<Symbol>;
    private var _busy as Boolean = false;
    private var _target as Number = 0;
    private var _autoWriteDone as Boolean = false;

    public function initialize() {
        BleDelegate.initialize();
    }

    public function start() as Void {
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => SERVICE,
                :characteristics => [
                    { :uuid => HEAT, :descriptors => [BluetoothLowEnergy.cccdUuid()] },
                    { :uuid => BATTERY }
                ]
            });
        } catch (e) {
            setStage("register failed", describe(e));
            return;
        }
        scan();
    }

    public function stop() as Void {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        if (_device != null) {
            BluetoothLowEnergy.unpairDevice(_device as Device);
        }
        _device = null;
    }

    public function scan() as Void {
        _heat = null;
        _battery = null;
        _steps = [] as Array<Symbol>;
        _busy = false;
        setStage("scanning", "");
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    // MENU: drop the connection and search again.
    public function rescan() as Void {
        if (_device != null) {
            BluetoothLowEnergy.unpairDevice(_device as Device);
            _device = null;
        }
        scan();
    }

    // Records every input event the watch delivers, to tell real presses from
    // events the system generates on its own.
    public function noteInput(text as String) as Void {
        inputs++;
        // Keep the last three events on screen, oldest first.
        _recent.add(text);
        if (_recent.size() > 3) {
            _recent = _recent.slice(1, null) as Array<String>;
        }
        lastInput = "";
        for (var i = 0; i < _recent.size(); i++) {
            lastInput += (i > 0 ? " " : "") + _recent[i];
        }
        System.println("input #" + inputs + " " + text + " level " + level + " stage " + stage);
        WatchUi.requestUpdate();
    }

    public function freeConnections() as Number {
        return BluetoothLowEnergy.getAvailableConnectionCount();
    }

    // UP / DOWN: change the level by delta, clamped to 0..10.
    public function bump(delta as Number) as Void {
        var value = (level != null ? level as Number : 0) + delta;
        if (value < 0) {
            value = 0;
        } else if (value > 10) {
            value = 10;
        }
        requestLevel(value);
    }

    // START: next level, wrapping from 10 to 0.
    public function cycle() as Void {
        requestLevel(((level != null ? level as Number : 0) + 1) % 11);
    }

    private function requestLevel(value as Number) as Void {
        if (_heat == null) {
            return;
        }
        _target = value;
        if (_steps.indexOf(:setLevel) < 0) {
            _steps.add(:setLevel);
        }
        next();
    }

    public function onProfileRegister(uuid as Uuid, status as Status) as Void {
        System.println("profile register status " + status);
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            setStage("register failed", "status " + status);
        }
    }

    public function onScanStateChange(scanState as ScanState, status as Status) as Void {
        System.println("scan state " + scanState + " status " + status);
    }

    public function onScanResults(scanResults as Iterator) as Void {
        if (_device != null) {
            return;
        }
        for (var result = scanResults.next(); result != null; result = scanResults.next()) {
            if (!(result instanceof ScanResult)) {
                continue;
            }
            seen++;
            var name = result.getDeviceName();
            var strength = result.getRssi();
            if (bestRssi == null || strength > (bestRssi as Number)) {
                bestRssi = strength;
            }
            var raw = result.getRawData().toString();
            if (_logged.indexOf(raw) < 0 && _logged.size() < 60) {
                _logged.add(raw);
                distinct = _logged.size();
                System.println("adv rssi " + strength + " name " + name + " raw " + raw);
            }
            var byUuid = contains(result.getServiceUuids(), SERVICE);
            var byName = (name != null) && name.equals(EMULATOR_NAME);
            if (byUuid || byName) {
                matchedBy = byUuid ? "uuid" : "name";
                rssi = result.getRssi();
                BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
                setStage("connecting", name != null ? name : "no name");
                try {
                    _device = BluetoothLowEnergy.pairDevice(result);
                } catch (e) {
                    setStage("pair failed", describe(e));
                }
                return;
            }
        }
        WatchUi.requestUpdate();
    }

    public function onConnectedStateChanged(device as Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state != BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            drops++;
            _device = null;
            System.println("disconnected, state " + state);
            scan();
            return;
        }
        _device = device;
        var service = device.getService(SERVICE);
        if (service == null) {
            setStage("no service", "");
            return;
        }
        _heat = service.getCharacteristic(HEAT);
        _battery = service.getCharacteristic(BATTERY);
        if (_heat == null) {
            setStage("no heat char", "");
            return;
        }
        setStage("connected", "reading");
        _steps = [:readHeat, :readBattery, :subscribe, :autoWrite] as Array<Symbol>;
        _busy = false;
        next();
    }

    public function onCharacteristicRead(characteristic as Characteristic, status as Status, value as ByteArray) as Void {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS && value.size() > 0) {
            if (characteristic.getUuid().equals(HEAT)) {
                level = value[0];
            } else if (characteristic.getUuid().equals(BATTERY)) {
                battery = value[0];
            }
        } else {
            detail = "read status " + status;
        }
        done();
    }

    public function onCharacteristicWrite(characteristic as Characteristic, status as Status) as Void {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            writes++;
            level = _target;
            lastWrite = "ok " + _target;
        } else {
            lastWrite = "fail " + status;
        }
        done();
    }

    public function onDescriptorWrite(descriptor as Descriptor, status as Status) as Void {
        detail = (status == BluetoothLowEnergy.STATUS_SUCCESS) ? "subscribed" : ("cccd status " + status);
        done();
    }

    public function onCharacteristicChanged(characteristic as Characteristic, value as ByteArray) as Void {
        notifies++;
        if (value.size() > 0 && characteristic.getUuid().equals(HEAT)) {
            level = value[0];
        }
        WatchUi.requestUpdate();
    }

    private function done() as Void {
        _busy = false;
        next();
    }

    private function next() as Void {
        if (_busy) {
            return;
        }
        if (_steps.size() == 0) {
            if (_heat != null) {
                stage = "ready";
            }
            WatchUi.requestUpdate();
            return;
        }
        var step = _steps[0];
        _steps = _steps.slice(1, null) as Array<Symbol>;
        var started = false;
        try {
            if (step == :readHeat && _heat != null) {
                (_heat as Characteristic).requestRead();
                started = true;
            } else if (step == :readBattery && _battery != null) {
                (_battery as Characteristic).requestRead();
                started = true;
            } else if (step == :subscribe && _heat != null) {
                var cccd = (_heat as Characteristic).getDescriptor(BluetoothLowEnergy.cccdUuid());
                if (cccd != null) {
                    cccd.requestWrite([0x01, 0x00]b);
                    started = true;
                } else {
                    detail = "no cccd";
                }
            } else if (step == :autoWrite && _heat != null && !_autoWriteDone) {
                // One write without any button press, so the result does not depend
                // on how the watch delivers input to a widget.
                _autoWriteDone = true;
                _target = ((level != null ? level as Number : 0) + 1) % 11;
                sendLevel();
                started = true;
            } else if (step == :setLevel && _heat != null) {
                sendLevel();
                started = true;
            }
        } catch (e) {
            setStage("op failed", describe(e));
        }
        _busy = started;
        if (!started) {
            next();
        } else {
            WatchUi.requestUpdate();
        }
    }

    private function sendLevel() as Void {
        (_heat as Characteristic).requestWrite([_target]b, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
    }

    private function setStage(newStage as String, newDetail as String) as Void {
        stage = newStage;
        detail = newDetail;
        System.println(newStage + " " + newDetail);
        WatchUi.requestUpdate();
    }

    private function describe(e as Exception) as String {
        var message = e.getErrorMessage();
        return message != null ? message : "exception";
    }

    private function contains(iter as Iterator, uuid as Uuid) as Boolean {
        for (var item = iter.next(); item != null; item = iter.next()) {
            if (item.equals(uuid)) {
                return true;
            }
        }
        return false;
    }
}
