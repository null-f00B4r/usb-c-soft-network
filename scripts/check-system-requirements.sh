#!/usr/bin/env bash
set -euo pipefail

# System Requirements Checker for usb-c-soft-network
# Verifies that the system has necessary Type-C support

echo "=== USB-C Soft Network - System Requirements Check ==="
echo ""

EXIT_CODE=0

# Check 1: Kernel Version
echo "[1/5] Checking kernel version..."
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(uname -r | cut -d. -f1)
KERNEL_MINOR=$(uname -r | cut -d. -f2)

echo "  Kernel: $KERNEL_VERSION"

if [[ $KERNEL_MAJOR -ge 6 ]] || [[ $KERNEL_MAJOR -eq 5 && $KERNEL_MINOR -ge 10 ]]; then
    echo "  ✓ Kernel version is sufficient (5.10+ required)"
else
    echo "  ⚠️  Kernel version may be too old (5.10+ recommended)"
    echo "     Type-C support improved significantly in kernel 5.10+"
fi
echo ""

# Check 2: Type-C Kernel Modules
echo "[2/5] Checking Type-C kernel module availability..."

TYPEC_MODULES=("typec" "typec_ucsi" "ucsi_acpi")
TYPEC_AVAILABLE=0
TYPEC_MISSING=()

for module in "${TYPEC_MODULES[@]}"; do
    if modinfo "$module" &>/dev/null; then
        echo "  ✓ Module '$module' available"
        TYPEC_AVAILABLE=$((TYPEC_AVAILABLE + 1))
    else
        echo "  ✗ Module '$module' NOT available"
        TYPEC_MISSING+=("$module")
    fi
done

if [[ $TYPEC_AVAILABLE -lt 2 ]]; then
    echo ""
    echo "  ❌ CRITICAL: Required Type-C modules missing"
    echo "     At minimum, 'typec' and 'typec_ucsi' are required"
    EXIT_CODE=1
else
    echo "  ✓ Required Type-C modules are available"
fi
echo ""

# Check 3: Load modules and check sysfs
echo "[3/5] Checking Type-C sysfs support..."

if [[ $EUID -eq 0 ]]; then
    # Try to load modules if running as root
    for module in "typec" "typec_ucsi"; do
        if ! lsmod | grep -q "^${module} "; then
            modprobe "$module" 2>/dev/null || true
        fi
    done
    sleep 1
fi

if [[ -d "/sys/class/typec" ]]; then
    PORT_COUNT=$(ls -d /sys/class/typec/port[0-9]* 2>/dev/null | wc -l || echo "0")
    PORT_COUNT=$(echo "$PORT_COUNT" | tr -d '[:space:]')
    echo "  ✓ Type-C sysfs present: /sys/class/typec/"
    if [[ "$PORT_COUNT" -gt 0 ]]; then
        echo "  ✓ Detected $PORT_COUNT Type-C port(s)"
    else
        echo "  ❌ Type-C subsystem loaded but NO ports detected"
        echo ""
        echo "     The kernel has Type-C support, but no Type-C Port Manager (TCPM)"
        echo "     was detected. This typically means:"
        echo ""
        echo "     1. System has USB-C ports but no UCSI firmware interface"
        echo "     2. USB-C controller uses vendor-specific management"
        echo "     3. BIOS/UEFI doesn't expose UCSI ACPI interface"
        echo "     4. Additional platform-specific drivers required"
        echo ""
        echo "     This project REQUIRES /sys/class/typec/portX entries for"
        echo "     host-to-host USB-C networking. Without port enumeration,"
        echo "     cable connection detection is not possible."
        echo ""
        EXIT_CODE=1
    fi
else
    echo "  ✗ Type-C sysfs NOT present: /sys/class/typec/"
    if [[ $EUID -ne 0 ]]; then
        echo "     (Re-run with sudo to attempt module loading)"
    else
        echo "     Modules are loaded but sysfs not created"
        echo "     This indicates no USB-C controllers detected"
    fi
    EXIT_CODE=1
fi
echo ""

# Check 4: USB Controllers
echo "[4/5] Checking USB controller hardware..."

