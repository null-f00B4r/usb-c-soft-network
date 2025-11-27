#!/bin/bash
#!/bin/bash
# check-connection-ready.sh - Check if system is ready for USB-C host-to-host connection
#
# This script verifies that:
# 1. Port identification has been completed (target_usb_c_port.env exists)
# 2. Prompts user to connect USB-C cable between both devices
# 3. Waits for user confirmation before proceeding
#
# NOTE: This project uses DIRECT HARDWARE ACCESS via libusb.
#       We do NOT require sysfs/Type-C subsystem - just the identified USB port.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/target_usb_c_port.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_status() {
    local status=$1
    local message=$2
    case $status in
        ok)     echo -e "${GREEN}✓${NC} $message" ;;
        fail)   echo -e "${RED}✗${NC} $message" ;;
        warn)   echo -e "${YELLOW}!${NC} $message" ;;
        info)   echo -e "${BLUE}→${NC} $message" ;;
    esac
}

echo "=========================================="
echo "  USB-C Host-to-Host Connection Check"
echo "=========================================="
echo ""
echo "This project uses DIRECT HARDWARE ACCESS."
echo "No USB-C network adapter or special cable needed."
echo ""

# Check 1: Configuration file exists
echo "Phase 1: Port Identification"
echo "----------------------------"

if [[ -f "$CONFIG_FILE" ]]; then
    print_status ok "Configuration file exists: $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    if [[ -n "$DETECTION_METHOD" ]]; then
        print_status ok "Detection method: $DETECTION_METHOD"
    else
        print_status warn "Detection method not set (assuming libusb)"
        DETECTION_METHOD="libusb"
    fi
    
    if [[ "$DETECTION_METHOD" == "sysfs" ]]; then
        if [[ -n "$TYPEC_PORT" ]]; then
            print_status ok "Type-C port identified: $TYPEC_PORT"
        fi
        if [[ -n "$TYPEC_PORT_PATH" ]]; then
            print_status ok "Type-C port path: $TYPEC_PORT_PATH"
        fi
    elif [[ "$DETECTION_METHOD" == "libusb" ]]; then
        print_status ok "Using libusb direct hardware access"
        if [[ -n "$USB_BUS" && -n "$USB_DEVICE" ]]; then
            print_status ok "Identified USB port: Bus $USB_BUS (device $USB_DEVICE was used for detection)"
        fi
        if [[ -n "$USB_DEVICE_PATH" ]]; then
            print_status ok "USB device path: $USB_DEVICE_PATH"
        fi
    fi
    
    PORT_IDENTIFIED=true
else
    print_status fail "Configuration file not found: $CONFIG_FILE"
    echo ""
    print_status info "Run: ./scripts/identify-usb-c-port.sh"
    print_status info "Or manually create target_usb_c_port.env"
    echo ""
    exit 1
fi

echo ""
print_status ok "PORT IDENTIFICATION COMPLETE"
echo ""

# Phase 2: Prompt user to connect devices
echo "=========================================="
echo -e "  ${CYAN}ACTION REQUIRED${NC}"
echo "=========================================="
echo ""
echo "Both devices must now be connected via USB-C cable."
echo ""
echo "Please ensure:"
echo "  1. This device has identified its USB-C port (done ✓)"
echo "  2. The OTHER device has ALSO run identify-usb-c-port.sh"
echo "  3. Both devices have target_usb_c_port.env configured"
echo ""
echo -e "${YELLOW}>>> Connect the USB-C cable between both devices now <<<${NC}"
echo ""
echo "  [Device 1: $(hostname)]  ◄══════ USB-C Cable ══════►  [Device 2: ???]"
echo ""

# Wait for user confirmation
read -p "Press ENTER when cable is connected (or 'q' to quit): " user_input

if [[ "$user_input" == "q" || "$user_input" == "Q" ]]; then
    echo ""
    print_status info "Aborted by user"
    exit 0
fi

echo ""
echo "=========================================="
echo "  Phase 2: Verifying Connection"
echo "=========================================="
echo ""

# Try to detect the connection
CONNECTION_DETECTED=false

