# USB-C Host-to-Host Connection Workflow

This document describes the complete workflow for establishing a USB-C network connection between two Linux hosts.

## Architecture Overview

```
┌─────────────────┐                    ┌─────────────────┐
│   Device 1      │    USB-C Cable     │   Device 2      │
│  (Linux Host)   │◄──────────────────►│  (Linux Host)   │
│                 │   Direct H2H       │                 │
│ /sys/class/     │   Connection       │ /sys/class/     │
│   typec/port1   │                    │   typec/port0   │
└─────────────────┘                    └─────────────────┘
```

**Key Point:** This is NOT USB gadget mode. This is direct host-to-host USB-C communication using the Linux Type-C subsystem.

## Prerequisites

Both devices must have:
- Linux kernel 5.10+ with Type-C subsystem (`CONFIG_TYPEC`)
- USB-C port with data support (not charge-only)
- Data-capable USB-C cable
- Root/sudo access
- This software built and installed

## Phase 1: Port Identification (Each Device)

Before connecting the cable between hosts, each device must identify which USB-C port to use.

### On Device 1 (e.g., your local PC)

```bash
cd /path/to/usb-c-soft-network

# Run the identification script
# This may require temporarily connecting a USB device (like a phone)
# to identify the correct port
./scripts/identify-usb-c-port.sh

# Verify the configuration was created
cat target_usb_c_port.env
```

### On Device 2 (e.g., remote PC "qos")

```bash
cd /path/to/usb-c-soft-network

# Same process on the second device
./scripts/identify-usb-c-port.sh

# Verify
cat target_usb_c_port.env
```

### Manual Configuration (Alternative)

If automatic detection doesn't work, create `target_usb_c_port.env` manually:

```bash
# For Type-C sysfs method (preferred for host-to-host)
DETECTION_METHOD=sysfs
TYPEC_PORT=port0
TYPEC_PORT_PATH=/sys/class/typec/port0
TYPEC_DATA_ROLE=host
TYPEC_POWER_ROLE=source
```

See [docs/how-to-select-port.md](how-to-select-port.md) for detailed manual selection instructions.

## Phase 2: Connect the USB-C Cable

Once BOTH devices have `target_usb_c_port.env` configured:

1. **Disconnect any test devices** used during port identification
2. **Connect the USB-C cable** between the two identified ports
3. **Verify the connection** on both sides

### Verify Connection on Each Device

```bash
# Check if Type-C partner is detected
source target_usb_c_port.env

if [[ "$DETECTION_METHOD" == "sysfs" ]]; then
    if [[ -d "${TYPEC_PORT_PATH}-partner" ]]; then
        echo "✓ USB-C cable connected on $TYPEC_PORT"
        cat "${TYPEC_PORT_PATH}/data_role"
        cat "${TYPEC_PORT_PATH}/power_role"
    else
        echo "✗ No USB-C connection detected on $TYPEC_PORT"
    fi
fi

# Check kernel messages
dmesg | tail -20 | grep -i typec
```

### Expected Output When Connected

```
✓ USB-C cable connected on port0
host [device]
source [sink]
```

The bracketed role indicates the current active role.

## Phase 3: Establish Network Link

Once the physical USB-C connection is verified on both devices:

### On Device 1 (Host Role)

```bash
# Start the USB-C network in host mode
sudo ./build/usb-c-net --mode host

# Or use the example
sudo ./build/examples/simple_usb_net host
```

### On Device 2 (Device Role)

```bash
# Start the USB-C network in device mode
sudo ./build/usb-c-net --mode device

# Or use the example
sudo ./build/examples/simple_usb_net device
```

## Phase 4: Test Connectivity

Once both sides report the network is up:

```bash
# On Device 1 (host side, typically 192.168.7.1)
ping 192.168.7.2

# On Device 2 (device side, typically 192.168.7.2)
ping 192.168.7.1
```

## Troubleshooting

### "No USB-C connection detected"

1. **Check the cable**: Ensure it's a data-capable USB-C cable, not charge-only
2. **Check the ports**: Both ports must support USB data (not charging-only ports)
3. **Check kernel modules**: 
   ```bash
   sudo modprobe typec
   sudo modprobe typec_ucsi
   lsmod | grep typec
   ```
4. **Check dmesg**: `dmesg | grep -i typec`

### "Permission denied"

```bash
# Ensure you're running with sudo
sudo ./build/usb-c-net

# Or add udev rules for USB access
sudo usermod -a -G plugdev $(whoami)
```

### Connection drops intermittently

- Try a different USB-C cable (some cables are lower quality)
- Check for loose connections
- Monitor `dmesg -w` for kernel messages

### Data role negotiation issues

USB-C supports role swap. If both devices try to be host:

```bash
# Force device role on one side
echo "device" | sudo tee /sys/class/typec/port0/data_role
```

## Quick Reference

| Step | Device 1 | Device 2 |
|------|----------|----------|
| 1. Identify port | `./scripts/identify-usb-c-port.sh` | `./scripts/identify-usb-c-port.sh` |
| 2. Verify config | `cat target_usb_c_port.env` | `cat target_usb_c_port.env` |
| 3. Connect cable | Connect USB-C port ◄─────► | ─────► Connect USB-C port |
| 4. Verify link | Check `${TYPEC_PORT_PATH}-partner` | Check `${TYPEC_PORT_PATH}-partner` |
| 5. Start network | `sudo ./build/usb-c-net --mode host` | `sudo ./build/usb-c-net --mode device` |
| 6. Test | `ping 192.168.7.2` | `ping 192.168.7.1` |

## Status Check Script

Create a quick status check:

```bash
#!/bin/bash
# check-connection-status.sh

source target_usb_c_port.env

echo "=== USB-C Connection Status ==="
echo "Detection method: $DETECTION_METHOD"

if [[ "$DETECTION_METHOD" == "sysfs" ]]; then
    echo "Type-C port: $TYPEC_PORT"
    echo "Port path: $TYPEC_PORT_PATH"
    
    if [[ -d "${TYPEC_PORT_PATH}-partner" ]]; then
        echo "Status: ✓ CONNECTED"
        echo "Data role: $(cat ${TYPEC_PORT_PATH}/data_role)"
        echo "Power role: $(cat ${TYPEC_PORT_PATH}/power_role)"
    else
        echo "Status: ✗ NOT CONNECTED"
        echo "Waiting for USB-C cable connection..."
    fi
else
    echo "Using libusb detection (for identification only)"
    echo "For host-to-host connection, sysfs method is preferred"
fi
```
