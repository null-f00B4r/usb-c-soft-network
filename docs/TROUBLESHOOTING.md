# Troubleshooting Guide

## System Requirements

### USB-C Type-C Kernel Support (REQUIRED)

This project requires the Linux kernel Type-C subsystem for host-to-host USB-C networking.

**Check if your system has Type-C support:**
```bash
# Check if Type-C modules are available
modinfo typec
modinfo typec_ucsi

# Check kernel config (if available)
zgrep CONFIG_TYPEC /proc/config.gz
# Should show: CONFIG_TYPEC=m or CONFIG_TYPEC=y
```

**If Type-C modules are missing:**

1. **Use a modern distribution kernel** (most include Type-C support):
   - Debian/Ubuntu 20.04+
   - Fedora 33+
   - Arch Linux (latest)
   - RHEL/CentOS 8+

2. **Recompile kernel with Type-C support:**
   ```
   CONFIG_TYPEC=m
   CONFIG_TYPEC_UCSI=m
   CONFIG_UCSI_ACPI=m
   ```

3. **Load the modules:**
   ```bash
   sudo modprobe typec
   sudo modprobe typec_ucsi
   ```

**Verify Type-C sysfs is available:**
```bash
ls /sys/class/typec/
# Should show: port0  port1  (or similar)
```

**This project does NOT support:**
- ❌ USB gadget mode fallback (not needed for host-to-host)
- ❌ Charge-only cables (data lines required)
- ❌ Systems without USB-C hardware
- ❌ Kernels without CONFIG_TYPEC support

---

## USB-C Port Detection Issues

### Problem: Type-C subsystem not found

**Symptoms:**
```
❌ ERROR: Required Type-C kernel modules not available:
  - typec
  - typec_ucsi
```

**Cause:**
Your kernel doesn't have Type-C support compiled in.

**Solution:**
1. Check kernel version: `uname -r`
2. Verify you're running a modern kernel (5.10+)
3. Install distribution kernel if using custom kernel
4. Or recompile with `CONFIG_TYPEC=m`

---

### Problem: Script requires sudo/root privileges

**Symptoms:**
```
❌ ERROR: Root privileges required
This tool requires root access to:
  - Load Type-C kernel modules
  - Access Type-C sysfs attributes in /sys/class/typec/
```

**Cause:**
The script needs root access to:
- Load kernel modules (`modprobe`)
- Read Type-C sysfs attributes in `/sys/class/typec/`
- Detect USB-C port connections accurately

**Solution:**
Always run with sudo:
```bash
sudo ./scripts/identify-usb-c-port.sh
```

Root access is mandatory for proper Type-C detection.

---

### Problem: Type-C modules loaded but no ports detected

**Symptoms:**
```bash
$ ls /sys/class/typec/
# Empty directory - no port0, port1, etc.

$ lspci | grep -i usb
00:14.0 USB controller: Intel Corporation Raptor Lake USB 3.2 Gen 2x2 (20 Gb/s) XHCI Host Controller
```

**Cause:**
The system has USB-C physical ports and kernel Type-C support, but the ports are not managed by the Linux Type-C subsystem. This occurs when:

1. **No UCSI Interface**: BIOS/UEFI doesn't expose USB Type-C Connector System Software Interface (UCSI) via ACPI
2. **Vendor-Specific Management**: USB-C controller uses proprietary firmware/management
3. **Missing Platform Drivers**: Intel/AMD chipset-specific drivers not loaded
4. **Not True Type-C**: Ports are USB 3.x with Type-C connector shape but no Type-C protocol support

**Verification:**
```bash
# Check if UCSI ACPI device exists
sudo dmesg | grep -i ucsi
# If empty, no UCSI interface found

# Try loading UCSI ACPI driver
sudo modprobe ucsi_acpi
sudo dmesg | tail -20
# Look for "ucsi_acpi" messages

# Check ACPI tables for UCSI
sudo acpidump | grep -i usbc
```

**Solution:**

This is a **hardware/firmware limitation**. The project **cannot function** without `/sys/class/typec/portX` entries.

**Options:**

1. **Update BIOS/UEFI**: Check manufacturer's website for firmware updates that may add UCSI support

2. **Enable in BIOS**: Some systems have USB-C/Thunderbolt settings that must be enabled:
   - Boot into BIOS/UEFI setup
   - Look for "USB Configuration", "Thunderbolt", or "Type-C" settings
   - Enable "UCSI Support", "Type-C Port Management", etc.

3. **Use Different Hardware**: Test on a system with confirmed Type-C subsystem support:
   - Modern laptops with Thunderbolt 3/4
   - Systems with discrete USB-C controllers
   - Devices with Type-C DisplayPort alternate mode

4. **Check Kernel Support**: Ensure you're running a recent kernel (5.15+) with full UCSI support

**This project explicitly does NOT support:**
- USB gadget mode as workaround (by design - see README)
- Systems without kernel Type-C port enumeration
- Proprietary USB-C management interfaces

**Why this is required:**

Host-to-host USB-C networking (per project design) requires detecting cable connection/disconnection via Type-C sysfs (`/sys/class/typec/portX/data_role`, `/sys/class/typec/portX-partner/`, etc.). Without this, the project cannot:
- Detect when a cable is connected
- Determine cable orientation
- Negotiate data roles (DFP/UFP)
- Detect partner device capabilities

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