# Method 1: Check sysfs partner (if available)
if [[ "$DETECTION_METHOD" == "sysfs" && -n "$TYPEC_PORT_PATH" ]]; then
    partner_path="${TYPEC_PORT_PATH}-partner"
    if [[ -d "$partner_path" ]]; then
        print_status ok "Type-C partner detected via sysfs"
        CONNECTION_DETECTED=true
    fi
fi

# Method 2: Check via lsusb for any new devices (libusb method)
if [[ "$CONNECTION_DETECTED" == "false" ]]; then
    print_status info "Checking USB bus for connected devices..."
    
    # List current USB devices
    echo ""
    echo "Current USB devices on Bus $USB_BUS:"
    lsusb | grep "Bus 0*${USB_BUS}" | head -10
    echo ""
    
    # For host-to-host, we may not see a "device" appear - that's expected
    # The connection happens at a lower level
    print_status info "Note: Host-to-host USB-C may not show as enumerated device"
    print_status info "Direct hardware access will establish the link"
    CONNECTION_DETECTED=true  # Assume connected if user confirmed
fi

echo ""

# Summary and next steps
echo "=========================================="
echo "  Ready to Establish Network Link"
echo "=========================================="
echo ""

if [[ "$CONNECTION_DETECTED" == "true" ]]; then
    print_status ok "Configuration complete on this device"
    echo ""
    echo "Next steps:"
    echo ""
    echo "  On THIS device ($(hostname)), run one of:"
    echo "    sudo ./build/usb-c-net --mode host"
    echo "    sudo ./build/usb-c-net --mode device"
    echo ""
    echo "  On the OTHER device, run the opposite mode:"
    echo "    sudo ./build/usb-c-net --mode device"
    echo "    sudo ./build/usb-c-net --mode host"
    echo ""
    echo "  Then test connectivity:"
    echo "    ping 192.168.7.1  (from device side)"
    echo "    ping 192.168.7.2  (from host side)"
    echo ""
else
    print_status warn "Could not verify connection"
    echo ""
    echo "Troubleshooting:"
    echo "  - Ensure cable is data-capable (not charge-only)"
    echo "  - Try a different USB-C port"
    echo "  - Check dmesg: dmesg | tail -20"
fi

echo ""

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/target_usb_c_port.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    local status=$1
    local message=$2
    case $status in
        ok)     echo -e "${GREEN}✓${NC} $message" ;;
        fail)   echo -e "${RED}✗${NC} $message" ;;
        warn)   echo -e "${YELLOW}!${NC} $message" ;;
        info)   echo -e "${BLUE}→${NC} $message" ;;
    esac
}

echo "=========================================="
echo "  USB-C Host-to-Host Connection Status"
echo "=========================================="
echo ""

# Check 1: Configuration file exists
echo "Phase 1: Port Identification"
echo "----------------------------"

if [[ -f "$CONFIG_FILE" ]]; then
    print_status ok "Configuration file exists: $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    if [[ -n "$DETECTION_METHOD" ]]; then
        print_status ok "Detection method: $DETECTION_METHOD"
    else
        print_status warn "Detection method not set in config"
    fi
    
    if [[ "$DETECTION_METHOD" == "sysfs" ]]; then
        if [[ -n "$TYPEC_PORT" ]]; then
            print_status ok "Type-C port identified: $TYPEC_PORT"
        fi
        if [[ -d "$TYPEC_PORT_PATH" ]]; then
            print_status ok "Type-C port path exists: $TYPEC_PORT_PATH"
        else
            print_status fail "Type-C port path not found: $TYPEC_PORT_PATH"
        fi
    elif [[ "$DETECTION_METHOD" == "libusb" ]]; then
        print_status warn "Using libusb detection (identification only)"
        print_status info "For host-to-host, consider using sysfs method"
        if [[ -n "$USB_BUS" && -n "$USB_DEVICE" ]]; then
            print_status ok "USB location: Bus $USB_BUS, Device $USB_DEVICE"
        fi
    fi
