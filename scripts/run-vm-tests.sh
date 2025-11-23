#!/usr/bin/env bash
set -euo pipefail

# This is an *example* script showing how to run a test VM using QEMU and
# pass a USB device through for hardware tests. This is intentionally
# conservative and is meant to be adapted to your environment.

IMG=${1:-debian-trixie.qcow2}
MEM=${2:-2048}
CPU=${3:-2}
BUSDEV=${USB_BUSDEV:-}

if [[ -z "$BUSDEV" ]]; then
  echo "Please set USB_BUSDEV to the 'bus/device' value found via lsusb (eg 002/003)"
  echo "e.g. USB_BUSDEV=002/003 ./scripts/run-vm-tests.sh"
  exit 1
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "qemu-system-x86_64 not found; please install qemu-system-x86" >&2
  exit 2
fi

# This example expects $IMG to be a qcow2 image containing an SSH server and an account
# to login. For testing, the user may create an image with cloud-init or install Debian
# and enable SSH.

BUS=$(echo $BUSDEV | cut -d'/' -f1)
DEV=$(echo $BUSDEV | cut -d'/' -f2)
DEV_PATH=/dev/bus/usb/$BUS/$DEV

if [[ ! -e "$DEV_PATH" ]]; then
  echo "Device $DEV_PATH not found. Ensure the device is plugged and correct numbers provided." >&2
  exit 3
fi

echo "Starting QEMU with Passthrough of $DEV_PATH (requires root)."
echo "You can stop the VM with CTRL-C and test commands by SSH'ing into the VM."

sudo qemu-system-x86_64 -m $MEM -smp $CPU -drive file=$IMG,if=virtio -usb -device usb-host,hostbus=$BUS,hostaddr=$DEV -net user,hostfwd=tcp::2222-:22 -net nic

echo "VM exited."
