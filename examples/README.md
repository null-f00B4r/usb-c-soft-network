# USB-C Software Network Examples

This directory contains example programs demonstrating the usb-c-soft-network functionality.

## Examples

### simple_usb_net

A basic IP-over-USB demo that shows how to establish network communication between two devices connected via USB-C.

**Features:**
- Host and device (gadget) mode support
- UDP packet exchange demonstration
- Simple echo server/client pattern
- ~1500 byte MTU support

**Architecture:**
```
┌─────────────────┐                  ┌─────────────────┐
│   Host Device   │                  │  Gadget Device  │
│  192.168.7.1    │                  │  192.168.7.2    │
│                 │                  │                 │
│  simple_usb_net │◄────USB-C───────►│  simple_usb_net │
│     (host)      │                  │    (device)     │
└─────────────────┘                  └─────────────────┘
```

## Building the Examples

Examples are built automatically when you build the main project:

```bash
# Using host build script
./scripts/host_build.sh RelWithDebInfo

# Or manually with CMake
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
cmake --build build --parallel
```

Built executables will be in: `build/examples/`

## Running the Example

### Prerequisites

1. **Two Linux machines** or one Linux machine and a VM with USB passthrough
2. **USB-C cable** connecting the two devices
3. **Root privileges** (required for USB gadget setup and network configuration)
4. **Kernel modules**: `g_ether` or configfs gadget support

### Setup

#### On the Device (Gadget) side:

```bash
# Load USB gadget module (if not using configfs)
sudo modprobe g_ether

# Or use configfs (more flexible):
sudo mount -t configfs none /sys/kernel/config
cd /sys/kernel/config/usb_gadget
# ... configure gadget (see kernel documentation)

# Run the example
cd build/examples
sudo ./simple_usb_net device
```

#### On the Host side:

```bash
# The USB network device should appear automatically (usually usb0)
# Configure the interface:
sudo ip addr add 192.168.7.1/24 dev usb0
sudo ip link set usb0 up

# Run the example
cd build/examples
sudo ./simple_usb_net host
```

### Expected Output

**Device side:**
```
USB-C Software Network Demo
============================

=== Running as USB DEVICE ===
Setting up USB gadget mode...
Sending messages to host at 192.168.7.1:9999
Sending: Hello from device #0
Received: ACK from host
Sending: Hello from device #1
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
Received: Hello from device #1
...
```

## Testing with Virtual Machines

For safer testing without two physical machines, use QEMU with USB passthrough:

```bash
# Find your USB-C device
./scripts/find-usb-c-ports.sh

# Run VM with USB passthrough
./scripts/run-vm-tests.sh
# Follow the prompts to select the USB device
```

Inside the VM, run the device side, and on the host run the host side.

## Troubleshooting

### "Permission denied" errors
- Ensure you're running with `sudo` or as root
- Check that your user has permission to access `/dev/bus/usb/`

### "No such device" errors
- Verify USB cable is properly connected
- Check `dmesg | tail` for USB enumeration messages
- Verify kernel modules are loaded: `lsmod | grep usb`

### Network interface not appearing
- Check if `usb0` interface exists: `ip link show`
- Load g_ether module: `sudo modprobe g_ether`
- Check kernel logs: `sudo dmesg | grep -i usb`

### Cannot bind to address
- Check if port is already in use: `sudo netstat -tuln | grep 9999`
- Verify IP address is configured: `ip addr show dev usb0`

## Next Steps

This example demonstrates the basic concept. For production use, you would need:

1. **Proper USB descriptor configuration** - Device class, vendor ID, etc.
2. **Network protocol implementation** - Ethernet framing, ARP, IP routing
3. **Error handling and recovery** - Cable disconnect, packet loss
4. **Performance optimization** - Bulk transfers, DMA, buffering
5. **Security** - Authentication, encryption for sensitive data

See the main project source code for the full implementation.

## References

- [Linux USB Gadget API](https://www.kernel.org/doc/html/latest/usb/gadget.html)
- [USB Network Device Class (CDC-ECM)](https://www.usb.org/document-library/class-definitions-communication-devices-12)
- [g_ether kernel module documentation](https://www.kernel.org/doc/Documentation/usb/gadget_configfs.txt)
