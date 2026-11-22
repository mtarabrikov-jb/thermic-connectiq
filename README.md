# Connect IQ apps for Therm-ic heated gear

Control Therm-ic heated socks and other heated gear from a Garmin watch, without taking
the phone out.

Unofficial. Not affiliated with or endorsed by Therm-ic or Garmin.

## Status

Experimental, and **not yet tried on real hardware**.

- The widget works end to end against the pack emulator in this repository, on a
  fenix 6S Pro (Connect IQ 3.4.5): find the pack, connect, read level and battery,
  follow notifications, set the level, reconnect.
- The official phone app works against the same emulator, which is how the protocol
  was confirmed.
- Open question: the phone app bonds with the pack, and watches on Connect IQ 3.x cannot
  bond. If a real pack refuses an unbonded connection, the widget will show
  `needs bonding` and direct control from such a watch is not possible. See
  [docs/protocol.md](docs/protocol.md).
- Two packs at once (left and right) are implemented but untested.

## What is here

| Path        | What |
|-------------|------|
| `widget/`   | The widget: level and battery on the main page, level control on a second page. |
| `common/`   | Code shared by the apps: protocol constants, state model, Bluetooth and demo transports. |
| `probe/`    | Diagnostic widget that shows every step of scan, connect, read and write. |
| `emulator/` | A Bluetooth LE peripheral that imitates a pack, for Linux with BlueZ. |
| `tools/`    | Headless simulator, SDK Manager container, icon helper. |
| `docs/`     | Protocol notes. |

A data field for recording during an activity is planned next to `widget/`.

## Using the widget

Main page: the level as a number and a ring, battery of each pack underneath.

- START opens the control page.
- UP and DOWN are left to the watch, so the widget loop keeps scrolling.

Control page:

- UP and DOWN change the level, 0 to 10. Several quick presses become one write.
- START switches the heat off, or back to the last level that was on.
- BACK returns to the main page.

The widget never writes to a pack on its own. A level changed with the button on the
pack shows up on the watch, and the control page continues from that value.

## Building

Needs the Connect IQ SDK with the device files for your watch, and a developer key.

```bash
# once: a signing key
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt

SDK="$(tr -d '\n' < ~/.Garmin/ConnectIQ/current-sdk.cfg)"
"$SDK/bin/monkeyc" -d fenix6spro -f widget/monkey.jungle -o widget/bin/THERMIC.prg -y developer_key.der -w
```

Keep the key out of the repository. `.gitignore` covers `*.der` and `*.pem`.

Supported devices are listed in `widget/manifest.xml`. To add one, add its product id
there and download its device files with the SDK Manager. The pack family is a constant
in `common/source/Protocol.mc`; the watch registers at most three Bluetooth profiles, so
one family is compiled in.

### SDK Manager on a current Linux

Garmin's SDK Manager and simulator link to WebKitGTK 4.0, which Ubuntu 24.04 and its
derivatives no longer ship. Pointing the 4.0 library name at 4.1 does not work.
`tools/sdkmanager/` runs the official binary in an Ubuntu 22.04 container instead:

```bash
tools/sdkmanager/run.sh /path/to/unpacked/connectiq-sdk-manager-linux
```

The compiler itself is Java and runs on the host.

## Installing on the watch

Connect the watch by USB and copy the `.prg` into `GARMIN/Apps`. Music models show up as
an MTP device, the others as a drive. To get the app's log, create an empty
`GARMIN/Apps/LOGS/THERMIC.TXT` first; the name must match the `.prg`.

## Trying it without hardware

### Pack emulator

`emulator/pack_emulator.py` registers the pack's services with BlueZ and advertises
them. It logs every read, write and subscription and has a small console to play the
pack's side, for example a press of its button.

```bash
python3 emulator/pack_emulator.py --log session.log
# then, in its console:
#   heat 7        the pack changes level by itself
#   battery 50
#   show
```

Requirements: BlueZ with a controller that supports the peripheral role, `python3-dbus`
and `python3-gi`.

BlueZ publishes a Device Information service of its own, without the characteristics
the official app looks for, and it comes first. To test with the official app, set
`DeviceID = false` in the `[General]` section of `/etc/bluetooth/main.conf` and restart
the bluetooth service. The widget does not need this.

The official app will bond with the computer running the emulator, and it wants two
packs for socks; choose a product that uses a single pack. Turn the phone's Bluetooth
off while testing the watch, or the app reconnects and gets in the way.

### Demo build and headless simulator

The demo build replaces Bluetooth with two made-up packs:

```bash
"$SDK/bin/monkeyc" -d fenix6spro -f widget/monkey-demo.jungle -o widget/bin/THERMICD.prg -y developer_key.der -w
```

`tools/simulator/` runs Garmin's simulator on a virtual display, sends key presses and
saves screenshots, so screens can be checked without a watch:

```bash
docker build -t ciq-sdkmanager:jammy tools/sdkmanager     # base image
docker build -t ciq-sim:jammy tools/simulator
tools/simulator/run.sh widget/bin/THERMICD.prg fenix6spro /tmp/shots \
    wait:4 shot:a-main key:Return wait:1 shot:b-control key:Up wait:2 shot:c-up
```

The simulator has no Bluetooth; use it with the demo build.

## Branding

The repository ships a neutral launcher icon. `widget/monkey.jungle` lists a second,
optional resource directory, `private/widget/resources`, which is ignored by git.
Resources placed there override the shipped ones with the same id, so a private build
can carry its own icon. `tools/make_icon.py` produces one from a logo you supply.

Therm-ic and its logo are trademarks of their owner. Do not publish builds that use them
without permission.

## How the protocol was worked out

By reading the official Android app and by letting it talk to the emulator. No code from
that app is included here; see [docs/protocol.md](docs/protocol.md) for what was
learned and how sure each part is.
