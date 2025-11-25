# Troubleshooting Guide

## USB-C Port Detection Issues

### Problem: Script requires sudo/root privileges

**Symptoms:**
```
⚠️  WARNING: Not running as root (sudo)
Continue in non-root mode (might not be accurate)? (y/N):
```

**Cause:**
The script needs root access to:
- Read Type-C sysfs attributes in `/sys/class/typec/`
- Enumerate USB devices via libusb
- Access hardware information accurately

**Solution:**
Run with sudo:
```bash
sudo ./scripts/identify-usb-c-port.sh
```

If you choose to continue without root, detection may be inaccurate or fail.

---

### Problem: Detection method selection

**How it works:**
The script automatically selects the best detection method:

1. **Type-C sysfs** (default, preferred):
   - Checks if `/sys/class/typec/` exists
   - Works for host-to-host connections
   - No gadget mode required

2. **libusb enumeration** (fallback):
   - Used if sysfs method unavailable or fails
   - Requires one end in USB gadget mode
   - Detects device enumeration changes

**Force a specific method:**
The script automatically falls back if the primary method fails, so no manual selection is needed.

---

### Problem: `identify-usb-c-port.sh` not detecting changes (sysfs method)

**Symptoms:**
```
Error: No Type-C port state change detected.
Falling back to libusb device enumeration method...
```

**Causes:**
- Cable was already connected at "BEFORE" state
- Both machines are USB hosts (no gadget mode)
- Port doesn't support Type-C detection
- Cable doesn't have proper USB-C connectors

**Solutions:**

1. **Disconnect all cables before starting**:
   - Run the script with all USB-C cables disconnected
   - Follow the prompts to connect cable at the right time

2. **Use the libusb fallback** (if one end has gadget mode):
   - The script will automatically offer this option
   - Requires USB device enumeration support

3. **Check sysfs support**:
   ```bash
   ls -la /sys/class/typec/
   ```

---

### Problem: No detection method works

**Symptoms:**
Both sysfs and libusb methods fail

**Debug steps:**

1. **Check Type-C subsystem**:
   ```bash
   ls -la /sys/class/typec/
   cat /sys/class/typec/port0/data_role 2>/dev/null || echo "Cannot read"
   ```

2. **Check libusb**:
   ```bash
   lsusb
   sudo ./build/usb-c-net
   ```

3. **Review debug log**:
   ```bash
   cat find-usb-port-debug.out
   ```

**Possible causes:**
- Kernel doesn't support Type-C subsystem (CONFIG_TYPEC not enabled)
- No USB-C ports on the machine
- Permissions issues even with sudo
- Hardware doesn't expose Type-C information

---

### Problem: Script exits with errors reading sysfs attributes

**Symptoms:**
- Error messages about missing files in `/sys/class/typec/`
- Script cannot read port attributes

**Cause:**
Some Type-C ports don't expose all sysfs attributes (especially `orientation`).

**Solution:**
The merged script now handles this gracefully with conditional reads. This is already implemented in the current version.

**Debug Commands:**

### Problem: No detection method works

### Problem: No detection method works

**Symptoms:**
Both sysfs and libusb methods fail

**Debug steps:**

1. **Check Type-C subsystem**:
   ```bash
   ls -la /sys/class/typec/
   cat /sys/class/typec/port0/data_role 2>/dev/null || echo "Cannot read"
   ```

2. **Check libusb**:
   ```bash
   lsusb
   sudo ./build/usb-c-net
   ```

3. **Review debug log**:
   ```bash
   cat find-usb-port-debug.out
   ```

**Possible causes:**
- Kernel doesn't support Type-C subsystem (CONFIG_TYPEC not enabled)
- No USB-C ports on the machine
- Permissions issues even with sudo
- Hardware doesn't expose Type-C information

---

### Problem: Script exits with errors reading sysfs attributes
```bash
# Check if sysfs attributes exist
ls -la /sys/class/typec/port0/

# Test attribute reads manually
cat /sys/class/typec/port0/data_role 2>/dev/null || echo "missing"
cat /sys/class/typec/port0/orientation 2>/dev/null || echo "missing"

# Run with trace enabled
sudo bash -x ./scripts/identify-usb-c-port-sysfs.sh 2>&1 | tee /tmp/debug.log

# Check where script stops
tail -100 /tmp/debug.log
```

---

### Problem: Permission denied on debug file

**Symptoms:**
```
bash: /home/q/usb-c-soft-network/find-usb-port-debug.out: Permission denied
```

**Cause:**
Debug file was created by root (sudo) and current user can't write to it.

**Solution:**
```bash
sudo rm -f /home/q/usb-c-soft-network/find-usb-port-debug.out
```

Or make script create file with correct permissions:
```bash
touch "$DEBUG_FILE" && chmod 666 "$DEBUG_FILE"
```

