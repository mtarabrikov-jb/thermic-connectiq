#!/usr/bin/env python3
"""BLE peripheral that imitates a Therm-ic battery pack.

Purpose: watch what the official Therm-ic phone app reads and writes, and later test a
Garmin watch app, without real hardware. It only logs writes - nothing heats up.

Protocol source: decompiled com.thermic.app 1.0.3 (version code 49).
  - UUID = family template with a 4-hex-digit code; code 0001 is the service.
  - Every property is its own GATT characteristic, one or two bytes, little-endian.
  - No bonding is requested by the app; characteristics here need no encryption.

Requires BlueZ with the D-Bus GATT server API and the system python3-dbus / python3-gi.

BlueZ publishes its own Device Information service (0x180A, PnP ID only) by default.
The phone app looks up 0x180A and takes the first instance, so that built-in service
hides the one defined here and the app drops the connection as "not supported".
Disable it once: set `DeviceID = false` in the [General] section of
/etc/bluetooth/main.conf and restart the bluetooth service.

Usage:
  pack_emulator.py [--family s|c|b|i|body] [--name NAME] [--duration SECONDS]
                   [--log FILE] [--selftest]

Console commands while running from a terminal:
  heat N       pretend the button on the pack changed the level (0..10)
  battery N    set battery level in percent
  charge N     0 not charging, 1 pre-charge, 2 charging, 3 complete
  allowed 0|1  heating allowed flag
  ext T        external temperature, degrees Celsius
  int T        temperature inside the pack, degrees Celsius
  res N        heater resistance as the pack reports it; 65535 for no heater
  drop         cut the link, as when the pack goes out of range; it advertises again
  show         print current state
  quit         cut the link and stop, as when the pack is switched off
"""
import argparse
import datetime
import re
import signal
import sys

import dbus
import dbus.exceptions
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BLUEZ = 'org.bluez'
DBUS_OM = 'org.freedesktop.DBus.ObjectManager'
DBUS_PROP = 'org.freedesktop.DBus.Properties'
GATT_MGR = 'org.bluez.GattManager1'
ADV_MGR = 'org.bluez.LEAdvertisingManager1'
GATT_SVC = 'org.bluez.GattService1'
GATT_CHRC = 'org.bluez.GattCharacteristic1'
ADV_IFACE = 'org.bluez.LEAdvertisement1'
APP_PATH = '/thermic/emu'

FAMILIES = {
    's': ('S_PACK', '73cb%s-b806-43bd-9612-e3de0a18ccb6'),
    'c': ('C_PACK', 'dabe%s-1e1c-4f9e-931c-1ac4c235254b'),
    'b': ('B_PACK', '04f9%s-a0e9-4111-b3bd-0221dff2d442'),
    'i': ('I_PACK', 'c1f2%s-b64c-4b4f-9482-cf47b4b5cfa4'),
    'body': ('BODY_PACK', '28b3%s-98a2-4c6d-9287-2fc3d1f37682'),
}
# Second service the app requires to be present; by its method signatures it is the
# firmware update channel. Writes are logged and otherwise ignored.
OTA_TEMPLATE = '27b3%s-98a2-4c6d-9287-2fc3d1f37682'
SIG_UUID = '0000%s-0000-1000-8000-00805f9b34fb'

CHARGE = {0: 'NOT_CHARGING', 1: 'PRE_CHARGE', 2: 'CHARGING', 3: 'CHARGING_COMPLETE'}

