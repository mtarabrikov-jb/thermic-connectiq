#!/bin/bash
# Starts Garmin's Connect IQ SDK Manager in a container.
#
# usage: run.sh <directory with the unpacked connectiq-sdk-manager-linux.zip> [command...]
#
# Download the archive from https://developer.garmin.com/connect-iq/sdk/ yourself:
# the download is tied to accepting Garmin's licence.
# An optional command replaces the SDK Manager, for example `xdpyinfo` to check that
# the container can reach the display.
set -eu
[ $# -ge 1 ] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
SDKMANAGER_DIR="$(readlink -f "$1")"
shift
[ -x "${SDKMANAGER_DIR}/bin/sdkmanager" ] || { echo "no bin/sdkmanager in ${SDKMANAGER_DIR}" >&2; exit 1; }
export SDKMANAGER_DIR
# Shells do not export these, and compose only sees the environment.
HOST_UID="$(id -u)"; HOST_GID="$(id -g)"; HOST_NAME="$(hostname)"
export HOST_UID HOST_GID HOST_NAME
mkdir -p "${HOME}/.Garmin"
exec docker compose -f "${HERE}/docker-compose.yml" run --rm sdkmanager "$@"
