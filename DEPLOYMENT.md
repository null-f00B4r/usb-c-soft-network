# Live Hardware Deployment Guide

## Project Goal

This project implements **software-based USB-C networking without kernel gadget drivers**. Instead of using `g_ether` or similar kernel modules, we:

1. **Access USB hardware directly** via libusb or /dev/bus/usb
2. **Implement USB protocols in userspace** (enumeration, descriptors, bulk transfers)
3. **Create a pure software network stack** over USB-C
4. **Handle USB-C specific features** (Type-C detection, PD, alt modes)

This means **both machines act as regular USB hosts** - no gadget mode needed!

## Quick Deployment Steps

### 1. Transfer and Build on Remote Host

```bash
# From local machine, transfer the project
rsync -avz --exclude='build' --exclude='.git' \
    /path/to/usb-c-soft-network/ qos:~/usb-c-soft-network/

# SSH to remote host
ssh qos

# Build with Intel compilers
cd ~/usb-c-soft-network
export PATH=/opt/intel/oneapi/compiler/2025.3/bin:$PATH
./scripts/host_build.sh RelWithDebInfo

# Install binaries
cd build
sudo make install

# Verify installation
which simple_usb_net dummy
```

### 2. USB-C Port Detection (Both Machines)

Before establishing a connection, identify which Type-C port will be used:

```bash
sudo ./scripts/identify-usb-c-port.sh
```

This script automatically selects the best detection method:

**Default: Type-C sysfs detection**
- Works for **host-to-host** connections without gadget mode
- Monitors `/sys/class/typec/` for physical cable connections
- Recommended for most scenarios

**Fallback: libusb device enumeration**
- Automatically used if sysfs method fails
- Only works when one end is in USB gadget/device mode
- Requires USB device enumeration changes

The script will:
- Check for root privileges (required for accurate detection)
- List all available Type-C ports
- Monitor for cable connection/disconnection events
- Save port configuration to `target_usb_c_port.env`

### 3. Determine Host vs Device Roles

**USB Host (qos)**: The computer that provides power and initiates communication
**USB Device (local)**: The gadget that responds to the host

In your setup:
- `qos` appears to be the **USB host** (desktop/server)
- Local machine appears to be the **USB device** (laptop/portable)

### 3. Set Up USB Gadget (Device Side - Local Machine)

```bash
# Load USB gadget module
sudo modprobe g_ether

# Or use configfs for more control:
sudo modprobe libcomposite
sudo mount -t configfs none /sys/kernel/config 2>/dev/null || true

# Check if usb0 interface appeared
ip link show usb0

# Configure the network interface
sudo ip addr add 192.168.7.2/24 dev usb0
sudo ip link set usb0 up
```

### 4. Set Up USB Host (Host Side - qos)

```bash
# Wait for USB device to enumerate
# Check dmesg for new USB network device
dmesg | tail -20 | grep -i usb

# Find the network interface (usually usb0, enp*, or similar)
ip link show | grep usb

# Configure the interface
sudo ip addr add 192.168.7.1/24 dev usb0
sudo ip link set usb0 up

# Verify connectivity
ping -c 3 192.168.7.2
```

### 5. Run the Demo

**On qos (USB Host):**
```bash
sudo simple_usb_net host
```

**On local machine (USB Device):**
```bash
sudo ./build/examples/simple_usb_net device
```

## Troubleshooting Live Hardware

### USB Device Not Appearing

```bash
# Check USB enumeration
dmesg | tail -30 | grep -i usb

# Check loaded modules
lsmod | grep usb
lsmod | grep g_ether

# Try reloading g_ether
sudo rmmod g_ether
sudo modprobe g_ether
```

### Network Interface Not Working

```bash
# Check if interface exists
ip link show | grep usb

# Check interface status
ip addr show usb0

# Restart interface
sudo ip link set usb0 down
sudo ip link set usb0 up

# Check routing
ip route
```

### Permission Issues

```bash
# Ensure running with sudo
sudo ./simple_usb_net device

# Check USB device permissions
ls -l /dev/bus/usb/

# Add user to appropriate group (alternative to sudo)
sudo usermod -a -G dialout $USER
# Log out and back in for group changes
```

### Firewall Blocking

```bash
# Temporarily disable firewall for testing
sudo ufw disable  # Ubuntu/Debian
sudo systemctl stop firewalld  # RHEL/Fedora

# Or allow specific port
sudo ufw allow 9999/udp
```

## Alternative: Simple Network Test First

Before running the demo, verify basic USB networking works:

**Device side (local):**
```bash
sudo modprobe g_ether
sudo ip addr add 192.168.7.2/24 dev usb0
sudo ip link set usb0 up
```

**Host side (qos):**
```bash
sudo ip addr add 192.168.7.1/24 dev usb0
sudo ip link set usb0 up
ping 192.168.7.2
```

Once basic connectivity works, proceed with the demo applications.

## Checking Hardware Connection

**Check physical connection:**
```bash
# Local machine
lsusb -t

# Remote machine (qos)
ssh qos lsusb -t
```

**Verify USB-C cable supports data:**
- Not all USB-C cables support data transfer
- Some are power-only
- Try a different cable if devices don't enumerate

## Expected Output

**Device side:**
```
USB-C Software Network Demo
============================

=== Running as USB DEVICE ===
Setting up USB gadget mode...
Sending messages to host at 192.168.7.1:9999
Sending: Hello from device #0
Received: ACK from host
...
```

**Host side:**
```
USB-C Software Network Demo
============================

=== Running as USB HOST ===
Setting up USB host mode...
Listening on 192.168.7.1:9999
Waiting for messages from device...
Received: Hello from device #0
...
```

## Cleanup

```bash
# Remove network configuration
sudo ip addr del 192.168.7.1/24 dev usb0  # on host
sudo ip addr del 192.168.7.2/24 dev usb0  # on device

# Unload modules
sudo rmmod g_ether
```

## Next Steps After Successful Test

1. Implement actual USB-C specific features
2. Add performance benchmarking
3. Implement file transfer protocol
4. Add encryption for data security
5. Create systemd service for automatic setup
