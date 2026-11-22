# Therm-ic battery pack protocol

What is known about how the packs of Therm-ic heated gear talk over Bluetooth LE.

## Where this comes from

- Static analysis of the official Android app, `com.thermic.app` 1.0.3 (version code 49).
- Watching that app talk to `emulator/pack_emulator.py`.
- Running the code in this repository on a fenix 6S Pro against the same emulator.

**Nothing here has been checked against a real pack.** Everything about the pack side
is what the app expects of it. The section "Unknown" lists what only hardware can answer.

## Model

Plain GATT. Every property of a pack is its own characteristic holding one or two
bytes, little-endian. There are no frames, commands or checksums. Changing the heat
level is a one-byte write.

## UUIDs

A UUID is a family template with a 16-bit code in place of `XXXX`. Code `0001` is the
service; every other code is a characteristic of that service.

| Family   | Template                               |
|----------|----------------------------------------|
| S-Pack   | `73cbXXXX-b806-43bd-9612-e3de0a18ccb6` |
| C-Pack   | `dabeXXXX-1e1c-4f9e-931c-1ac4c235254b` |
| B-Pack   | `04f9XXXX-a0e9-4111-b3bd-0221dff2d442` |
| I-Pack   | `c1f2XXXX-b64c-4b4f-9482-cf47b4b5cfa4` |
| BodyPack | `28b3XXXX-98a2-4c6d-9287-2fc3d1f37682` |

The app tells the family from the advertised service UUID. It did not tie a family to a
product type: an S-Pack was accepted for a product that needs a single pack.

## Characteristics

Access is how the app uses the characteristic. "poll" means the app re-reads it on a
timer instead of subscribing.

| Code   | Name                                   | Access           | Bytes | Value |
|--------|----------------------------------------|------------------|-------|-------|
| `0002` | HEAT_LEVEL                             | read write notify | 1    | 0..10, 0 is off |
| `0004` | HEATER_RESISTANCE                      | read notify      | 2     | unit unknown |
| `0005` | BATTERY_LEVEL                          | read notify      | 1     | taken to be percent |
| `0006` | BATTERY_CAPACITY                       | read             | 2     | unit unknown |
| `0007` | BATTERY_CURRENT_CONSUMPTION            | read, poll       | 2     | unit unknown |
| `0008` | BATTERY_CHARGE_STATUS                  | read notify      | 1     | 0 not charging, 1 pre-charge, 2 charging, 3 complete |
| `0009` | LED_ACTIVATION_STATUS                  | read write       | 1     | 0 enabled, 1 disabled |
| `000A` | LED_STATUS                             | read             | 1     | not decoded by the app |
| `000B` | DEVICE_SLEEP                           | write            | 1     | not explored |
| `000C` | DEVICE_FACTORY_RESET                   | write            | 1     | not explored, do not write |
| `000D` | DEVICE_SETUP                           | read             | 1     | bit 0: 1 enabled |
| `000E` | VIBRATOR_ACTIVATION_STATUS             | read write       | 1     | 0 enabled, 1 disabled |
| `000F` | HEATING_ALLOWED                        | read             | 1     | 1 enabled, 0 disabled |
| `0010` | REMAINING_HEAT_TIME                    | read notify      | 2     | minutes |
| `0012` | INTERNAL_TEMPERATURE                   | read, poll       | 1     | value - 40 = degrees Celsius |
| `0013` | EXTERNAL_TEMPERATURE                   | read notify      | 1     | value - 40 = degrees Celsius |
| `0014` | TIME_TO_FULL                           | read notify      | 2     | minutes |
| `0015` | ENABLE_EXTERNAL_TEMPERATURE_REGULATION | read write       | 1     | 1 enabled, 0 disabled |
| `0016` | TARGET_EXTERNAL_TEMPERATURE_REGULATION | read write       | 1     | value - 40 = degrees Celsius |
| `0017` | FUEL_GAUGE_DIE_TEMPERATURE             | read, poll       | 1     | value - 40 = degrees Celsius |
| `0018` | BATTERY_DESIGN_CAPACITY                | read write       | 2     | unit unknown |
| `0019` | MINIMAL_INTERNAL_TEMPERATURE           | read             | 1     | value - 40 = degrees Celsius |
| `001A` | PREV_MINIMAL_INTERNAL_TEMPERATURE      | read             | 1     | value - 40 = degrees Celsius |

There is no code `0011`. Note the two conventions for on/off: the LED and the vibrator
use 0 for enabled, the other switches use 1.

The app refuses a pack that lacks a characteristic it considers required. For an S-Pack
that is everything above except `0019` and `001A`.

## Other services the app expects

- Device Information, `0x180A`, with model number `0x2A24`, firmware revision `0x2A26`
  and software revision `0x2A28`. The app looks the service up, takes the first
  instance and drops the connection if the three characteristics are not in it.
