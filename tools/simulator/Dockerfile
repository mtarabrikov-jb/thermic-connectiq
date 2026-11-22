# Headless Connect IQ simulator.
#
# The simulator binary needs the same old WebKitGTK 4.0 as the SDK Manager, so it runs
# on top of that image (see ../sdkmanager). Added here: a virtual display, a window
# manager for keyboard focus, tools to send key presses and take screenshots, and the
# Java runtime that monkeydo uses to push an app into the simulator.
FROM ciq-sdkmanager:jammy

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      xvfb xauth openbox xdotool imagemagick libudev1 libgl1 libgl1-mesa-dri procps \
      openjdk-17-jre-headless \
 && rm -rf /var/lib/apt/lists/*
