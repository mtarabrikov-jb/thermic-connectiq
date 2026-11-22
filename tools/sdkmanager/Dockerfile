# Runtime for Garmin's official Connect IQ SDK Manager on distributions that no longer
# ship WebKitGTK 4.0 (Ubuntu 24.04, Linux Mint 22).
#
# The sdkmanager binary links to libwebkit2gtk-4.0.so.37 and libsoup-2.4.so.1 directly.
# Ubuntu 22.04 still has the genuine WebKitGTK 4.0 built against libsoup2. Pointing the
# 4.0 name at the 4.1 library on the host does not work: 4.1 pulls in libsoup3 and the
# process aborts with "libsoup2 symbols detected".
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# x11-utils is only for troubleshooting display access:
#   docker compose run --rm sdkmanager xdpyinfo
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libwebkit2gtk-4.0-37 libgtk-3-0 libcurl4 libsecret-1-0 libexpat1 \
      libxxf86vm1 libsm6 libxext6 libx11-6 libxkbcommon0 libjpeg-turbo8 libpng16-16 \
      libusb-1.0-0 ca-certificates fonts-dejavu-core dbus-x11 x11-utils \
 && rm -rf /var/lib/apt/lists/*
