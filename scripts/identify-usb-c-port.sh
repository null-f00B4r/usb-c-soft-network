#!/usr/bin/env bash
set -euo pipefail

# USB-C Port Identification Tool
# Supports two detection methods:
#   1. Type-C sysfs (default) - works for host-to-host connections
#   2. libusb device enumeration (fallback) - requires gadget mode ONLY FOR DETECTION
#
# IMPORTANT: This script identifies which USB-C port to use.
# The detection methods (especially libusb) may require gadget-mode devices,
# but the actual USB-C networking implementation does NOT require gadget mode.
# See docs/how-to-select-port.md for clarification.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
USB_NET_BIN="${PROJECT_ROOT}/build/usb-c-net"
OUTPUT_FILE="${PROJECT_ROOT}/target_usb_c_port.env"
DEBUG_FILE="${PROJECT_ROOT}/find-usb-port-debug.out"
TYPEC_PATH="/sys/class/typec"

# Initialize debug file
echo "=== USB-C Port Identification Debug Log ===" > "$DEBUG_FILE"
echo "Started: $(date)" >> "$DEBUG_FILE"
echo "" >> "$DEBUG_FILE"

echo "=== USB-C Port Identification Tool ==="
echo ""

# Check for root privileges (required for module loading and sysfs access)
if [[ $EUID -ne 0 ]]; then
    echo "❌ ERROR: Root privileges required" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    echo "This tool requires root access to:" | tee -a "$DEBUG_FILE"
    echo "  - Load Type-C kernel modules" | tee -a "$DEBUG_FILE"
    echo "  - Access Type-C sysfs attributes in /sys/class/typec/" | tee -a "$DEBUG_FILE"
    echo "  - Detect USB-C port connections accurately" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    echo "Please run with: sudo $0" | tee -a "$DEBUG_FILE"
    exit 1
fi

# Check and load required Type-C kernel modules
echo "Checking Type-C kernel module support..." | tee -a "$DEBUG_FILE"

REQUIRED_MODULES=("typec" "typec_ucsi")
MISSING_MODULES=()
LOADED_MODULES=()

for module in "${REQUIRED_MODULES[@]}"; do
    if lsmod | grep -q "^${module} "; then
        echo "  ✓ Module '$module' already loaded" | tee -a "$DEBUG_FILE"
        LOADED_MODULES+=("$module")
    elif modinfo "$module" &>/dev/null; then
        echo "  → Loading module '$module'..." | tee -a "$DEBUG_FILE"
        if modprobe "$module" 2>> "$DEBUG_FILE"; then
            echo "  ✓ Module '$module' loaded successfully" | tee -a "$DEBUG_FILE"
            LOADED_MODULES+=("$module")
        else
            echo "  ⚠️  Failed to load module '$module' (see debug log)" | tee -a "$DEBUG_FILE"
        fi
    else
        echo "  ✗ Module '$module' not available in kernel" | tee -a "$DEBUG_FILE"
        MISSING_MODULES+=("$module")
    fi
done

