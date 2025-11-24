#!/usr/bin/env bash
set -e

# Find Type-C ports and USB devices. Allow user to select device for passthrough
# Returns a device path or exits non-zero if nothing found

function list_typec_ports() {
  if [[ -d /sys/class/typec ]]; then
    for p in /sys/class/typec/port-*; do
      portname=$(basename $p)
      # typec/port-* includes both connectors; read partner to find active devices
      echo "$portname   - /sys/class/typec/$portname"
    done
  else
    return 1
  fi
}

function list_lsusb() {
  if command -v lsusb >/dev/null 2>&1; then
    lsusb
  else
    echo "lsusb not available; install usbutils"
    return 1
  fi
}

echo "Searching for Type-C ports via /sys/class/typec..."
if list_typec_ports >/dev/null 2>&1; then
  echo "TypeC ports found:"
  list_typec_ports || true
else
  echo "No Type-C entries found in /sys/class/typec. Falling back to lsusb device listing."
  list_lsusb || true
fi

echo
echo "To passthrough a USB bus into Docker, identify the USB bus and device numbers via lsusb, eg:"
echo "  Bus 002 Device 003: ID 1234:5678 Some Device"
echo "Then run: docker run --rm -it --device=/dev/bus/usb/002/003 <image>"

echo
read -p "If you want, enter a Bus and Device to pass (format 002/003), or press Enter to exit: " bd
if [[ -z "$bd" ]]; then
  echo "No device selected. Exiting."
  exit 0
fi
devicepath="/dev/bus/usb/$bd"
if [[ -e "$devicepath" ]]; then
  echo "You selected: $devicepath"
  echo "Sample docker run: docker run --rm -it --device=$devicepath $IMAGE"
  echo $devicepath
else
  echo "$devicepath not found. Ensure the correct bus/device numbers were specified and that you have permission to access /dev/bus/usb." >&2
  exit 2
fi
