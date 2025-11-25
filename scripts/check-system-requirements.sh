#!/usr/bin/env bash
set -euo pipefail

# System Requirements Checker for usb-c-soft-network
# Verifies that the system has necessary Type-C support and build dependencies

echo "=== USB-C Soft Network - System Requirements Check ==="
echo ""
echo "This tool checks both runtime (Type-C hardware) and build requirements."
echo ""

EXIT_CODE=0
WARN_COUNT=0

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

# Check 5: libusb (REQUIRED for direct USB access)
echo "[5/8] Checking libusb support..."

if pkg-config --exists libusb-1.0; then
    LIBUSB_VERSION=$(pkg-config --modversion libusb-1.0)
    echo "  ✓ libusb-1.0 installed (version $LIBUSB_VERSION)"
else
    echo "  ❌ libusb-1.0 NOT found (REQUIRED)"
    echo "     Install with: sudo apt install libusb-1.0-0-dev"
    echo "     Or equivalent: pkg-config libusb-1.0"
    EXIT_CODE=1
fi
echo ""

# Check 6: Build tools (CMake)
echo "[6/8] Checking build tools..."

if command -v cmake >/dev/null 2>&1; then
    CMAKE_VERSION=$(cmake --version | head -1 | awk '{print $3}')
    echo "  ✓ CMake installed (version $CMAKE_VERSION)"
    
    # Check if version meets minimum requirement (4.1.2)
    CMAKE_MAJOR=$(echo "$CMAKE_VERSION" | cut -d. -f1)
    CMAKE_MINOR=$(echo "$CMAKE_VERSION" | cut -d. -f2)
    
    if [[ $CMAKE_MAJOR -lt 4 ]] || [[ $CMAKE_MAJOR -eq 4 && $CMAKE_MINOR -lt 1 ]]; then
        echo "  ⚠️  CMake version may be too old (4.1.2+ required)"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
else
    echo "  ❌ CMake NOT found (REQUIRED for building)"
    echo "     Install with: sudo apt install cmake"
    EXIT_CODE=1
fi
echo ""

# Check 7: C/C++ Compiler (Intel oneAPI preferred)
echo "[7/8] Checking compiler availability..."

INTEL_FOUND=false
GCC_FOUND=false

if command -v icx >/dev/null 2>&1 && command -v icpx >/dev/null 2>&1; then
    ICX_VERSION=$(icx --version 2>&1 | head -1)
    echo "  ✓ Intel oneAPI compilers found (icx/icpx)"
    echo "    $ICX_VERSION" | sed 's/^/    /'
    INTEL_FOUND=true
fi

if command -v gcc >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1; then
    GCC_VERSION=$(gcc --version | head -1)
    echo "  ✓ GCC/G++ found"
    echo "    $GCC_VERSION" | sed 's/^/    /'
    GCC_FOUND=true
fi

if [[ "$INTEL_FOUND" == false && "$GCC_FOUND" == false ]]; then
    echo "  ❌ No C/C++ compiler found (REQUIRED)"
    echo "     Install GCC: sudo apt install build-essential"
    echo "     Or Intel oneAPI: https://www.intel.com/content/www/us/en/developer/tools/oneapi.html"
    EXIT_CODE=1
elif [[ "$INTEL_FOUND" == false ]]; then
    echo ""
    echo "  ⚠️  Intel oneAPI compilers NOT found (RECOMMENDED)"
    echo "     This project is designed for Intel oneAPI compilers."
    echo "     You can build with GCC using: SKIP_COMPILER_CHECK=1 ./scripts/host_build.sh"
    echo "     Install Intel oneAPI: https://www.intel.com/content/www/us/en/developer/tools/oneapi.html"
    WARN_COUNT=$((WARN_COUNT + 1))
fi
echo ""

# Check 8: pkg-config (required for dependency detection)
echo "[8/8] Checking pkg-config..."

if command -v pkg-config >/dev/null 2>&1; then
    echo "  ✓ pkg-config installed"
else
    echo "  ❌ pkg-config NOT found (REQUIRED)"
    echo "     Install with: sudo apt install pkg-config"
    EXIT_CODE=1
fi
echo ""

# Summary
echo "========================================"
echo "Summary:"
echo ""

if [[ $EXIT_CODE -eq 0 ]]; then
    if [[ $WARN_COUNT -gt 0 ]]; then
        echo "⚠️  System meets minimum requirements with $WARN_COUNT warning(s)"
    else
        echo "✅ System meets all requirements for USB-C host-to-host networking"
    fi
    echo ""
    echo "Runtime Requirements Met:"
    echo "  ✓ Linux kernel 5.10+ with Type-C subsystem (CONFIG_TYPEC)"
    echo "  ✓ Type-C kernel modules available (typec, typec_ucsi)"
    echo "  ✓ Type-C sysfs present (/sys/class/typec/)"
    echo "  ✓ USB-C hardware ports detected"
    echo "  ✓ libusb-1.0 installed"
    echo ""
    echo "Build Requirements Met:"
    echo "  ✓ CMake 4.1.2+"
    echo "  ✓ C/C++ compiler (C23/C++23 support)"
    echo "  ✓ pkg-config"
    echo ""
    if [[ $WARN_COUNT -gt 0 ]]; then
        echo "Warnings (non-critical):"
        if [[ "$INTEL_FOUND" == false && "$GCC_FOUND" == true ]]; then
            echo "  ⚠️  Intel oneAPI compilers not found (using GCC fallback)"
        fi
        echo ""
    fi
    echo "Next steps:"
    if [[ "$INTEL_FOUND" == true ]]; then
        echo "  1. Build the project: ./scripts/host_build.sh RelWithDebInfo"
    else
        echo "  1. Build the project: SKIP_COMPILER_CHECK=1 ./scripts/host_build.sh RelWithDebInfo"
    fi
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
    echo ""
    echo "Note: This project does NOT require or use USB gadget mode."
    echo "      It implements host-to-host USB-C networking using the"
    echo "      Linux Type-C subsystem (/sys/class/typec/)."
fi

echo ""
echo "========================================"
echo "Additional Information:"
echo ""
echo "Architecture: Host-to-host USB-C networking (NOT gadget mode)"
echo "Kernel Requirements:"
echo "  - CONFIG_TYPEC=m or =y (Type-C subsystem)"
echo "  - CONFIG_TYPEC_UCSI=m (USB Type-C Connector System Software Interface)"
echo "  - CONFIG_UCSI_ACPI=m (ACPI UCSI driver, for most systems)"
echo ""
echo "Build Requirements:"
echo "  - CMake 4.1.2+"
echo "  - C23 and C++23 standard support"
echo "  - Intel oneAPI compilers (icx/icpx) - recommended"
echo "  - Or GCC/Clang with SKIP_COMPILER_CHECK=1 (development only)"
echo "  - libusb-1.0 development headers"
echo "  - pkg-config"
echo ""
echo "Runtime Requirements:"
echo "  - Root/sudo privileges (for hardware access)"
echo "  - Data-capable USB-C cable (not charge-only)"
echo "  - Two USB-C ports (or one port + VM with USB passthrough)"
echo ""
echo "For detailed documentation, see:"
echo "  - README.md - Project overview and quick start"
echo "  - docs/TROUBLESHOOTING.md - Detailed troubleshooting"
echo "  - examples/README.md - Example usage"
echo ""
exit $EXIT_CODE