# Give kernel time to initialize Type-C subsystem
if [[ ${#LOADED_MODULES[@]} -gt 0 ]]; then
    echo "Waiting for Type-C subsystem initialization..." | tee -a "$DEBUG_FILE"
    sleep 2
fi

echo "" | tee -a "$DEBUG_FILE"

# Determine which detection method to use
USE_SYSFS=true
USE_LIBUSB=false

if [[ ! -d "$TYPEC_PATH" ]]; then
    echo "⚠️  Type-C subsystem not found at $TYPEC_PATH" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    
    if [[ ${#MISSING_MODULES[@]} -gt 0 ]]; then
        echo "⚠️  WARNING: Type-C kernel modules not available:" | tee -a "$DEBUG_FILE"
        for module in "${MISSING_MODULES[@]}"; do
            echo "  - $module" | tee -a "$DEBUG_FILE"
        done
        echo "" | tee -a "$DEBUG_FILE"
        echo "This system's kernel does not have Type-C support compiled." | tee -a "$DEBUG_FILE"
        echo "" | tee -a "$DEBUG_FILE"
        echo "Automatic sysfs detection is not possible, but you can:" | tee -a "$DEBUG_FILE"
        echo "  1. Manually configure the USB-C port (recommended)" | tee -a "$DEBUG_FILE"
        echo "  2. Use a kernel with CONFIG_TYPEC=m or CONFIG_TYPEC=y" | tee -a "$DEBUG_FILE"
        echo "  3. Try libusb enumeration as a fallback" | tee -a "$DEBUG_FILE"
        echo "" | tee -a "$DEBUG_FILE"
        offer_manual_configuration
    else
        echo "Type-C modules are loaded but sysfs not present." | tee -a "$DEBUG_FILE"
        echo "This may indicate no USB-C controllers are detected." | tee -a "$DEBUG_FILE"
        echo "" | tee -a "$DEBUG_FILE"
        echo "Checking for USB-C hardware..." | tee -a "$DEBUG_FILE"
        if lspci | grep -qi "usb.*type-c\|thunderbolt"; then
            echo "  Found potential USB-C/Thunderbolt controller" | tee -a "$DEBUG_FILE"
        else
            echo "  No USB-C controllers detected by lspci" | tee -a "$DEBUG_FILE"
        fi
        echo "" | tee -a "$DEBUG_FILE"
    fi
    
    USE_SYSFS=false
    USE_LIBUSB=true
elif [[ -z "$(ls -d "$TYPEC_PATH"/port[0-9]* 2>/dev/null)" ]]; then
    echo "⚠️  No Type-C ports found in $TYPEC_PATH" | tee -a "$DEBUG_FILE"
    echo "Type-C subsystem is loaded but no ports are detected." | tee -a "$DEBUG_FILE"
    echo "This system may not have USB-C ports or the controller is not recognized." | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    USE_SYSFS=false
    USE_LIBUSB=true
fi

# For libusb fallback, check if binary exists but warn about limitations
if [[ "$USE_LIBUSB" == true ]]; then
    echo "⚠️  WARNING: Falling back to libusb enumeration method" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    echo "This DETECTION method requires USB gadget mode for the test device." | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    echo "NOTE: This is ONLY for port identification. The actual USB-C networking" | tee -a "$DEBUG_FILE"
    echo "implementation does NOT require gadget mode. This is a detection-only" | tee -a "$DEBUG_FILE"
    echo "limitation. See docs/how-to-select-port.md for clarification." | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    
    if [[ ! -x "$USB_NET_BIN" ]]; then
        echo "Error: usb-c-net binary not found at: $USB_NET_BIN" | tee -a "$DEBUG_FILE"
        echo "Please build the project first: ./scripts/host_build.sh" | tee -a "$DEBUG_FILE"
        exit 1
    fi
fi

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

#############################################################################
# Manual Configuration Helper
#############################################################################

offer_manual_configuration() {
    echo ""
    echo "You can manually configure your USB-C port instead:"
    echo ""
    echo "1. Copy the example configuration:"
    echo "   cp target_usb_c_port.env.example target_usb_c_port.env"
    echo ""
    echo "2. Edit the file and follow the instructions:"
    echo "   nano target_usb_c_port.env"
    echo ""
    echo "3. For detailed guidance on finding your port, see:"
    echo "   docs/how-to-select-port.md"
    echo ""
    echo "Debug information saved to: $DEBUG_FILE"
    echo ""
    exit 1
}

#############################################################################
# METHOD 1: Type-C sysfs detection (default, works for host-to-host)
#############################################################################

detect_via_sysfs() {
    echo "=== Using Type-C sysfs Detection Method ===" | tee -a "$DEBUG_FILE"
    echo ""
    echo "This method detects physical cable connection via the Type-C subsystem."
    echo "It works even when both ends are USB hosts (no gadget mode needed)."
    echo ""

    # Function to list all Type-C ports and their status
    list_typec_ports() {
        local timestamp="$1"
        echo "=== Type-C Ports at $timestamp ===" >> "$DEBUG_FILE"
        
        for port in "$TYPEC_PATH"/port[0-9]*; do
            if [[ -d "$port" ]] && [[ ! "$port" =~ -partner$ ]]; then
                local portname=$(basename "$port")
                local data_role="unknown"
                local power_role="unknown"
                local vconn_source="unknown"
                local usb_power_delivery="unknown"
                local orientation="unknown"
                local number_of_altmodes="0"
                
                [[ -f "$port/data_role" ]] && data_role=$(cat "$port/data_role" 2>/dev/null) || data_role="unknown"
                [[ -f "$port/power_role" ]] && power_role=$(cat "$port/power_role" 2>/dev/null) || power_role="unknown"
                [[ -f "$port/vconn_source" ]] && vconn_source=$(cat "$port/vconn_source" 2>/dev/null) || vconn_source="unknown"
                [[ -f "$port/usb_power_delivery" ]] && usb_power_delivery=$(cat "$port/usb_power_delivery" 2>/dev/null) || usb_power_delivery="unknown"
                [[ -f "$port/orientation" ]] && orientation=$(cat "$port/orientation" 2>/dev/null) || orientation="unknown"
                if [[ -d "$port-partner" ]]; then
                    number_of_altmodes=$(ls -1d "$port-partner"/port*-partner.*/mode* 2>/dev/null | wc -l || echo "0")
                fi
                
                # Key indicator: check if partner exists (cable connected)
                local partner_status="not connected"
                if [[ -d "$port-partner" ]]; then
                    partner_status="CONNECTED"
                    # Try to get partner info
                    if [[ -f "$port-partner/identity" ]]; then
                        local identity=$(cat "$port-partner/identity" 2>/dev/null | tr '\n' ' ')
                        partner_status="CONNECTED ($identity)"
                    fi
                fi
                
                echo "$portname: $partner_status | data=$data_role power=$power_role orient=$orientation" >> "$DEBUG_FILE"
                echo "  Path: $port" >> "$DEBUG_FILE"
                
                # Also print to console
                printf "%-12s %-30s %-20s %-20s %-15s\n" \
                    "$portname" "$partner_status" "$data_role" "$power_role" "$orientation"
            fi
        done
        echo "" >> "$DEBUG_FILE"
    }

    echo "Available USB-C ports:"
    echo ""
    printf "%-12s %-30s %-20s %-20s %-15s\n" "Port" "Status" "Data Role" "Power Role" "Orientation"
    echo "----------- ----------------------------- ------------------- ------------------- --------------"

    list_typec_ports "initial scan"

    echo ""
    echo "Step 1: Current port states shown above."
    echo "Please ensure NO USB-C cable is connected to the target port."
    echo ""
    read -p "Press ENTER to scan BEFORE state: " _

    echo ""
    echo "Scanning Type-C ports (BEFORE state)..."
    BEFORE_STATE=$(mktemp)

    for port in "$TYPEC_PATH"/port[0-9]*; do
        if [[ -d "$port" ]] && [[ ! "$port" =~ -partner$ ]]; then
            portname=$(basename "$port")
            partner_exists="no"
            [[ -d "$port-partner" ]] && partner_exists="yes"
            echo "$portname:$partner_exists" >> "$BEFORE_STATE"
        fi
    done

    echo "BEFORE state:" | tee -a "$DEBUG_FILE"
    cat "$BEFORE_STATE" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"

    echo ""
    echo "Step 2: Now connect the USB-C cable to the target port."
    echo ""
    read -p "Press ENTER after connecting the cable: " _

    sleep 1  # Give kernel time to detect

    echo ""
    echo "Scanning Type-C ports (AFTER state)..."
    AFTER_STATE=$(mktemp)

    for port in "$TYPEC_PATH"/port[0-9]*; do
        if [[ -d "$port" ]] && [[ ! "$port" =~ -partner$ ]]; then
            portname=$(basename "$port")
            partner_exists="no"
            [[ -d "$port-partner" ]] && partner_exists="yes"
            echo "$portname:$partner_exists" >> "$AFTER_STATE"
        fi
    done

    echo "AFTER state:" | tee -a "$DEBUG_FILE"
    cat "$AFTER_STATE" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"

    echo ""
    echo "Analyzing changes..."
    echo "" | tee -a "$DEBUG_FILE"
    echo "=== ANALYSIS ===" >> "$DEBUG_FILE"

    # Find ports where partner state changed from "no" to "yes"
    CHANGED_PORT=""
    while IFS=: read -r port before_partner; do
        after_partner=$(grep "^$port:" "$AFTER_STATE" | cut -d: -f2)
        
        if [[ "$before_partner" == "no" && "$after_partner" == "yes" ]]; then
            CHANGED_PORT="$port"
            echo "Detected change: $port went from disconnected to connected" | tee -a "$DEBUG_FILE"
            break
        fi
    done < "$BEFORE_STATE"

    rm -f "$BEFORE_STATE" "$AFTER_STATE"

    if [[ -z "$CHANGED_PORT" ]]; then
        echo "Error: No Type-C port state change detected." | tee -a "$DEBUG_FILE"
        echo "" | tee -a "$DEBUG_FILE"
        echo "Possible reasons:" | tee -a "$DEBUG_FILE"
        echo "  1. Cable was already connected" | tee -a "$DEBUG_FILE"
        echo "  2. Cable doesn't have proper USB-C connectors" | tee -a "$DEBUG_FILE"
        echo "  3. Port doesn't support Type-C detection" | tee -a "$DEBUG_FILE"
        echo "" | tee -a "$DEBUG_FILE"
        
        if [[ -x "$USB_NET_BIN" ]]; then
            echo "Falling back to libusb device enumeration method..." | tee -a "$DEBUG_FILE"
            echo "" | tee -a "$DEBUG_FILE"
            return 1  # Signal to try fallback method
        else
            echo "Debug information saved to: $DEBUG_FILE" | tee -a "$DEBUG_FILE"
            exit 1
        fi
    fi

    # Get detailed info about the identified port
    PORT_PATH="$TYPEC_PATH/$CHANGED_PORT"

    DATA_ROLE=$(cat "$PORT_PATH/data_role" 2>/dev/null || echo "unknown")
    POWER_ROLE=$(cat "$PORT_PATH/power_role" 2>/dev/null || echo "unknown")
    ORIENTATION=$(cat "$PORT_PATH/orientation" 2>/dev/null || echo "unknown")
    
    # Try to find associated USB controller
    USB_CONTROLLER="unknown"
    if [[ -L "$PORT_PATH/device" ]]; then
        USB_CONTROLLER=$(readlink -f "$PORT_PATH/device" | grep -oP 'usb\d+' | head -1 || echo "unknown")
    fi

    echo ""
    echo "=== Identified USB-C Port ==="
    echo ""
    echo "The target USB-C port is: $CHANGED_PORT"
    echo "  Path: $PORT_PATH"
    echo "  Data Role: $DATA_ROLE"
    echo "  Power Role: $POWER_ROLE"
    echo "  Orientation: $ORIENTATION"
    [[ "$USB_CONTROLLER" != "unknown" ]] && echo "  USB Controller: $USB_CONTROLLER"
    echo ""

    # Ask for confirmation
    read -p "Is this correct? (Y/n): " response
    response=${response,,}

    if [[ "$response" != "y" && "$response" != "" ]]; then
        echo ""
        echo "Please try again."
        echo "Aborted by user." >> "$DEBUG_FILE"
        exit 1
    fi

    # Save configuration
    cat > "$OUTPUT_FILE" <<EOF
# Target USB-C Port Configuration
# Generated by identify-usb-c-port.sh (sysfs method) on $(date)
#
# This file identifies the USB-C port for networking via sysfs detection

DETECTION_METHOD=sysfs
TYPEC_PORT=$CHANGED_PORT
TYPEC_PORT_PATH=$PORT_PATH
TYPEC_DATA_ROLE=$DATA_ROLE
TYPEC_POWER_ROLE=$POWER_ROLE
TYPEC_ORIENTATION=$ORIENTATION
USB_CONTROLLER=$USB_CONTROLLER

# For monitoring connection state:
# cat $PORT_PATH-partner 2>/dev/null && echo "Connected" || echo "Disconnected"

# For use in scripts:
# source $OUTPUT_FILE
# if [[ -d \$TYPEC_PORT_PATH-partner ]]; then
#     echo "USB-C cable connected on \$TYPEC_PORT"
# fi
EOF

    echo ""
    echo "Configuration saved to: $OUTPUT_FILE"
    echo "Debug log saved to: $DEBUG_FILE"
    echo ""
    echo "You can monitor this port's connection state with:"
    echo "  watch -n 1 'ls -ld $PORT_PATH-partner 2>/dev/null || echo \"Not connected\"'"
    echo ""
    echo "Successfully identified target USB-C port!" | tee -a "$DEBUG_FILE"
    echo "Completed: $(date)" >> "$DEBUG_FILE"

    return 0
}

#############################################################################
# METHOD 2: libusb device enumeration (fallback, requires gadget mode)
#############################################################################

detect_via_libusb() {
    echo "=== Using libusb Device Enumeration Method ===" | tee -a "$DEBUG_FILE"
    echo ""
    echo "⚠️  DETECTION METHOD ONLY: This step requires a gadget-mode device."
    echo ""
    echo "This method detects USB device enumeration changes by comparing"
    echo "the USB device list before and after connection."
    echo ""
    echo "For detection, you can use:"
    echo "  • Android phone or tablet (native USB gadget support)"
    echo "  • Another Linux host configured as USB gadget"
    echo "  • USB device with gadget-mode capabilities"
    echo ""
    echo "IMPORTANT: This gadget mode is ONLY needed for this detection step."
    echo "The actual USB-C networking does NOT require gadget mode."
    echo ""

    TEMP_DIR=$(mktemp -d)
    BEFORE_LIST="${TEMP_DIR}/before.txt"
    AFTER_LIST="${TEMP_DIR}/after.txt"

    # Step 1: Ask user to connect device
    echo "Step 1: Connect a gadget-mode device to the target USB-C port."
    echo ""
    echo "Recommended test devices:"
    echo "  • Smartphone or tablet (Android, iOS with proper adapter)"
    echo "  • Another Linux host with g_ether module loaded"
    echo "  • Any device with USB gadget/device-mode support"
    echo ""
    read -p "Continue, device connected (Y/n): " response
    response=${response,,}
    if [[ "$response" != "y" && "$response" != "" ]]; then
        echo "Aborted by user."
        echo "Aborted by user at step 1." >> "$DEBUG_FILE"
        exit 1
    fi

    echo ""
    echo "Scanning USB devices (before state)..."
    echo "" >> "$DEBUG_FILE"
    echo "=== BEFORE STATE (device connected) ===" >> "$DEBUG_FILE"
    echo "Scan time: $(date)" >> "$DEBUG_FILE"
    echo "" >> "$DEBUG_FILE"

    "$USB_NET_BIN" 2>&1 | tee "$BEFORE_LIST" | tee -a "$DEBUG_FILE"

    # Extract device list from output
    grep "^[0-9]" "$BEFORE_LIST" > "${BEFORE_LIST}.devices" 2>/dev/null || true

    echo "" | tee -a "$DEBUG_FILE"
    echo "Found $(wc -l < "${BEFORE_LIST}.devices") devices in BEFORE state" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"

    # Step 2: Ask user to disconnect device
    echo ""
    echo "Step 2: Disconnect the gadget-mode device from the USB-C port."
    echo ""
    echo "This is only to detect which port changed state (for identification)."
    echo "The actual USB-C networking will not require this device."
    echo ""
    read -p "Continue, device disconnected (Y/n): " response
    response=${response,,}
    if [[ "$response" != "y" && "$response" != "" ]]; then
        echo "Aborted by user."
        echo "Aborted by user at step 2." >> "$DEBUG_FILE"
        exit 1
    fi

    echo ""
    echo "Scanning USB devices (after state)..."
    echo "" >> "$DEBUG_FILE"
    echo "=== AFTER STATE (device disconnected) ===" >> "$DEBUG_FILE"
    echo "Scan time: $(date)" >> "$DEBUG_FILE"
    echo "" >> "$DEBUG_FILE"

    "$USB_NET_BIN" 2>&1 | tee "$AFTER_LIST" | tee -a "$DEBUG_FILE"

    # Extract device list from output
    grep "^[0-9]" "$AFTER_LIST" > "${AFTER_LIST}.devices" 2>/dev/null || true

    echo "" | tee -a "$DEBUG_FILE"
    echo "Found $(wc -l < "${AFTER_LIST}.devices") devices in AFTER state" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"

    # Step 3: Compare the two lists
    echo ""
    echo "Analyzing differences..."
    echo "" | tee -a "$DEBUG_FILE"
    echo "=== ANALYSIS ===" >> "$DEBUG_FILE"
    echo "Comparing device lists..." >> "$DEBUG_FILE"
    echo "" >> "$DEBUG_FILE"

    # Find devices that disappeared
    CHANGED_DEVICES=$(comm -23 <(sort "${BEFORE_LIST}.devices") <(sort "${AFTER_LIST}.devices") 2>&1)

    echo "Devices that disappeared:" >> "$DEBUG_FILE"
    echo "$CHANGED_DEVICES" >> "$DEBUG_FILE"
    echo "" >> "$DEBUG_FILE"

    if [[ -z "$CHANGED_DEVICES" ]]; then
        echo "Error: No device changes detected." | tee -a "$DEBUG_FILE"
        echo "Please ensure you connected and then disconnected a device." | tee -a "$DEBUG_FILE"
        echo "" >> "$DEBUG_FILE"
        echo "Debug information has been saved to: $DEBUG_FILE" | tee -a "$DEBUG_FILE"
        exit 1
    fi

    # Get the first changed device
    IDENTIFIED_PORT=$(echo "$CHANGED_DEVICES" | head -n 1)

    # Parse the device information
    BUS=$(echo "$IDENTIFIED_PORT" | awk '{print $1}')
    DEVICE=$(echo "$IDENTIFIED_PORT" | awk '{print $2}')
    SPEED=$(echo "$IDENTIFIED_PORT" | awk '{print $3}')
    VENDOR_PRODUCT=$(echo "$IDENTIFIED_PORT" | awk '{print $4}')
    DESCRIPTION=$(echo "$IDENTIFIED_PORT" | awk '{$1=$2=$3=$4=$5=""; print $0}' | sed 's/^[ \t]*//')

    # Find the USB port path (sysfs) - this stays constant regardless of device number
    # The port path is like "1-4" or "2-1.3" and identifies the physical port
    USB_PORT_PATH=""
    for dev in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
        if [[ -f "$dev/busnum" && -f "$dev/devnum" ]]; then
            dev_bus=$(cat "$dev/busnum" 2>/dev/null)
            dev_num=$(cat "$dev/devnum" 2>/dev/null)
            # Match bus and device number (strip leading zeros for comparison)
            if [[ "$((10#$BUS))" == "$dev_bus" && "$((10#$DEVICE))" == "$dev_num" ]]; then
                USB_PORT_PATH=$(basename "$dev")
                echo "Found USB port path: $USB_PORT_PATH" >> "$DEBUG_FILE"
                break
            fi
        fi
    done

    # If we couldn't find it with device connected, try to identify from before list
    if [[ -z "$USB_PORT_PATH" ]]; then
        echo "Warning: Could not determine USB port path (device may have been disconnected too fast)" | tee -a "$DEBUG_FILE"
        echo "The USB port path is needed to identify the physical port consistently." | tee -a "$DEBUG_FILE"
        echo "" | tee -a "$DEBUG_FILE"
        
        # Try to find it from the before state by looking at what's now missing
        echo "Attempting to find port path from sysfs device list..." >> "$DEBUG_FILE"
        for dev in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
            if [[ -f "$dev/busnum" ]]; then
                dev_bus=$(cat "$dev/busnum" 2>/dev/null)
                if [[ "$((10#$BUS))" == "$dev_bus" ]]; then
                    echo "  Candidate port: $(basename $dev) on bus $dev_bus" >> "$DEBUG_FILE"
                fi
            fi
        done
    fi

    echo "=== Identified USB-C Port ==="
    echo ""
    echo "The target USB-C port is:"
    echo "  Bus:       $BUS"
    echo "  Device:    $DEVICE (at time of detection)"
    echo "  Port Path: ${USB_PORT_PATH:-unknown}"
    echo "  Speed:     ${SPEED} Mbps"
    echo "  ID:        $VENDOR_PRODUCT"
    echo "  Info:      $DESCRIPTION"
    echo ""
    
    if [[ -z "$USB_PORT_PATH" ]]; then
        echo "⚠️  WARNING: USB port path could not be determined."
        echo "   You may need to run identification again with the device connected longer,"
        echo "   or manually set USB_PORT_PATH in the config file."
        echo ""
    fi

    # Ask for confirmation
    read -p "Is this correct? (Y/n): " response
    response=${response,,}

    if [[ "$response" != "y" && "$response" != "" ]]; then
        echo ""
        echo "Please try again."
        exit 1
    fi

    # Save to file
    cat > "$OUTPUT_FILE" <<EOF
# Target USB-C Port Configuration
# Generated by identify-usb-c-port.sh (libusb method) on $(date)
#
# This file identifies the USB-C port to use for networking
# USB_PORT_PATH is the key - it identifies the physical port location

DETECTION_METHOD=libusb
USB_BUS=$BUS
USB_PORT_PATH=$USB_PORT_PATH
USB_SPEED=$SPEED
USB_VENDOR_PRODUCT=$VENDOR_PRODUCT
USB_DESCRIPTION="$DESCRIPTION"

# Note: USB_DEVICE number changes with each connection
# Use USB_PORT_PATH to identify the physical port consistently
# USB_DEVICE=$DEVICE (at time of detection, may change)

# Full device path pattern for this port
# Devices connected to this port will appear at: /sys/bus/usb/devices/$USB_PORT_PATH

# For use in scripts:
# source $OUTPUT_FILE
# Find current device on this port:
#   if [[ -d /sys/bus/usb/devices/\$USB_PORT_PATH ]]; then
#     devnum=\$(cat /sys/bus/usb/devices/\$USB_PORT_PATH/devnum)
#     echo "Device \$devnum on port \$USB_PORT_PATH"
#   fi
EOF

    echo ""
    echo "Configuration saved to: $OUTPUT_FILE"
    echo "Debug log saved to: $DEBUG_FILE"
    echo ""
    echo "You can now use this port information in other scripts:"
    echo "  source $OUTPUT_FILE"
    echo "  echo \"Using USB device at bus \$USB_BUS, device \$USB_DEVICE\""
    echo ""
    echo "For Docker passthrough:"
    echo "  docker run --device=/dev/bus/usb/$BUS/$DEVICE ..."
    echo ""
    echo "Successfully identified target USB-C port!" | tee -a "$DEBUG_FILE"
    echo "Completed: $(date)" >> "$DEBUG_FILE"

    return 0
}

#############################################################################
# Main execution
#############################################################################

if [[ "$USE_SYSFS" == true ]]; then
    if detect_via_sysfs; then
        exit 0
    fi
    # If sysfs detection failed and returned 1, try libusb fallback
    USE_LIBUSB=true
    echo ""
fi

if [[ "$USE_LIBUSB" == true ]]; then
    if detect_via_libusb; then
        exit 0
    fi
fi

# All automatic detection methods failed - offer manual configuration
echo "⚠️  Automatic detection failed on all methods." | tee -a "$DEBUG_FILE"
echo "" | tee -a "$DEBUG_FILE"
offer_manual_configuration

# Step 2: Ask user to disconnect device
echo ""
echo "Step 2: Device should now be disconnected."
echo ""
read -p "Continue, device disconnected (Y/n): " response
response=${response,,}
if [[ "$response" != "y" && "$response" != "" ]]; then
    echo "Aborted by user."
    echo "Aborted by user at step 2." >> "$DEBUG_FILE"
    exit 1
fi

echo ""
echo "Scanning USB devices (after state)..."
echo "" >> "$DEBUG_FILE"
echo "=== AFTER STATE (device disconnected) ===" >> "$DEBUG_FILE"
echo "Scan time: $(date)" >> "$DEBUG_FILE"
echo "" >> "$DEBUG_FILE"

"$USB_NET_BIN" 2>&1 | tee "$AFTER_LIST" | tee -a "$DEBUG_FILE"

# Extract device list from output
grep "^[0-9]" "$AFTER_LIST" > "${AFTER_LIST}.devices" 2>/dev/null || true

echo "" | tee -a "$DEBUG_FILE"
echo "Found $(wc -l < "${AFTER_LIST}.devices") devices in AFTER state" | tee -a "$DEBUG_FILE"
echo "" | tee -a "$DEBUG_FILE"
echo "Device list saved to: ${AFTER_LIST}.devices" | tee -a "$DEBUG_FILE"
echo "" | tee -a "$DEBUG_FILE"

# Show extracted device list
echo "Extracted device list:" | tee -a "$DEBUG_FILE"
cat "${AFTER_LIST}.devices" | tee -a "$DEBUG_FILE"
echo "" | tee -a "$DEBUG_FILE"

# Step 3: Compare the two lists
echo ""
echo "Analyzing differences..."
echo "" | tee -a "$DEBUG_FILE"
echo "=== ANALYSIS ===" >> "$DEBUG_FILE"
echo "Comparing device lists..." >> "$DEBUG_FILE"
echo "" >> "$DEBUG_FILE"

# Debug: show what we're comparing
echo "BEFORE devices:" >> "$DEBUG_FILE"
sort "${BEFORE_LIST}.devices" >> "$DEBUG_FILE"
echo "" >> "$DEBUG_FILE"
echo "AFTER devices:" >> "$DEBUG_FILE"
sort "${AFTER_LIST}.devices" >> "$DEBUG_FILE"
echo "" >> "$DEBUG_FILE"

# Find devices that disappeared
CHANGED_DEVICES=$(comm -23 <(sort "${BEFORE_LIST}.devices") <(sort "${AFTER_LIST}.devices") 2>&1)

echo "Devices that disappeared:" >> "$DEBUG_FILE"
echo "$CHANGED_DEVICES" >> "$DEBUG_FILE"
echo "" >> "$DEBUG_FILE"

if [[ -z "$CHANGED_DEVICES" ]]; then
    echo "Error: No device changes detected." | tee -a "$DEBUG_FILE"
    echo "Please ensure you connected and then disconnected a device." | tee -a "$DEBUG_FILE"
    echo "" >> "$DEBUG_FILE"
    echo "Debug information has been saved to: $DEBUG_FILE" | tee -a "$DEBUG_FILE"
    exit 1
fi

# Count changed devices
NUM_CHANGED=$(echo "$CHANGED_DEVICES" | wc -l)

echo "Number of changed devices: $NUM_CHANGED" >> "$DEBUG_FILE"
echo "" >> "$DEBUG_FILE"

if [[ $NUM_CHANGED -gt 1 ]]; then
    echo "Warning: Multiple devices changed state:" | tee -a "$DEBUG_FILE"
    echo "$CHANGED_DEVICES" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    echo "This could indicate:" | tee -a "$DEBUG_FILE"
    echo "  - A USB hub was connected/disconnected" | tee -a "$DEBUG_FILE"
    echo "  - Multiple devices were affected" | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    echo "Proceeding with the first detected change..." | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
fi

# Get the first changed device
IDENTIFIED_PORT=$(echo "$CHANGED_DEVICES" | head -n 1)

echo "Selected device for identification:" >> "$DEBUG_FILE"
echo "$IDENTIFIED_PORT" >> "$DEBUG_FILE"
echo "" >> "$DEBUG_FILE"

# Parse the device information
BUS=$(echo "$IDENTIFIED_PORT" | awk '{print $1}')
DEVICE=$(echo "$IDENTIFIED_PORT" | awk '{print $2}')
SPEED=$(echo "$IDENTIFIED_PORT" | awk '{print $3}')
VENDOR_PRODUCT=$(echo "$IDENTIFIED_PORT" | awk '{print $4}')
DESCRIPTION=$(echo "$IDENTIFIED_PORT" | awk '{$1=$2=$3=$4=$5=""; print $0}' | sed 's/^[ \t]*//')

echo "=== Identified USB-C Port ==="
echo ""
echo "The target USB-C port is:"
echo "  Bus:     $BUS"
echo "  Device:  $DEVICE"
echo "  Speed:   ${SPEED} Mbps"
echo "  ID:      $VENDOR_PRODUCT"
echo "  Info:    $DESCRIPTION"
echo ""

# Step 4: Ask for confirmation
read -p "Is this correct? (Y/n): " response
response=${response,,}

if [[ "$response" != "y" && "$response" != "" ]]; then
    echo ""
    echo "Please try again."
    exit 1
fi

# Step 5: Save to file
cat > "$OUTPUT_FILE" <<EOF
# Target USB-C Port Configuration
# Generated by identify-usb-c-port.sh on $(date)
#
# This file identifies the USB-C port to use for networking

USB_BUS=$BUS
USB_DEVICE=$DEVICE
USB_SPEED=$SPEED
USB_VENDOR_PRODUCT=$VENDOR_PRODUCT
USB_DESCRIPTION="$DESCRIPTION"

# Full device path for Docker passthrough
USB_DEVICE_PATH=/dev/bus/usb/$BUS/$DEVICE

# For use in scripts:
# source target_usb_c_port.env
# docker run --device=\$USB_DEVICE_PATH ...
EOF

echo ""
echo "Configuration saved to: $OUTPUT_FILE"
echo "Debug log saved to: $DEBUG_FILE"
echo ""
echo "You can now use this port information in other scripts:"
echo "  source $OUTPUT_FILE"
echo "  echo \"Using USB device at bus \$USB_BUS, device \$USB_DEVICE\""
echo ""
echo "For Docker passthrough:"
echo "  docker run --device=/dev/bus/usb/$BUS/$DEVICE ..."
echo ""
echo "Successfully identified target USB-C port!" | tee -a "$DEBUG_FILE"
echo "Completed: $(date)" >> "$DEBUG_FILE"
exit 0
