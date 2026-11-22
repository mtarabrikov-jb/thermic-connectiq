#!/bin/bash
# Runs inside the ciq-sim container: starts the Connect IQ simulator on a virtual display,
# loads one app, plays a list of steps and saves screenshots.
#
# usage: simshot.sh <sdk> <prg> <device> <outdir> [step...]
# steps:
#   key:<name>     xdotool key name; Return = START, Escape = BACK, Up / Down, m = MENU
#   wait:<seconds>
#   shot:<name>    screenshot of the simulator window to <outdir>/<name>.png
#   screen:<name>  screenshot of the whole virtual display; unlike shot: it shows open menus
#   click:<x>,<y>  mouse click, window coordinates
#   tap:<x>,<y>    mouse click, display coordinates as read off a screen: shot; for dialogs
#   type:<text>    types the text into whatever has the focus
# "tests" as the very first step runs the unit tests of a build made with
# monkeyc --unit-test; their results come out with the app console at the end.
#
# Expects the host's ~/.Garmin/ConnectIQ mounted read-only at /garmin.
SDK=$1; PRG=$2; DEV=$3; OUT=$4; shift 4
TESTS=""
if [ "${1:-}" = "tests" ]; then TESTS="-t"; shift; fi

# Writable ~/.Garmin for the simulator's own settings, with the SDK, device files and
# fonts linked in from the read-only mount. Without a writable config directory the
# simulator keeps showing "can't open user configuration file".
mkdir -p "$HOME/.Garmin/ConnectIQ"
for d in Sdks Devices Fonts; do ln -s "/garmin/$d" "$HOME/.Garmin/ConnectIQ/$d"; done
cp /garmin/current-sdk.cfg "$HOME/.Garmin/ConnectIQ/" 2>/dev/null

export DISPLAY=:99
Xvfb :99 -screen 0 700x760x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
for i in $(seq 1 50); do xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done
openbox >/tmp/openbox.log 2>&1 &

"$SDK/bin/simulator" >/tmp/sim.log 2>&1 &
SIMPID=$!
for i in $(seq 1 120); do
  [ -n "$(xdotool search --onlyvisible --name 'CIQ Simulator' 2>/dev/null | head -1)" ] && break
  sleep 0.25
done
sleep 2
kill -0 $SIMPID 2>/dev/null || { echo "simulator exited"; tail -15 /tmp/sim.log; exit 1; }
[ -n "$(xdotool search --onlyvisible --name 'Simulator Error' 2>/dev/null | head -1)" ] && echo "simulator error dialog is present"

WIN=$(xdotool search --onlyvisible --name 'CIQ Simulator' 2>/dev/null | head -1)
xdotool windowmove "$WIN" 0 0 2>/dev/null
xdotool windowactivate "$WIN" 2>/dev/null
xdotool windowfocus "$WIN" 2>/dev/null
sleep 1

timeout 170 "$SDK/bin/monkeydo" "$PRG" "$DEV" $TESTS >/tmp/monkeydo.log 2>&1 &
# The window title gains the device name once the app is loaded.
for i in $(seq 1 120); do
  case "$(xdotool getwindowname "$WIN" 2>/dev/null)" in *" - "*) break ;; esac
  sleep 0.25
done
echo "window: $(xdotool getwindowname "$WIN" 2>/dev/null)"
# The simulator swallows the first key press after a load. Spend a harmless one on it.
sleep 1
xdotool key shift
sleep 0.5

for s in "$@"; do
  case "$s" in
    key:*)   xdotool key "${s#key:}"; sleep 0.5 ;;
    wait:*)  sleep "${s#wait:}" ;;
    click:*) c="${s#click:}"; xdotool mousemove --window "$WIN" "${c%,*}" "${c#*,}" click 1; sleep 0.5 ;;
    tap:*)   c="${s#tap:}"; xdotool mousemove "${c%,*}" "${c#*,}" click 1; sleep 0.5 ;;
    type:*)  xdotool type --delay 40 "${s#type:}"; sleep 0.5 ;;
    shot:*)  import -window "$WIN" "$OUT/${s#shot:}.png" 2>/tmp/import.log && echo "shot ${s#shot:}" || cat /tmp/import.log ;;
    screen:*) import -window root "$OUT/${s#screen:}.png" 2>/tmp/import.log && echo "screen ${s#screen:}" || cat /tmp/import.log ;;
  esac
done

# One contact sheet with every shot cropped to the watch screen (240 px round devices).
if ls "$OUT"/*.png >/dev/null 2>&1; then
  rm -f "$OUT/sheet.png"
  montage "$OUT"/*.png -crop 300x300+27+112 +repage -tile 5x -geometry +6+6 -background '#202020' \
    "$OUT/sheet.png" 2>/tmp/montage.log || cat /tmp/montage.log
fi
echo "--- app console:"
grep -v -e '^$' /tmp/monkeydo.log