# code, name, access (r read, w write, n notify), size in bytes, initial value, kind.
# "poll" in the app means it re-reads periodically, so those are plain read here.
# kind: level 0..10 | pct | u16 | minutes | temp (stored +40) | charge |
#       on1 (1 = enabled) | on0 (0 = enabled) | raw
FIELDS = [
    ('0002', 'HEAT_LEVEL', 'rwn', 1, 0, 'level'),
    ('0004', 'HEATER_RESISTANCE', 'rn', 2, 50, 'u16'),
    ('0005', 'BATTERY_LEVEL', 'rn', 1, 87, 'pct'),
    ('0006', 'BATTERY_CAPACITY', 'r', 2, 1400, 'u16'),
    ('0007', 'BATTERY_CURRENT_CONSUMPTION', 'r', 2, 0, 'u16'),
    ('0008', 'BATTERY_CHARGE_STATUS', 'rn', 1, 0, 'charge'),
    ('0009', 'LED_ACTIVATION_STATUS', 'rw', 1, 0, 'on0'),
    ('000A', 'LED_STATUS', 'r', 1, 0, 'raw'),
    ('000B', 'DEVICE_SLEEP', 'w', 1, 0, 'raw'),
    ('000C', 'DEVICE_FACTORY_RESET', 'w', 1, 0, 'raw'),
    ('000D', 'DEVICE_SETUP', 'r', 1, 1, 'on1'),
    ('000E', 'VIBRATOR_ACTIVATION_STATUS', 'rw', 1, 0, 'on0'),
    ('000F', 'HEATING_ALLOWED', 'r', 1, 1, 'on1'),
    ('0010', 'REMAINING_HEAT_TIME', 'rn', 2, 0, 'minutes'),
    ('0012', 'INTERNAL_TEMPERATURE', 'r', 1, 25 + 40, 'temp'),
    ('0013', 'EXTERNAL_TEMPERATURE', 'rn', 1, 20 + 40, 'temp'),
    ('0014', 'TIME_TO_FULL', 'rn', 2, 0, 'minutes'),
    ('0015', 'ENABLE_EXTERNAL_TEMPERATURE_REGULATION', 'rw', 1, 0, 'on1'),
    ('0016', 'TARGET_EXTERNAL_TEMPERATURE_REGULATION', 'rw', 1, 30 + 40, 'temp'),
    ('0017', 'FUEL_GAUGE_DIE_TEMPERATURE', 'r', 1, 25 + 40, 'temp'),
    ('0018', 'BATTERY_DESIGN_CAPACITY', 'rw', 2, 1400, 'u16'),
    ('0019', 'MINIMAL_INTERNAL_TEMPERATURE', 'r', 1, 20 + 40, 'temp'),
    ('001A', 'PREV_MINIMAL_INTERNAL_TEMPERATURE', 'r', 1, 20 + 40, 'temp'),
]

LOG_FILE = None


def log(msg):
    line = '%s  %s' % (datetime.datetime.now().astimezone().isoformat(timespec='seconds'), msg)
    print(line, flush=True)
    if LOG_FILE:
        LOG_FILE.write(line + '\n')
        LOG_FILE.flush()


def describe(kind, value):
    if kind == 'level':
        return 'level %d' % value if value <= 10 else 'level %d (out of range)' % value
    if kind == 'pct':
        return '%d %%' % value
    if kind == 'minutes':
        return '%d min' % value
    if kind == 'temp':
        return '%d C' % (value - 40)
    if kind == 'charge':
        return CHARGE.get(value, 'unknown %d' % value)
    if kind == 'on1':
        return 'ENABLED' if value & 1 else 'DISABLED'
    if kind == 'on0':
        return {0: 'ENABLED', 1: 'DISABLED'}.get(value, 'unknown %d' % value)
    return str(value)


# Centrals that have read or written a characteristic of the pack. These are the only
# links the emulator ever cuts: the computer's other Bluetooth devices are not its
# business.
PEERS = set()


def peer(options):
    path = str(options.get('device', ''))
    if path:
        PEERS.add(path)
    return 'peer ..' + path[-5:].replace('_', ':') if path else 'peer ?'


def drop_links(bus):
    """Disconnects the centrals that used the pack. Unregistering the services does not
    do that: BlueZ keeps the link, and a watch goes on believing the pack is there."""
    for path in sorted(PEERS):
        tail = path[-5:].replace('_', ':')
        try:
            device = bus.get_object(BLUEZ, path)
            if dbus.Interface(device, DBUS_PROP).Get('org.bluez.Device1', 'Connected'):
                dbus.Interface(device, 'org.bluez.Device1').Disconnect()
                log('LINK   dropped       peer ..%s' % tail)
        except dbus.exceptions.DBusException as error:
            log('WARN   could not drop the link to ..%s: %s' % (tail, error.get_dbus_name()))


