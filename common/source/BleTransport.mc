import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;

// One connected pack.
(:real)
class Link {
    public var device as Device;
    public var scan as ScanResult;
    public var pack as Pack;
    public var heat as Characteristic? = null;
    public var battery as Characteristic? = null;
    public var temperature as Characteristic? = null;
    // Level waiting to be written; null when nothing is pending.
    public var pendingLevel as Number? = null;

    public function initialize(newDevice as Device, newScan as ScanResult, newPack as Pack) {
        device = newDevice;
        scan = newScan;
        pack = newPack;
    }
}

// One queued GATT request.
(:real)
class Op {
    public var link as Link;
    public var kind as Symbol;

    public function initialize(newLink as Link, newKind as Symbol) {
        link = newLink;
        kind = newKind;
    }
}

(:real)
function makeTransport(model as Model) as Transport {
    return new $.BleTransport(model);
}

// Direct Bluetooth LE link to the packs, without bonding.
//
// Lessons from the probe widget that shape this class:
//   - the watch scans passively and only reports advertisers that set the
//     "discoverable" flag, so a pack is recognised by its service UUID alone;
//   - Connect IQ takes one GATT request at a time, hence the queue;
//   - nothing is written on connect - only setLevel() writes.
//
// There is no timer in here, because a data field is not allowed one. The host calls
// onTick() once a second instead.
(:real)
class BleTransport extends BluetoothLowEnergy.BleDelegate {

    // Housekeeping runs on every third call of onTick().
    private const TICKS_PER_CHECK = 3;
    // Measured on a fenix 6S Pro inside an activity: 30 s from pairDevice() to the watch
    // reporting the connection, of which 25 s pass after the link is already up. With a
    // limit of 30 s the data field never connected: every attempt was dropped 25 s after
    // its link came up. Keep a wide margin.
    private const CONNECT_TIMEOUT_MS = 90000;
    private const OP_TIMEOUT_MS = 10000;
    // How long to keep looking for a second pack once one is connected.
    private const SEARCH_MORE_MS = 45000;

    private var _model as Model;
    private var _serviceUuid as Uuid;
    private var _heatUuid as Uuid;
    private var _batteryUuid as Uuid;
    private var _temperatureUuid as Uuid;

    private var _links as Array<Link> = [] as Array<Link>;
    private var _ops as Array<Op> = [] as Array<Op>;
    private var _current as Op? = null;
    private var _currentSince as Number = 0;
    private var _sentLevel as Number = 0;

    // The single connection attempt in progress.
    private var _pendingScan as ScanResult? = null;
    private var _pendingDevice as Device? = null;
    private var _pendingSince as Number = 0;

    private var _ticks as Number = 0;
    private var _running as Boolean = false;
    private var _scanning as Boolean = false;
    private var _searchUntil as Number = 0;

    public function initialize(model as Model) {
        BleDelegate.initialize();
        _model = model;
        _serviceUuid = Protocol.uuid(Protocol.CODE_SERVICE);
        _heatUuid = Protocol.uuid(Protocol.CODE_HEAT);
        _batteryUuid = Protocol.uuid(Protocol.CODE_BATTERY);
        _temperatureUuid = Protocol.uuid(Protocol.CODE_TEMPERATURE);
    }

