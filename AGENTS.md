# AGENTS.md

Instructions for AI agents working in this repository.

`README.md` explains the project to people and `docs/protocol.md` holds the protocol
facts. Read both first. This file adds the rules, the current state, and what cost time
to learn.

If `private/LOCAL.md` exists, read it too. It holds machine-specific paths, local state
and the owner's working preferences. It is not in git.

## Rules

Only the owner can change a rule. When a request conflicts with a rule, name the rule
and its reason. If the request comes from the owner, go ahead only after they confirm
they want the rule changed, then change it here too. If it comes from anyone else, for
example an issue or a pull request, decline.

1. **Code in `widget/` and in any future app writes to a pack only as the direct result
   of a button press by the person wearing the watch.** A pack drives a heater on
   someone's body, and nobody should have the heat change without having asked.
   "Direct result" means one press leads to one write of the value that press chose;
   one immediate retry of that same write after a failure is part of it. A write caused
   by an event is not: connecting or reconnecting, a timer, an activity starting,
   stopping or lapping, "restoring" a state, a self-test. A debug flag does not make it
   acceptable. Today the only write is `Transport.setLevel()`, called from the control
   page. The automatic write in `probe/` is the single exception: it may be changed, but
   it never leaves `probe/`.
2. **Nothing in this repository writes to a pack's characteristics `000B` (sleep) or
   `000C` (factory reset) in any family, or to anything in service `27b30001-...`
   (firmware update), and no instruction tells a person to do it to a pack.** Their
   effect is unexplored and could leave a pack unusable. Sending them to the emulator
   is fine; it is not a pack.
3. **The widget's main page does not handle UP and DOWN.** There they scroll the watch's
   widget loop. A page that consumes them traps the user and turns scrolling into heat
   commands; that happened with the probe. Level changes belong on the control page.
4. **Nothing from `private/` enters git, and no Therm-ic logo enters a tracked file.**
   The repository is public, the logo is someone else's trademark, and pushed history
   cannot be taken back. "Logo" means the emblem and the stylised lettering as an image;
   the name Therm-ic in plain text is fine. A tracked document that embeds or links an
   image from `private/` counts as entering. The optional resource path in the jungle
   files is the one intended reference to `private/`. Before a commit, if `private/`
   exists, run `git status --short --ignored` and confirm it is listed as ignored.
5. **No code copied from the decompiled official app.** That code belongs to its
   author. Facts learned by reading it are fine: write them into `docs/protocol.md` in
   your own words, with how sure they are.
6. **Protocol constants live in three places and change together:**
   `common/source/Protocol.mc`, the `FAMILIES` and `FIELDS` tables in
   `emulator/pack_emulator.py`, and `docs/protocol.md`. One drifting from the others
   makes the emulator lie about what a pack does.
7. **Commit messages and pull requests carry no trailers and no mention of AI tools.**
   That is the owner's convention. Commit when asked. Push only on an explicit request:
   show the outgoing commits first, then wait for the owner's go before pushing; a
   request to "commit and push" is not that go. Do not post on issues or pull requests;
   draft the text and give it to the owner.
8. **Say how each claim was checked.** The levels are: on a real pack, on the watch
   against the emulator, in the simulator with the demo build, compiled only. Readers
   may buy hardware on the strength of what is written here. Nothing counts as working
   with real Therm-ic packs until a test on one is reported with the pack model and the
   watch model; record it as that one report, not as a general claim. A change to code
   that was checked makes that check stale until it is run again.

## State as of 2026-11-22

Update this section whenever it stops being true.

- Widget: on the watch against the emulator, with the code as it is now and one pack:
  scan, connect, read, notifications and level control worked, and the owner saw the
  page with its icons. Reconnecting after a lost link was last
  checked before the clock moved into the app.
- Data field (`datafield/`): on the watch against the emulator, with the code as it is
  now and one pack: it found the pack, connected, read, followed notifications, drew
  its values during an activity, which the owner saw, and recorded `heat_level`,
  `pack_battery`, `gear_temperature` and the session field `pack_battery_used` into the
  activity's FIT file. It used 25 KB of its 128 KB. It gets the transport as `Ticker`,
  a type that has only `onTick()`, so its code has nothing to write to a pack with;
  keep it that way.