if lspci -nn | grep -qi "USB.*[Cc]ontroller.*[Tt]ype-*C\|Thunderbolt"; then
    echo "  ✓ USB-C/Thunderbolt controller detected"
    lspci | grep -i "usb.*controller\|thunderbolt" | sed 's/^/    /'
elif lspci -nn | grep -qi "USB"; then
    echo "  ⚠️  USB controllers found but no explicit Type-C mention"
    echo "     Modern USB 3.x controllers often support Type-C"
    lspci | grep -i usb | head -3 | sed 's/^/    /'
else
    echo "  ✗ No USB controllers detected"
    EXIT_CODE=1
fi
echo ""

# Check 5: libusb (for fallback functionality)
echo "[5/5] Checking libusb support..."

if pkg-config --exists libusb-1.0; then
    LIBUSB_VERSION=$(pkg-config --modversion libusb-1.0)
    echo "  ✓ libusb-1.0 installed (version $LIBUSB_VERSION)"
else
    echo "  ⚠️  libusb-1.0 not found"
    echo "     Install with: sudo apt install libusb-1.0-0-dev"
fi
echo ""

# Summary
echo "========================================"
echo "Summary:"
echo ""

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✅ System meets requirements for USB-C host-to-host networking"
    echo ""
    echo "Next steps:"
    echo "  1. Build the project: ./scripts/host_build.sh RelWithDebInfo"
    echo "  2. Identify USB-C port: sudo ./scripts/identify-usb-c-port.sh"
    echo "  3. Run examples: sudo ./build/examples/simple_usb_net"
else
    echo "❌ System does NOT meet requirements"
    echo ""
    echo "Issues found:"
    if [[ ${#TYPEC_MISSING[@]} -gt 0 ]]; then
        echo "  • Missing Type-C kernel modules: ${TYPEC_MISSING[*]}"
    fi
    if [[ ! -d "/sys/class/typec" ]]; then
        echo "  • Type-C sysfs not available"
    fi
    PORT_COUNT=$(ls -d /sys/class/typec/port[0-9]* 2>/dev/null | wc -l || echo "0")
    PORT_COUNT=$(echo "$PORT_COUNT" | tr -d '[:space:]')
    if [[ -d "/sys/class/typec" ]] && [[ "$PORT_COUNT" -eq 0 ]]; then
        echo "  • Type-C sysfs exists but NO ports detected (critical issue)"
        echo ""
        echo "Root cause: USB-C hardware present but not managed by kernel Type-C subsystem"
        echo ""
        echo "Your system has USB-C ports but they are NOT exposed through the"
        echo "Linux Type-C subsystem (/sys/class/typec/). This project requires"
        echo "UCSI (USB Type-C Connector System Software Interface) or compatible"
        echo "Type-C Port Manager support in the kernel."
        echo ""
        echo "Possible reasons:"
        echo "  • BIOS/UEFI doesn't expose UCSI ACPI interface"
        echo "  • USB-C controller uses proprietary/vendor-specific management"
        echo "  • Additional platform drivers needed (Intel/AMD chipset-specific)"
        echo "  • USB-C ports are actually USB 3.x Type-A with Type-C connector"
        echo ""
        echo "Unfortunately, this project CANNOT function without kernel Type-C"
        echo "port enumeration. Alternative approaches (like USB gadget mode)"
        echo "are explicitly NOT supported per the design requirements."
        echo ""
    fi
    echo ""
    echo "Solutions:"
    if [[ ${#TYPEC_MISSING[@]} -gt 0 ]]; then
        echo "  1. Use a distribution kernel (Debian/Ubuntu/Fedora/Arch)"
    fi
    echo "  2. Check BIOS/UEFI settings for USB-C/Thunderbolt configuration"
    echo "  3. Try updating BIOS/UEFI firmware to latest version"
    echo "  4. Verify ports are true USB-C (not just Type-C connector shape)"
    echo "  5. Check if Intel/AMD platform drivers are loaded"
    echo "  6. See docs/TROUBLESHOOTING.md for detailed help"
fi

echo ""
exit $EXIT_CODE