    public function start() as Void {
        BluetoothLowEnergy.setDelegate(self);
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => _serviceUuid,
                :characteristics => [
                    { :uuid => _heatUuid, :descriptors => [BluetoothLowEnergy.cccdUuid()] },
                    { :uuid => _batteryUuid, :descriptors => [BluetoothLowEnergy.cccdUuid()] },
                    { :uuid => _temperatureUuid, :descriptors => [BluetoothLowEnergy.cccdUuid()] }
                ]
            });
        } catch (e) {
            trace("profile error");
            _model.note = "profile error";
            _model.changed();
            return;
        }
        trace("start");
        _running = true;
        _searchUntil = System.getTimer() + SEARCH_MORE_MS;
        updateScan();
    }

    public function stop() as Void {
        trace("stop");
        _running = false;
        setScan(false);
        for (var i = 0; i < _links.size(); i++) {
            unpair(_links[i].device);
        }
        if (_pendingDevice != null) {
            unpair(_pendingDevice as Device);
        }
        _links = [] as Array<Link>;
        _ops = [] as Array<Op>;
        _current = null;
        _pendingScan = null;
        _pendingDevice = null;
    }

    // The only place that writes to a pack.
    public function setLevel(level as Number) as Void {
        _model.target = level;
        var sent = false;
        for (var i = 0; i < _links.size(); i++) {
            var link = _links[i];
            if (link.heat == null) {
                continue;
            }
            link.pendingLevel = level;
            if (!queued(link, :write)) {
                _ops.add(new Op(link, :write));
            }
            sent = true;
        }
        if (!sent) {
            // Nothing to send to: fall back to what is known.
            _model.userDone();
            return;
        }
        _model.changed();
        run();
    }

    public function onProfileRegister(uuid as Uuid, status as Status) as Void {
        trace("profile status " + status);
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            _model.note = "profile " + status;
            _model.changed();
        }
    }

    public function onScanStateChange(scanState as ScanState, status as Status) as Void {
        var scanning = (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING);
        if (scanning != _scanning) {
            // Not asked for by setScan(): another app, or the watch itself.
            trace("scan turned " + (scanning ? "on" : "off") + " from outside, status " + status);
        }
        _scanning = scanning;
    }

    public function onScanResults(scanResults as Iterator) as Void {
        if (!_running || _pendingScan != null || _links.size() >= _model.MAX_PACKS) {
            return;
        }
        for (var result = scanResults.next(); result != null; result = scanResults.next()) {
            if (!(result instanceof ScanResult)) {
                continue;
            }
            if (!hasService(result.getServiceUuids()) || known(result)) {
                continue;
            }
            // One connection attempt at a time; scanning resumes when it ends.
            setScan(false);
            try {
                var device = BluetoothLowEnergy.pairDevice(result);
                if (device != null) {
                    _pendingScan = result;
                    _pendingDevice = device;
                    _pendingSince = System.getTimer();
                    trace("found a pack, connecting");
                }
            } catch (e) {
                trace("connect error");
                _model.note = "connect error";
            }
            updateScan();
            return;
        }
    }

    public function onConnectedStateChanged(device as Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        var connected = (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED);
        trace((connected ? "connected" : "disconnected")
            + (_pendingScan != null ? ", attempt pending" : ", no attempt pending")
            + ", packs " + _links.size());
        if (connected) {
            var scan = _pendingScan;
            _pendingScan = null;
            _pendingDevice = null;
            if (scan == null) {
                // Not an attempt this class started.
                unpair(device);
            } else {
                adopt(device, scan);
            }
        } else if (!sweep()) {
            // No known link went away, so the pending attempt is the one that failed.
            _pendingScan = null;
            _pendingDevice = null;
        }
        _searchUntil = System.getTimer() + SEARCH_MORE_MS;
        updateScan();
        run();
    }

    public function onCharacteristicRead(characteristic as Characteristic, status as Status, value as ByteArray) as Void {
        trace("read status " + status + ", value " + value);
        var op = _current;
        if (op != null) {
            if (status == BluetoothLowEnergy.STATUS_SUCCESS && value.size() > 0) {
                if (op.kind == :readHeat) {
                    op.link.pack.level = value[0];
                    _model.packReported();
                } else if (op.kind == :readBattery) {
                    op.link.pack.battery = value[0];
                } else if (op.kind == :readTemperature) {
                    op.link.pack.temperature = Protocol.temperature(value[0]);
                }
            } else if (op.kind != :readTemperature) {
                // The temperature is an extra: a pack that will not give it is still
                // a pack, so that failure is not shown as an error.
                report(status);
            }
        }
        finish();
    }

    public function onCharacteristicWrite(characteristic as Characteristic, status as Status) as Void {
        trace("write status " + status);
        var op = _current;
        if (op != null && op.kind == :write) {
            if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
                op.link.pack.level = _sentLevel;
                _model.note = "";
            } else {
                report(status);
            }
            if (!writesPending()) {
                _model.userDone();
            }
        }
        finish();
    }

    private function writesPending() as Boolean {
        for (var i = 0; i < _links.size(); i++) {
            if (_links[i].pendingLevel != null) {
                return true;
            }
        }
        return false;
    }

    public function onDescriptorWrite(descriptor as Descriptor, status as Status) as Void {
        trace("subscribe status " + status);
        finish();
    }

    // The pack reports a change, for example after its own button was pressed.
    public function onCharacteristicChanged(characteristic as Characteristic, value as ByteArray) as Void {
        if (value.size() == 0) {
            return;
        }
        for (var i = 0; i < _links.size(); i++) {
            var link = _links[i];
            if (characteristic.equals(link.heat)) {
                trace("level notified, " + value[0]);
                link.pack.level = value[0];
                _model.packReported();
            } else if (characteristic.equals(link.battery)) {
                trace("battery notified, " + value[0]);
                link.pack.battery = value[0];
                _model.packReported();
            } else if (characteristic.equals(link.temperature)) {
                // A pack may send this often. Only a change is worth a redraw and a
                // line in the log.
                var degrees = Protocol.temperature(value[0]);
                if (degrees != link.pack.temperature) {
                    trace("temperature notified, raw " + value[0]);
                    link.pack.temperature = degrees;
                    _model.changed();
                }
            }
        }
    }

    // Housekeeping: give up on a stuck connection attempt or request.
    public function onTick() as Void {
        if (!_running) {
            return;
        }
        _ticks++;
        if (_ticks < TICKS_PER_CHECK) {
            return;
        }
        _ticks = 0;
        var now = System.getTimer();
        if (_pendingDevice != null && now - _pendingSince > CONNECT_TIMEOUT_MS) {
            unpair(_pendingDevice as Device);
            _pendingScan = null;
            _pendingDevice = null;
            trace("connect timeout");
            _model.note = "connect timeout";
        }
        if (_current != null && now - _currentSince > OP_TIMEOUT_MS) {
            _current = null;
            trace("no reply to a request");
            _model.note = "no reply";
            _model.userDone();
        }
        sweep();
        updateScan();
        run();
    }

    private function adopt(device as Device, scan as ScanResult) as Void {
        var service = device.getService(_serviceUuid);
        var heat = (service != null) ? service.getCharacteristic(_heatUuid) : null;
        if (service == null || heat == null) {
            trace("not a pack: service " + (service != null) + ", heat level " + (heat != null));
            _model.note = "not a pack";
            unpair(device);
            return;
        }
        var pack = new Pack();
        var link = new Link(device, scan, pack);
        link.heat = heat;
        link.battery = service.getCharacteristic(_batteryUuid);
        link.temperature = service.getCharacteristic(_temperatureUuid);
        _links.add(link);
        _model.packs.add(pack);
        trace("pack " + _links.size() + " accepted, reading");
        _model.note = "";
        _ops.add(new Op(link, :readHeat));
        _ops.add(new Op(link, :readBattery));
        _ops.add(new Op(link, :readTemperature));
        _ops.add(new Op(link, :subHeat));
        _ops.add(new Op(link, :subBattery));
        _ops.add(new Op(link, :subTemperature));
    }

    // Drops links whose device is gone. Returns true if any was removed.
    private function sweep() as Boolean {
        var links = [] as Array<Link>;
        var packs = [] as Array<Pack>;
        var removed = false;
        for (var i = 0; i < _links.size(); i++) {
            var link = _links[i];
            if (link.device.isConnected()) {
                links.add(link);
                packs.add(link.pack);
            } else {
                removed = true;
                dropOps(link);
            }
        }
        if (removed) {
            trace("pack lost, left " + links.size());
            _links = links;
            _model.packs = packs;
            if (!writesPending()) {
                _model.userPending = false;
            }
            _model.packReported();
        }
        return removed;
    }

    private function dropOps(link as Link) as Void {
        var ops = [] as Array<Op>;
        for (var i = 0; i < _ops.size(); i++) {
            if (_ops[i].link != link) {
                ops.add(_ops[i]);
            }
        }
        _ops = ops;
        if (_current != null && (_current as Op).link == link) {
            _current = null;
        }
    }

    private function finish() as Void {
        _current = null;
        _model.changed();
        run();
    }

    private function run() as Void {
        while (_current == null && _ops.size() > 0) {
            var op = _ops[0];
            _ops = _ops.slice(1, null) as Array<Op>;
            if (issue(op)) {
                _current = op;
                _currentSince = System.getTimer();
            }
        }
    }

    // Sends one request. Returns false when there was nothing to send.
    private function issue(op as Op) as Boolean {
        var link = op.link;
        try {
            if (op.kind == :readHeat && link.heat != null) {
                (link.heat as Characteristic).requestRead();
                return true;
            }
            if (op.kind == :readBattery && link.battery != null) {
                (link.battery as Characteristic).requestRead();
                return true;
            }
            if (op.kind == :readTemperature && link.temperature != null) {
                (link.temperature as Characteristic).requestRead();
                return true;
            }
            if (op.kind == :subHeat) {
                return subscribe(link.heat);
            }
            if (op.kind == :subBattery) {
                return subscribe(link.battery);
            }
            if (op.kind == :subTemperature) {
                return subscribe(link.temperature);
            }
            if (op.kind == :write && link.heat != null && link.pendingLevel != null) {
                _sentLevel = link.pendingLevel as Number;
                link.pendingLevel = null;
                (link.heat as Characteristic).requestWrite(
                    [_sentLevel]b, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
                return true;
            }
        } catch (e) {
            _model.note = "request error";
        }
        return false;
    }

    private function subscribe(characteristic as Characteristic?) as Boolean {
        if (characteristic == null) {
            return false;
        }
        var cccd = characteristic.getDescriptor(BluetoothLowEnergy.cccdUuid());
        if (cccd == null) {
            return false;
        }
        cccd.requestWrite([0x01, 0x00]b);
        return true;
    }

    private function report(status as Status) as Void {
        // 18 and 19 are "insufficient authentication / encryption". The named constants
        // only exist from API 4.2.5, and this watch has no way to bond anyway.
        if (status == 18 || status == 19) {
            _model.note = "needs bonding";
        } else {
            _model.note = "error " + status;
        }
    }

    private function updateScan() as Void {
        var more = _links.size() == 0 || System.getTimer() < _searchUntil;
        var want = _running && _pendingScan == null && _links.size() < _model.MAX_PACKS && more;
        setScan(want);
        _model.searching = want || _pendingScan != null;
        _model.connecting = _pendingScan != null;
        _model.changed();
    }

    private function setScan(on as Boolean) as Void {
        if (on == _scanning) {
            return;
        }
        trace(on ? "scan on" : "scan off");
        _scanning = on;
        BluetoothLowEnergy.setScanState(on ? BluetoothLowEnergy.SCAN_STATE_SCANNING : BluetoothLowEnergy.SCAN_STATE_OFF);
    }

    private function queued(link as Link, kind as Symbol) as Boolean {
        for (var i = 0; i < _ops.size(); i++) {
            if (_ops[i].link == link && _ops[i].kind == kind) {
                return true;
            }
        }
        return false;
    }

    private function known(result as ScanResult) as Boolean {
        for (var i = 0; i < _links.size(); i++) {
            if (result.isSameDevice(_links[i].scan)) {
                return true;
            }
        }
        return false;
    }

    private function hasService(iter as Iterator) as Boolean {
        for (var item = iter.next(); item != null; item = iter.next()) {
            if (item.equals(_serviceUuid)) {
                return true;
            }
        }
        return false;
    }

    // One line per event for the app's log on the watch, stamped with seconds of uptime.
    // The watch keeps it only if GARMIN/Apps/LOGS/<name of the .prg>.TXT exists.
    private function trace(text as String) as Void {
        System.println("ble " + (System.getTimer() / 1000) + " " + text);
    }

    private function unpair(device as Device) as Void {
        try {
            BluetoothLowEnergy.unpairDevice(device);
        } catch (e) {
            // Already gone.
        }
    }
}