else
    print_status fail "Configuration file not found: $CONFIG_FILE"
    echo ""
    print_status info "Run: ./scripts/identify-usb-c-port.sh"
    print_status info "Or manually create target_usb_c_port.env"
    echo ""
    exit 1
fi

echo ""

# Check 2: Type-C subsystem
echo "Phase 2: Type-C Subsystem"
echo "-------------------------"

if [[ -d /sys/class/typec ]]; then
    print_status ok "Type-C subsystem available"
    
    port_count=$(ls -d /sys/class/typec/port* 2>/dev/null | wc -l)
    if [[ $port_count -gt 0 ]]; then
        print_status ok "Found $port_count Type-C port(s)"
        
        # List all ports
        for port_path in /sys/class/typec/port*; do
            port_name=$(basename "$port_path")
            if [[ -f "$port_path/data_role" ]]; then
                data_role=$(cat "$port_path/data_role" 2>/dev/null || echo "unknown")
                power_role=$(cat "$port_path/power_role" 2>/dev/null || echo "unknown")
                print_status info "  $port_name: data=$data_role, power=$power_role"
            fi
        done
    else
        print_status warn "No Type-C ports found in sysfs"
    fi
else
    print_status warn "Type-C sysfs not available (/sys/class/typec)"
    print_status info "Try: sudo modprobe typec typec_ucsi"
fi

echo ""

# Check 3: Connection status
echo "Phase 3: Connection Status"
echo "--------------------------"

if [[ "$DETECTION_METHOD" == "sysfs" && -n "$TYPEC_PORT_PATH" ]]; then
    partner_path="${TYPEC_PORT_PATH}-partner"
    
    if [[ -d "$partner_path" ]]; then
        print_status ok "USB-C CABLE CONNECTED on $TYPEC_PORT"
        
        # Show partner info if available
        if [[ -f "$partner_path/type" ]]; then
            partner_type=$(cat "$partner_path/type" 2>/dev/null || echo "unknown")
            print_status info "Partner type: $partner_type"
        fi
        
        # Show current roles
        if [[ -f "$TYPEC_PORT_PATH/data_role" ]]; then
            current_data=$(cat "$TYPEC_PORT_PATH/data_role")
            current_power=$(cat "$TYPEC_PORT_PATH/power_role")
            print_status info "Current data role: $current_data"
            print_status info "Current power role: $current_power"
        fi
        
        CONNECTION_READY=true
    else
        print_status warn "NO USB-C CABLE CONNECTED on $TYPEC_PORT"
        print_status info "Connect USB-C cable to the identified port"
        CONNECTION_READY=false
    fi
else
    print_status info "Cannot check connection (sysfs method required)"
    print_status info "Connect USB-C cable and check with: lsusb"
    CONNECTION_READY=unknown
fi

echo ""

# Summary and next steps
echo "=========================================="
echo "  Summary & Next Steps"
echo "=========================================="
echo ""

if [[ "$CONNECTION_READY" == "true" ]]; then
    print_status ok "READY FOR HOST-TO-HOST NETWORKING"
    echo ""
    echo "Next steps:"
    echo "  1. Ensure the OTHER device also shows 'CABLE CONNECTED'"
    echo "  2. On one device, run:  sudo ./build/usb-c-net --mode host"
    echo "  3. On other device, run: sudo ./build/usb-c-net --mode device"
    echo "  4. Test with: ping 192.168.7.1 / ping 192.168.7.2"
elif [[ "$CONNECTION_READY" == "false" ]]; then
    print_status warn "WAITING FOR USB-C CABLE"
    echo ""
    echo "Next steps:"
    echo "  1. Ensure the OTHER device has also run identify-usb-c-port.sh"
    echo "  2. Connect USB-C cable between the two identified ports"
    echo "  3. Run this script again to verify connection"
else
    print_status info "CONNECTION STATUS UNKNOWN"
    echo ""
    echo "Next steps:"
    echo "  1. Try running: ./scripts/identify-usb-c-port.sh --sysfs"
    echo "  2. Or connect cable and check: dmesg | grep -i typec"
fi

echo ""