---

## Build Issues

### Intel oneAPI compiler not found

**Symptoms:**
```
CMake Error: Could not find Intel C compiler (icx)
```

**Solutions:**

1. **Install Intel oneAPI** (recommended for production):
   ```bash
   # Follow: https://www.intel.com/content/www/us/en/developer/tools/oneapi.html
   source /opt/intel/oneapi/setvars.sh
   ```

2. **Build with system compilers** (testing only):
   ```bash
   SKIP_COMPILER_CHECK=1 ./scripts/host_build.sh RelWithDebInfo
   ```

3. **Use devcontainer** (no local installation needed):
   ```bash
   docker build -f .devcontainer/Dockerfile -t usb-c-soft-network-ci:latest .
   docker run --rm -v "$PWD:/workspaces/usb-c-soft-network" \
       usb-c-soft-network-ci:latest ./scripts/build.sh
   ```

---

## USB Hardware Access Issues

### libusb initialization fails

**Check permissions:**
```bash
# List USB devices
lsusb

# Check /dev/bus/usb permissions
ls -la /dev/bus/usb/

# Run with sudo if needed
sudo ./build/usb-c-net
```

### No USB devices detected

**Verify kernel modules:**
```bash
# Check if USB subsystem is available
lsmod | grep usb
dmesg | grep -i usb

# Check sysfs
ls -la /sys/bus/usb/devices/
```

---

## Type-C Subsystem Issues

### No Type-C ports found

**Check kernel support:**
```bash
# Verify Type-C subsystem exists
ls -la /sys/class/typec/

# If missing, check kernel config
zcat /proc/config.gz | grep -i typec

# Required kernel options:
# CONFIG_TYPEC=y
# CONFIG_TYPEC_TCPM=m
# CONFIG_USB_ROLE_SWITCH=y
```

### Port attributes missing

Some laptops/desktops don't expose all Type-C attributes. The script should handle this gracefully with fallbacks to "unknown".

**Expected attributes:**
- `data_role` (required)
- `power_role` (required)
- `vconn_source` (optional)
- `orientation` (optional, often missing)
- `usb_power_delivery` (optional)

**Partner detection:**
The key indicator is whether `$port-partner` directory exists:
```bash
ls -ld /sys/class/typec/port0-partner 2>/dev/null && echo "Connected" || echo "Disconnected"
```

---

## Testing Workflow

### Recommended test sequence:

1. **Build verification** (no hardware):
   ```bash
   ./scripts/host_build.sh RelWithDebInfo
   cd build && make test
   ```

2. **Port detection** (with USB-C cable):
   ```bash
   sudo ./scripts/identify-usb-c-port-sysfs.sh
   source target_usb_c_port.env
   echo "Detected: $TYPEC_PORT at $TYPEC_PORT_PATH"
   ```

3. **Monitor connection** (watch for cable events):
   ```bash
   watch -n 1 'ls -ld /sys/class/typec/port1-partner 2>/dev/null || echo "Not connected"'
   ```

4. **USB hardware enumeration**:
   ```bash
   sudo ./build/usb-c-net
   ```

---

## Getting Help

If you encounter an issue not covered here:

1. **Collect debug information:**
   ```bash
   # System info
   uname -a
   lsusb -v > usb-devices.txt
   ls -laR /sys/class/typec/ > typec-sysfs.txt
   
   # Build info
   cd build
   cmake -LA . > cmake-config.txt
   
   # Kernel logs
   dmesg | tail -100 > dmesg.txt
   ```

2. **Check existing issues:**
   - GitHub Issues: https://github.com/yourusername/usb-c-soft-network/issues

3. **Report with details:**
   - OS and kernel version
   - Hardware: laptop/desktop, USB-C port type
   - Exact error messages and command outputs
   - Debug logs from scripts

---

## Quick Reference

### Port Detection Commands
```bash
# Run unified detection script (auto-selects method)
sudo ./scripts/identify-usb-c-port.sh

# List Type-C ports
ls -la /sys/class/typec/

# Check port state
cat /sys/class/typec/port0/data_role
cat /sys/class/typec/port0/power_role

# Check connection
ls -ld /sys/class/typec/port0-partner 2>/dev/null

# View saved configuration
cat target_usb_c_port.env
```

### Build Commands
```bash
# Full rebuild
rm -rf build
./scripts/host_build.sh RelWithDebInfo

# Quick rebuild after code changes
cd build && make -j$(nproc)

# Run built binary
sudo ./build/usb-c-net
```

### USB Device Commands
```bash
# List USB devices
lsusb
lsusb -t  # tree view

# Check USB controller
lspci | grep -i usb

# Monitor USB events
sudo udevadm monitor --subsystem=usb

# Kernel logs
dmesg | grep -i usb | tail -20
```