- `27b30001-98a2-4c6d-9287-2fc3d1f37682` with characteristics `27b30002-...` and
  `27b30003-...`. Judging by how the app uses them this is the firmware update channel.
  The app requires them to exist and subscribes to the first one. Leave it alone.

The app also scans for the 16-bit service `0xFEE9` and handles such devices separately
from the five families. They look like an older generation this app does not drive;
that reading is an inference.

## What the phone app does

Observed with the emulator standing in for a pack.

1. Scans with a filter on the service UUID. A device without a name is ignored.
2. Connects and, once services are discovered, asks Android to bond. A device that is
   ready but not bonded is treated as a failure.
3. Subscribes to every notifying characteristic and to the firmware update control
   characteristic, then reads every readable characteristic, twice.
4. Polls `0007`, `0012` and `0017` every 10 seconds.
5. Changes the level with a single one-byte write to `0002`. No write precedes it.
6. After a HEAT_LEVEL notification it writes the notified value back once.

### Modes

The app has five modes for a product. This is read from its code and its texts, not
observed. No characteristic carries a mode. Apart from the target temperature a mode is
something the phone does, and the pack only ever receives a heat level.

- Manual: the level, 0 to 10.
- Eco: heating and pauses in turn, to save the battery. The user sets the level, the
  heating time and the break time in minutes. The app keeps the end of the current
  stretch in its own database.
- Motion: the level follows whether the user is moving. The user picks a kind of
  activity and two levels, "static heating" and "heating in motion". Movement comes
  from the phone: the app subscribes to Google's activity recognition and takes the
  most confident result. Which results count as moving depends on the kind of activity
  picked. Without the phone's permission to track physical activity the mode does not
  start.
- Boost: the highest level for 2, 5 or 10 minutes, then back.
- Target temperature: the app writes `0015` = 1 and `0016` = target + 40. The pack has
  those two characteristics for it, so the regulation is taken to run in the pack. The
  target can be set from 15 to 35 degrees in steps of one, and a new product starts at
  25. The app has a message for gear without a temperature sensor.

While a mode other than manual runs, the app shows a notification that it is running.

External temperature: the app takes a reading as present only from -20 to 214 degrees
Celsius. Outside that range it acts as if the product had no sensor; a raw `FF` gives
215 and falls outside. It shows one temperature for each pack, not a combined one. This
is read from the app's code, not observed.

Socks, soles and gloves are paired products: the app wants two packs and will not finish
pairing with one. Nothing in a pack marks it as left or right; the app assigns that.

## What the watch does

Measured on a fenix 6S Pro, Connect IQ 3.4.5.

- Scanning is passive, so the device name (which BlueZ puts into the scan response) never
  arrives. A pack can only be recognised by the service UUID in the advertisement.
- An advertiser without the "LE General Discoverable" flag is not reported at all. The
  emulator was invisible to the watch until it set that flag.
- One GATT request at a time; a second one before the first completes is rejected.
- At most three registered profiles, so one family is compiled into the apps here.
- Three simultaneous connections are available.
- No bonding: `requestBond` exists from API 4.2.5 only. A refused request reports status
  18 (insufficient authentication) or 19 (insufficient encryption).
- Every read arrives at the peripheral twice.
- About 25 seconds pass between the link coming up and the first read.

## What the apps here use

- `0002` HEAT_LEVEL: read and notifications in both apps. The widget writes it, and only
  after a button press.
- `0005` BATTERY_LEVEL: read and notifications.
- `0013` EXTERNAL_TEMPERATURE: read and notifications. Shown and recorded as the
  temperature at the heated gear, within the range the phone app accepts. A pack that
  lacks the characteristic or refuses the read is used without it.

The widget alone also uses these, and like the temperature each is optional:

- `0010` REMAINING_HEAT_TIME: read and notifications, shown as it comes.
- `0012` INTERNAL_TEMPERATURE: read when a pack connects and again every half a minute,
  as it has no notifications. Shown as the temperature inside the pack.
- `0015` and `0016`: read when a pack connects. The widget writes the target within the
  phone app's 15 to 35 degrees, and writes the switch, each after a button press and
  each on its own.

## Unknown

- **Whether a real pack lets an unbonded central read and write.** The app insists on
  bonding, which suggests the pack may too. If it does, a watch on Connect IQ 3.x cannot
  talk to it directly and needs a phone in between.
- Whether a pack advertises as discoverable outside its pairing mode.
- Whether a pack accepts more than one central at a time.
- Units of the two-byte values.
- Whether a pack keeps regulating to a target temperature on its own, with no phone or
  watch connected.
- What "external temperature" measures, and which products have a sensor for it. It is
  the value a pack regulates by in its target temperature mode, which is why the apps
  here take it for the temperature at the gear.