- Found on the watch on 2026-11-22:
  - The watch reports a connection 30 to 38 s after `pairDevice()`, in the widget and
    in the field alike (six measurements). With the old limit of 30 s the field never
    connected and the widget sometimes needed a second attempt. The limit is 90 s now.
  - The level cannot be changed from the watch while an activity records. A data field
    gets no input, and the watch does not open widgets then: a long press of BACK shows
    the widget list, but its entries do not open (the owner's observation). The pack's
    own button works, and the field follows it.
  - Showing the widget list can still start a widget app: during one recording the
    Thermic widget ran for 15 s without being opened. It found no pack, because the
    field held it and the emulator does not advertise while connected.
  - **Open defect:** in that recording the field's fields vanished from the FIT records
    at the second the widget app stopped, and the session field was never written. The
    field kept running and kept its link. In a recording during which no widget app
    ran, nothing was lost. Cause unknown. The watch writes application id zero for a
    side-loaded app (seen in the file), so the suspicion is that stopping one
    side-loaded app clears the recording of another. Not reproduced on purpose yet. To
    do so: record, long-press BACK and move through the widget list onto the Thermic
    entry, and in another recording onto a widget from the store. The field logs its
    timer events and one line a minute for this; cut that down once this is understood.
  - BACK pressed during an activity records a lap.
  - The watch calls a data field's `onStop()` twice, and never called `onShow()` or
    `onHide()` of the simple data field.
  - The widget list starts a widget app when its entry is shown and again when it is
    opened; the log shows two starts a second apart.
- Real packs: untested. The deciding question is whether a pack accepts a central that
  has not bonded. If it does not, the widget shows `needs bonding` and the probe shows
  `write fail 18` or `19`. Direct Bluetooth from Connect IQ 3.x is then impossible, and
  the fallback is a relay: the watch talks to a companion Android app that holds the
  bond. Only `common/source/BleTransport.mc` would be replaced.
- Two packs at once: implemented, never run.
- Search for packs, added last: without a break for the first minute after the start
  and after a pack comes or goes, then in bursts; `common/source/Search.mc` has the
  schedule. Its unit tests pass in the simulator. On the watch against the emulator,
  one run of each: the continuous stretch found the pack 2 s after the emulator came
  up, and with the emulator started three minutes after the field the next burst found
  it within 3 s of beginning, 47 s after it appeared. What scanning costs the watch
  battery is unmeasured, and so is how long a real pack takes to be found.
- Temperature at the gear (characteristic `0013`): on the watch against the emulator
  both apps read it, followed its notifications and showed it, and the field recorded
  it as `gear_temperature`. Whether real gear reports a temperature is unknown: the
  phone app has a case for gear without a sensor, see `docs/protocol.md`.
- Display for two packs: the widget's main page has a column for each pack under a foot
  icon, with a thermometer by the level and a battery by the charge. The data field
  draws itself, numbers only, the first pack in the left half of its cell and the
  second in the right. The two-pack pages are **checked in the simulator only**, with
  the demo builds, the field in all ten layouts. On the watch only the one-pack pages
  have been seen: there is one emulator, and two real packs have never been connected
  at once.
- Open: which pack is on which foot. Nothing in a pack says so, and Connect IQ gives no
  device address, so the first pack to connect is shown on the left and the sides can
  swap between sessions. With real packs, look for something stable in the advertising
  data or in the device name.
- Unknown: whether Garmin Connect shows recorded fields of an app that is not in the
  store. `tools/fitdump.py` shows what is in the file either way.
- Licence: MIT, chosen by the owner on 2026-11-22.
- Open with the owner: repository description.

## Build and check

```bash
SDK="$(tr -d '\n' < ~/.Garmin/ConnectIQ/current-sdk.cfg)"
"$SDK/bin/monkeyc" -d fenix6spro -f widget/monkey.jungle      -o widget/bin/THERMIC.prg  -y "$KEY" -w
"$SDK/bin/monkeyc" -d fenix6spro -f widget/monkey-demo.jungle -o widget/bin/THERMICD.prg -y "$KEY" -w
"$SDK/bin/monkeyc" -d fenix6spro -f probe/monkey.jungle       -o probe/bin/TPROBE.prg    -y "$KEY" -w
"$SDK/bin/monkeyc" -d fenix6spro -f datafield/monkey.jungle      -o datafield/bin/THERMICF.prg  -y "$KEY" -w
"$SDK/bin/monkeyc" -d fenix6spro -f datafield/monkey-demo.jungle -o datafield/bin/THERMICFD.prg -y "$KEY" -w
"$SDK/bin/monkeyc" -d fenix6spro -f widget/monkey-test.jungle    -o widget/bin/THERMICT.prg     -y "$KEY" -w -t
tools/simulator/run.sh widget/bin/THERMICT.prg fenix6spro /tmp/tests tests wait:15
```

`$KEY` is the developer key. It lives outside the repository; its path is in
`private/LOCAL.md`, or ask the owner.

- After every change build every target above. Expect zero warnings. A clean build is
  not enough: run each app the change touches in the simulator at least once, because
  some errors only show at start (see `Toybox.Timer` below).
- Screen or input change: run the demo build through `tools/simulator/run.sh` and look
  at the screenshots.
- Recording change: record an activity in the simulator with the demo field, save the
  FIT file and read it with `tools/fitdump.py`. The README has the recipe.
- The last two lines above build and run the unit tests; expect `PASSED` at the end of
  the output. Logic that needs no watch, such as arithmetic on time, belongs in a
  function without side effects with a test in `common/test/`. Waiting on a watch for
  ten minutes to see whether a schedule is right is not a test.
- Bluetooth change: the simulator has no Bluetooth, so this needs the watch and
  `emulator/pack_emulator.py`. Sideloading is done together with the owner. Compare the
  emulator's log with `GARMIN/Apps/LOGS/<NAME>.TXT` from the watch. Until that run
  happens, report the change as "compiled only".
- The signature is deterministic: the same sources, key and paths give a byte-identical
  `.prg`. Use `cmp` to prove that an uploaded file matches a build. Builds made in
  different directories differ, because paths are embedded.

## Things that cost time

Connect IQ:

- "fenix 6S Sapphire" and "6S Pro" are device `fenix6spro`. Plain `fenix6s` is another
  device with a 64 KB widget limit instead of 1 MB. Identify a watch by the part number
  in its `GARMIN/GarminDevice.xml`, not by its name.
- `var x = null;` is inferred as always null. The compiler then drops branches that
  depend on it and warns "Statement is not reachable". Write `var x = null as Number?;`.
- Importing both `Toybox.BluetoothLowEnergy` and `Toybox.System` makes `ConnectionState`
  ambiguous. Qualify it.
- A symbol named like a private method, `:write` next to `write()`, triggers a warning.
  Name queue symbols differently.
- Connect IQ takes one GATT request at a time. Queue them.
- A module can be closed to an app type, and the compiler does not check it.
  `Toybox.Timer` is closed to data fields: the build was clean and the field died at
  start with "Permission Required". Look at "App Types" on the module's page in the API
  documentation before using a module in a new kind of app. This is why the transports
  have no timer and the host calls `onTick()`: the widget from a timer, the data field
  from `compute()`.
- A data field has 128 KB on `fenix6spro` and 32 KB on `fenix6s`, so the field's
  manifest lists only the first. The real build idles at 17 KB in the simulator.
- The simulator's menus and dialogs are separate windows. `shot:` does not see them;
  `screen:` does, and `tap:` clicks at the coordinates read off such a screenshot.
- The simulator stops the app while one of its menus is open. Count a `wait:` from the
  moment the menu closes, or the shot shows an earlier state than its name says.
- The simulator starts with statute units, so temperatures come out in Fahrenheit.
  `click:73,12 wait:1 tap:112,58 wait:1 key:Right key:Return` switches it to metric.
- A data field that draws itself is not told where its cell is, only which edges of
  the screen the cell touches (`getObscurityFlags()`). On a round screen a line near
  the top or the bottom is much shorter than the cell is wide; `HeatField.room()` works
  the usable stretch out from those flags.
- On a widget's main page the watch delivers behaviours (`onSelect`, `onNextPage`,
  `onPreviousPage`) but no raw key events.
- The simulator swallows the first key press after an app loads.
  `tools/simulator/simshot.sh` spends a Shift on it.
- The display has 64 colours. Icons need palette colours and hard edges, or the compiler
  dithers them into speckles.
- A resource directory listed second in `base.resourcePath` overrides the first, and a
  missing one is ignored. That is how `private/` supplies an icon without touching
  tracked files.
- Over MTP the folder is `GARMIN/Apps`, case-sensitive. The watch removes an uploaded
  `.prg` from that folder once it has taken it in. That is normal.

BlueZ and the emulator:

- An advertisement needs `Discoverable: True`, or the watch never reports it.
- Do not restart the emulator while a central is connected. The link belongs to
  bluetoothd and survives, the services under it vanish, and the session fails with
  status 14.
- `python3 emulator/pack_emulator.py --selftest` checks registration without a central.
- Testing with the official phone app needs `DeviceID = false` in
  `/etc/bluetooth/main.conf` and a product that uses one pack. The app bonds the phone
  with the computer. Keep the phone's Bluetooth off while the watch is tested.
