# Manual USB-C Port Selection Guide

When automatic detection fails, you can manually select and configure your USB-C port. This guide walks you through the process.

## Overview

The `target_usb_c_port.env` file identifies which USB-C port to use for networking. If the automatic detection script fails (e.g., due to missing sysfs support), you can create this file manually.

## Important: Gadget Mode is ONLY for Detection

⚠️ **Key Clarification:**

- **Detection methods** (especially libusb enumeration) may require connecting a USB gadget-mode device (like a smartphone)
- **Actual USB-C networking** in this project does NOT require gadget mode
- The detection phase is separate from the networking phase
- Once you've identified the port using this guide, gadget-mode devices are no longer needed

This is purely a detection/identification step. The networking layer uses direct USB communication between hosts.

## What Information You Need

To manually select a port, you need to identify:

1. **USB Bus and Device Numbers** – The `/dev/bus/usb/` path
2. **Port Name** – The physical port identifier (if available via sysfs)
3. **Port Speed** – USB 2.0, 3.0, 3.1, etc.
4. **Vendor and Product IDs** – The USB device identifiers

## Step-by-Step Manual Selection

## Detection Methods and Their Requirements

The script uses two detection methods with different device type requirements:

### Method 1: Type-C sysfs Detection
- **Best for:** Systems with `/sys/class/typec/` support
- **Device needed:** Any USB-C device (host, device, or gadget mode - doesn't matter)
- **Works with:** Direct USB-C connection between two Linux hosts
- **Limitation:** Requires kernel Type-C subsystem support

### Method 2: libusb Enumeration
- **Used when:** Type-C sysfs is not available
- **Device needed:** **USB gadget-mode device** (smartphone, tablet, or Linux with g_ether)
- **Why:** Detects the device enumeration event when connected/disconnected
- **Important:** This is ONLY for detection. The actual networking doesn't need gadget mode.
- **Examples of suitable devices:**
  - Android phone or tablet
  - iOS device (with USB-C to Lightning adapter and appropriate iOS version)
  - Another Linux host with `g_ether` kernel module
  - USB device with gadget-mode firmware support

---

## Step-by-Step Manual Selection

### Method 1: Using `lsusb` (Recommended for most users)

1. **Connect your USB-C device/cable to the target port**

2. **List all USB devices:**
   ```bash
   lsusb
   ```
   
   Example output:
   ```
   Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
   Bus 002 Device 004: ID 1234:5678 Example Device
   Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
   ```

3. **Identify your device** in the list. Note:
   - **Bus number** (e.g., `002`)
   - **Device number** (e.g., `004`)

4. **Get more details:**
   ```bash
   lsusb -v -s 002:004
   ```
   
   Look for:
   - `iManufacturer`, `iProduct`, `iSerial`
   - `bMaxPower` (power consumption)
   - Endpoint descriptors

### Method 2: Using `dmesg` (For kernel device enumeration)

When you connect a device, the kernel logs it. Check the logs:

```bash
dmesg | tail -50
```

Look for lines like:
```
[timestamp] usb 2-1: new high-speed USB device number 4 using xhci_hcd
[timestamp] usb 2-1: New USB device found, idVendor=1234, idProduct=5678
```

This tells you:
- Bus: `2`
- Port path: `2-1`
- Device: `004` (the device number)

### Method 3: Using `/sys/class/usb_device` (If sysfs is available)

```bash
ls -la /sys/class/usb_device/
```

Each entry corresponds to a USB device. You can then read its attributes:
```bash
cat /sys/class/usb_device/usbX/devnum     # Device number
cat /sys/class/usb_device/usbX/busnum     # Bus number
```

### Method 4: Manual `/dev/bus/usb` Inspection

```bash
ls -la /dev/bus/usb/
# Lists bus directories

ls -la /dev/bus/usb/002/
# Lists devices on bus 002
```

## Creating the Configuration File

Once you've identified your port, create or edit `target_usb_c_port.env`:

```bash
# From the project root:
cp target_usb_c_port.env.example target_usb_c_port.env
# Then edit it with your values
```

### Configuration File Format

```bash
# For sysfs-based systems (with /sys/class/typec/ support)
DETECTION_METHOD=sysfs
TYPEC_PORT=port0
TYPEC_PORT_PATH=/sys/class/typec/port0
TYPEC_DATA_ROLE=host
TYPEC_POWER_ROLE=source
TYPEC_ORIENTATION=normal
USB_CONTROLLER=xhci_hcd

# For systems without sysfs (using libusb enumeration)
DETECTION_METHOD=libusb
USB_BUS=002
USB_DEVICE=004
USB_SPEED=5000
USB_VENDOR_PRODUCT=1234:5678
USB_DESCRIPTION="Example USB Device"
USB_DEVICE_PATH=/dev/bus/usb/002/004
```

## Verifying Your Selection

After creating the configuration file, verify it's correct:

```bash
# Source the configuration
source target_usb_c_port.env

# For sysfs method:
if [[ "$DETECTION_METHOD" == "sysfs" ]]; then
    echo "Checking Type-C port: $TYPEC_PORT"
    ls -la "$TYPEC_PORT_PATH"
    [[ -d "$TYPEC_PORT_PATH-partner" ]] && echo "✓ Device connected" || echo "✗ No device connected"
fi

# For libusb method:
if [[ "$DETECTION_METHOD" == "libusb" ]]; then
    echo "Checking USB device at bus $USB_BUS, device $USB_DEVICE"
    ls -la "$USB_DEVICE_PATH"
    lsusb -s "$USB_BUS:$USB_DEVICE"
fi
```

## Troubleshooting

### "Device not found" errors

- **Ensure the device is connected** to the USB-C port
- **Check the bus/device numbers** – they may change each time you reconnect
- **Verify the port path** exists in `/dev/bus/usb/`
- **Check permissions** – USB device access typically requires `sudo` or membership in the `plugdev` group

### Permission denied when accessing USB device

```bash
# Add current user to plugdev group
sudo usermod -a -G plugdev $(whoami)

# Apply group changes (or log out and back in)
newgrp plugdev

# Verify permissions
ls -la /dev/bus/usb/002/004
```

### Port information changes after reconnection

USB device numbers are assigned dynamically. If you frequently reconnect your device:

1. Use a USB hub in a fixed location
2. Use a USB device with a serial number for identification
3. Script the port detection to run before each operation

### How to find the physical port

If you have multiple USB-C ports:

1. **Try one port** and note the bus/device numbers
2. **Disconnect and reconnect** at the same port – device numbers should stabilize
3. **Try a different port** to compare

## For Docker/Container Passthrough

Once you have the USB device path, you can pass it to containers:

```bash
source target_usb_c_port.env

docker run \
  --device="$USB_DEVICE_PATH" \
  --privileged \
  my-usb-app
```

## Advanced: Using udev Rules

For permanent, predictable device identification, create a udev rule:

```bash
# Create /etc/udev/rules.d/99-usb-c-network.rules
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1234", ATTRS{idProduct}=="5678", SYMLINK+="usb-c-net-device"

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# The device is now available at: /dev/usb-c-net-device
```

Update `target_usb_c_port.env`:
```bash
USB_DEVICE_PATH=/dev/usb-c-net-device
```

## Architecture Note: Why Gadget Mode is Different for Detection vs Operation

You might notice a seeming contradiction: The project aims to support **host-to-host USB-C networking without gadget mode**, but the detection script (libusb method) requires a gadget-mode device.

### Here's why:

**Detection Phase (identifying the port):**
- The libusb enumeration method works by watching the USB device list
- It detects when a **device is enumerated** by the kernel
- This is easiest to observe with gadget-mode devices (they present themselves as USB devices)
- You temporarily connect a phone/gadget to see which port it appears on
- Once identified, you don't need that phone/gadget anymore

**Networking Phase (actual USB-C communication):**
- Direct USB communication between two hosts
- The project implements custom USB protocols that work between two peers
- No gadget mode infrastructure needed
- Both sides can be standard Linux hosts

### In Summary:

| Phase | Requirement | Reason |
|-------|-------------|--------|
| **Detection** (finding which port) | May need gadget device (for libusb method) | Easier to watch USB enumeration with gadget devices |
| **Networking** (using the port) | NO gadget mode needed | Direct USB communication between hosts |
| **sysfs Detection** (if available) | Any USB-C device | Type-C subsystem detects ports natively |

This is a **detection-only limitation**, not a project limitation.

## Getting Help

If you're still having trouble:

1. **Check the debug log:**
   ```bash
   cat find-usb-port-debug.out
   ```

2. **Run the automatic detection script with verbose output:**
   ```bash
   sudo bash -x ./scripts/identify-usb-c-port.sh
   ```

3. **Collect system information:**
   ```bash
   lsusb -v > usb-info.txt
   dmesg | tail -100 > dmesg.txt
   ```

4. **Open an issue** with the collected information.
