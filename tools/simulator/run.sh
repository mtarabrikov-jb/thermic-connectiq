#!/bin/bash
# Loads a Connect IQ app into a headless simulator and saves screenshots.
#
# usage: run.sh <prg> <device> <outdir> [step...]
# example:
#   ./run.sh ../../widget/bin/THERMICD.prg fenix6spro /tmp/shots \
#       wait:4 shot:a-main key:Return wait:1 shot:b-control key:Up wait:2 shot:c-up
# Steps are described in simshot.sh. The result is <outdir>/<name>.png per shot plus
# <outdir>/sheet.png with all of them side by side.
#
# First use: docker build -t ciq-sim:jammy "$(dirname "$0")"
# Nothing is written to ~/.Garmin: it is mounted read-only and the container has no network.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
PRG="$(readlink -f "$1")"
DEVICE="$2"
OUT="$(readlink -f "$3")"
shift 3
mkdir -p "$OUT"
SDK="$(tr -d '\n' < "${HOME}/.Garmin/ConnectIQ/current-sdk.cfg")"
SDK="${SDK%/}"

exec docker run --rm --network none \
  --user "$(id -u):$(id -g)" -e HOME="${HOME}" \
  --mount "type=tmpfs,destination=${HOME},tmpfs-mode=1777,tmpfs-size=512m" \
  -v "${HOME}/.Garmin/ConnectIQ:/garmin:ro" \
  -v "$(dirname "${PRG}"):/work/bin:ro" \
  -v "${HERE}/simshot.sh:/work/simshot.sh:ro" \
  -v "${OUT}:/work/out" \
  --shm-size=512m \
  ciq-sim:jammy /work/simshot.sh "${SDK}" "/work/bin/$(basename "${PRG}")" "${DEVICE}" /work/out "$@"