def dbus_bytes(data):
    return dbus.Array([dbus.Byte(b) for b in data], signature='y')


class InvalidArgs(dbus.exceptions.DBusException):
    _dbus_error_name = 'org.freedesktop.DBus.Error.InvalidArgs'


class NotPermitted(dbus.exceptions.DBusException):
    _dbus_error_name = 'org.bluez.Error.NotPermitted'


class Application(dbus.service.Object):
    def __init__(self, bus):
        self.path = APP_PATH
        self.services = []
        super().__init__(bus, self.path)

    @dbus.service.method(DBUS_OM, out_signature='a{oa{sa{sv}}}')
    def GetManagedObjects(self):
        objects = {}
        for service in self.services:
            objects[service.get_path()] = service.get_properties()
            for chrc in service.characteristics:
                objects[chrc.get_path()] = chrc.get_properties()
        return objects


class Service(dbus.service.Object):
    def __init__(self, bus, index, uuid):
        self.path = '%s/service%d' % (APP_PATH, index)
        self.uuid = uuid
        self.characteristics = []
        super().__init__(bus, self.path)

    def get_path(self):
        return dbus.ObjectPath(self.path)

    def get_properties(self):
        return {GATT_SVC: {
            'UUID': self.uuid,
            'Primary': dbus.Boolean(True),
            'Characteristics': dbus.Array([c.get_path() for c in self.characteristics], signature='o'),
        }}

    @dbus.service.method(DBUS_PROP, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        if interface != GATT_SVC:
            raise InvalidArgs()
        return self.get_properties()[GATT_SVC]


class Characteristic(dbus.service.Object):
    """One GATT characteristic. `owner` supplies read()/write() for the value."""

    def __init__(self, bus, service, uuid, flags, label, owner):
        self.path = '%s/char%02d' % (service.path, len(service.characteristics))
        self.service = service
        self.uuid = uuid
        self.flags = flags
        self.label = label
        self.owner = owner
        self.notifying = False
        super().__init__(bus, self.path)
        service.characteristics.append(self)

    def get_path(self):
        return dbus.ObjectPath(self.path)

    def get_properties(self):
        return {GATT_CHRC: {
            'Service': self.service.get_path(),
            'UUID': self.uuid,
            'Flags': dbus.Array(self.flags, signature='s'),
        }}

    @dbus.service.method(DBUS_PROP, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        if interface != GATT_CHRC:
            raise InvalidArgs()
        return self.get_properties()[GATT_CHRC]

    @dbus.service.method(GATT_CHRC, in_signature='a{sv}', out_signature='ay')
    def ReadValue(self, options):
        if 'read' not in self.flags:
            raise NotPermitted()
        data, text = self.owner.read(self.label)
        # A "read long" continues from an offset; answer with the rest of the value,
        # which is empty once the client already has all of it.
        offset = int(options.get('offset', 0))
        if offset:
            data = data[offset:]
            text = 'continuation from offset %d' % offset
        log('READ   %-40s -> %s  (%s)  %s' % (self.label, data.hex(' ') or '<empty>', text, peer(options)))
        return dbus_bytes(data)

    @dbus.service.method(GATT_CHRC, in_signature='aya{sv}')
    def WriteValue(self, value, options):
        data = bytes(int(b) for b in value)
        # Log the write before applying it, so the notifications it causes come after it.
        value_to_apply, text = self.owner.check_write(self.label, data)
        log('WRITE  %-40s <- %s  (%s)  %s' % (self.label, data.hex(' ') or '<empty>', text, peer(options)))
        if value_to_apply is not None:
            self.owner.set(self.label, value_to_apply, source='central')

    @dbus.service.method(GATT_CHRC)
    def StartNotify(self):
        self.notifying = True
        log('SUBSCR %-40s notifications on' % self.label)

    @dbus.service.method(GATT_CHRC)
    def StopNotify(self):
        self.notifying = False
        log('SUBSCR %-40s notifications off' % self.label)

    @dbus.service.signal(DBUS_PROP, signature='sa{sv}as')
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    def notify(self, data, text):
        if not self.notifying:
            return
        self.PropertiesChanged(GATT_CHRC, {'Value': dbus_bytes(data)}, [])
        log('NOTIFY %-40s -> %s  (%s)' % (self.label, data.hex(' '), text))


class Pack:
    """State of the emulated pack and the three GATT services exposing it."""

    def __init__(self, bus, app, family_key):
        self.family, template = FAMILIES[family_key]
        self.fields = {name: {'size': size, 'value': value, 'kind': kind}
                       for _code, name, _acc, size, value, kind in FIELDS}
        self.chars = {}
        self.strings = {'MODEL_NUMBER': self.family.replace('_', '-') + '-EMU',
                        'FIRMWARE_REVISION': '1.0.0', 'SOFTWARE_REVISION': '1.0.0'}

        self.pack_uuid = (template % '0001').lower()
        pack = Service(bus, 0, self.pack_uuid)
        for code, name, access, _size, _value, _kind in FIELDS:
            flags = [f for key, f in (('r', 'read'), ('w', 'write'), ('n', 'notify')) if key in access]
            self.chars[name] = Characteristic(bus, pack, (template % code).lower(), flags, name, self)

        info = Service(bus, 1, SIG_UUID % '180a')
        for code, name in (('2a24', 'MODEL_NUMBER'), ('2a26', 'FIRMWARE_REVISION'), ('2a28', 'SOFTWARE_REVISION')):
            Characteristic(bus, info, SIG_UUID % code, ['read'], name, self)

        ota = Service(bus, 2, OTA_TEMPLATE % '0001')
        Characteristic(bus, ota, OTA_TEMPLATE % '0002', ['write', 'notify'], 'OTA_CONTROL', self)
        Characteristic(bus, ota, OTA_TEMPLATE % '0003', ['write', 'write-without-response'], 'OTA_DATA', self)

        app.services += [pack, info, ota]

    def encode(self, name):
        f = self.fields[name]
        return f['value'].to_bytes(f['size'], 'little'), describe(f['kind'], f['value'])

    def read(self, label):
        if label in self.strings:
            return self.strings[label].encode('ascii'), self.strings[label]
        if label in self.fields:
            return self.encode(label)
        return b'', 'no value'

    def check_write(self, label, data):
        """Return (value to store or None when the write is ignored, text for the log)."""
        if label not in self.fields:
            return None, '%d bytes, ignored' % len(data)
        f = self.fields[label]
        if len(data) != f['size']:
            return None, 'unexpected length %d, expected %d, ignored' % (len(data), f['size'])
        value = int.from_bytes(data, 'little')
        if label == 'HEAT_LEVEL' and value > 10:
            return None, 'level %d out of range 0..10, ignored' % value
        return value, describe(f['kind'], value)

    def set(self, name, value, source='console'):
        """Store a value and send notifications the way a pack would."""
        f = self.fields[name]
        f['value'] = value
        if source != 'central':
            log('SET    %-40s = %s' % (name, describe(f['kind'], value)))
        self.chars[name].notify(*self.encode(name))
        if name in ('HEAT_LEVEL', 'BATTERY_LEVEL'):
            level = self.fields['HEAT_LEVEL']['value']
            battery = self.fields['BATTERY_LEVEL']['value']
            # Made-up model: 10 hours at level 1 on a full battery.
            minutes = 0 if level == 0 else round(600 / level * battery / 100)
            if minutes != self.fields['REMAINING_HEAT_TIME']['value']:
                self.fields['REMAINING_HEAT_TIME']['value'] = minutes
                self.chars['REMAINING_HEAT_TIME'].notify(*self.encode('REMAINING_HEAT_TIME'))

    def show(self):
        for _code, name, _acc, _size, _value, _kind in FIELDS:
            data, text = self.encode(name)
            log('STATE  %-40s %s  (%s)' % (name, data.hex(' '), text))


class Advertisement(dbus.service.Object):
    def __init__(self, bus, service_uuid, name):
        self.path = APP_PATH + '/adv0'
        # Discoverable puts the "LE General Discoverable" flag into the packet. Without it
        # BlueZ sends no Flags field at all unless the whole adapter is discoverable, and
        # scanners that look for discoverable devices may skip the advertisement.
        # The name always goes into the scan response, so passive scanners never see it.
        self.props = {
            'Type': 'peripheral',
            'ServiceUUIDs': dbus.Array([service_uuid], signature='s'),
            'LocalName': dbus.String(name),
            'Discoverable': dbus.Boolean(True),
        }
        super().__init__(bus, self.path)

    @dbus.service.method(DBUS_PROP, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        if interface != ADV_IFACE:
            raise InvalidArgs()
        return self.props

    @dbus.service.method(ADV_IFACE)
    def Release(self):
        log('ADV    released by BlueZ')


def find_adapter(bus):
    manager = dbus.Interface(bus.get_object(BLUEZ, '/'), DBUS_OM)
    for path, ifaces in manager.GetManagedObjects().items():
        if GATT_MGR in ifaces and ADV_MGR in ifaces:
            return path
    return None


def builtin_device_info_disabled():
    try:
        with open('/etc/bluetooth/main.conf', encoding='utf-8') as fh:
            return any(re.match(r'\s*DeviceID\s*=\s*false\s*$', line, re.I) for line in fh)
    except OSError:
        return False


COMMANDS = 'commands: heat N | battery N | charge N | allowed 0|1 | ext T | int T | res N | drop | show | quit'


def console(pack, loop, bus):
    def on_line(source, _condition):
        line = source.readline()
        if not line:
            return False
        parts = line.split()
        if not parts:
            return True
        cmd, arg = parts[0].lower(), parts[1] if len(parts) > 1 else None
        try:
            if cmd in ('quit', 'q', 'exit'):
                loop.quit()
            elif cmd == 'show':
                pack.show()
            elif cmd == 'drop':
                drop_links(bus)
            elif cmd == 'heat' and 0 <= int(arg) <= 10:
                pack.set('HEAT_LEVEL', int(arg))
            elif cmd == 'battery' and 0 <= int(arg) <= 100:
                pack.set('BATTERY_LEVEL', int(arg))
            elif cmd == 'charge' and int(arg) in CHARGE:
                pack.set('BATTERY_CHARGE_STATUS', int(arg))
            elif cmd == 'allowed' and int(arg) in (0, 1):
                pack.set('HEATING_ALLOWED', int(arg))
            elif cmd == 'ext' and -40 <= int(arg) <= 215:
                pack.set('EXTERNAL_TEMPERATURE', int(arg) + 40)
            elif cmd == 'int' and -40 <= int(arg) <= 215:
                pack.set('INTERNAL_TEMPERATURE', int(arg) + 40)
            elif cmd == 'res' and 0 <= int(arg) <= 65535:
                pack.set('HEATER_RESISTANCE', int(arg))
            else:
                print(COMMANDS)
        except (TypeError, ValueError):
            print(COMMANDS)
        return True

    GLib.io_add_watch(sys.stdin, GLib.IO_IN, on_line)


def main():
    global LOG_FILE
    parser = argparse.ArgumentParser(description='Therm-ic battery pack emulator (BLE peripheral).')
    parser.add_argument('--family', choices=sorted(FAMILIES), default='s')
    parser.add_argument('--name', default='SPackEmu',
                        help='advertised name; flags + 128-bit UUID leave room for 8 characters')
    parser.add_argument('--duration', type=int, default=0, help='stop after this many seconds, 0 = until quit')
    parser.add_argument('--log', help='also append the log to this file')
    parser.add_argument('--selftest', action='store_true',
                        help='register with BlueZ, report, unregister and exit')
    args = parser.parse_args()
    if args.log:
        LOG_FILE = open(args.log, 'a', encoding='utf-8')

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    adapter = find_adapter(bus)
    if adapter is None:
        sys.exit('no Bluetooth adapter with GATT server and LE advertising support found')
    adapter_obj = bus.get_object(BLUEZ, adapter)
    if not dbus.Interface(adapter_obj, DBUS_PROP).Get('org.bluez.Adapter1', 'Powered'):
        sys.exit('Bluetooth adapter %s is powered off' % adapter)

    loop = GLib.MainLoop()
    app = Application(bus)
    pack = Pack(bus, app, args.family)
    adv = Advertisement(bus, pack.pack_uuid, args.name)
    gatt_mgr = dbus.Interface(adapter_obj, GATT_MGR)
    adv_mgr = dbus.Interface(adapter_obj, ADV_MGR)
    state = {'gatt': False, 'adv': False, 'failed': False}

    log('START  family %s, service %s, name "%s", adapter %s' % (pack.family, pack.pack_uuid, args.name, adapter))
    if not builtin_device_info_disabled():
        log('WARN   BlueZ built-in Device Information service looks enabled; the Therm-ic app will '
            'reject the device until DeviceID = false is set in /etc/bluetooth/main.conf')

    def fail(what, error):
        state['failed'] = True
        log('ERROR  %s failed: %s' % (what, error))
        loop.quit()

    def adv_ok():
        state['adv'] = True
        active = int(dbus.Interface(adapter_obj, DBUS_PROP).Get(ADV_MGR, 'ActiveInstances'))
        log('ADV    advertising on, active instances: %d' % active)
        if args.selftest:
            log('SELFTEST ok: %d characteristics in %d services registered' % (
                sum(len(s.characteristics) for s in app.services), len(app.services)))
            loop.quit()

    def gatt_ok():
        state['gatt'] = True
        log('GATT   application registered')
        adv_mgr.RegisterAdvertisement(adv.path, {}, reply_handler=adv_ok,
                                      error_handler=lambda e: fail('RegisterAdvertisement', e))

    gatt_mgr.RegisterApplication(app.path, {}, reply_handler=gatt_ok,
                                 error_handler=lambda e: fail('RegisterApplication', e))

    def readvertise():
        # A connectable advertisement stops when a central connects. Register it again
        # after the link drops, so the next scan finds the pack without a restart.
        if not state['adv']:
            return False
        try:
            adv_mgr.UnregisterAdvertisement(adv.path)
        except dbus.exceptions.DBusException:
            pass
        adv_mgr.RegisterAdvertisement(
            adv.path, {},
            reply_handler=lambda: log('ADV    advertising restarted after disconnect'),
            error_handler=lambda e: log('WARN   advertising restart failed: %s' % e))
        return False

    def on_device_change(interface, changed, _invalidated, path=None):
        # Link level events: the GATT callbacks alone do not show when a central
        # connects or goes away.
        if interface != 'org.bluez.Device1' or 'Connected' not in changed:
            return
        tail = str(path)[-5:].replace('_', ':')
        if changed['Connected']:
            log('LINK   connected     peer ..%s' % tail)
        else:
            log('LINK   disconnected  peer ..%s' % tail)
            if not args.selftest:
                GLib.timeout_add(500, readvertise)

    bus.add_signal_receiver(on_device_change, dbus_interface=DBUS_PROP,
                            signal_name='PropertiesChanged', path_keyword='path')

    for sig in (signal.SIGINT, signal.SIGTERM):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: loop.quit() or False)
    if args.duration > 0:
        GLib.timeout_add_seconds(args.duration, lambda: log('STOP   duration reached') or loop.quit() or False)
    if sys.stdin.isatty() and not args.selftest:
        console(pack, loop, bus)

    try:
        loop.run()
    finally:
        # First the links, as a pack that is switched off does: a central then sees
        # the pack go, not a pack whose services vanished.
        drop_links(bus)
        if state['adv']:
            try:
                adv_mgr.UnregisterAdvertisement(adv.path)
            except dbus.exceptions.DBusException as error:
                log('WARN   UnregisterAdvertisement: %s' % error)
        if state['gatt']:
            try:
                gatt_mgr.UnregisterApplication(app.path)
            except dbus.exceptions.DBusException as error:
                log('WARN   UnregisterApplication: %s' % error)
        log('STOP   advertising off, application unregistered')
    sys.exit(1 if state['failed'] else 0)


if __name__ == '__main__':
    main()
