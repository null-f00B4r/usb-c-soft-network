#!/usr/bin/env bash
set -euo pipefail

# USB-C Port Identification Tool
# Supports two detection methods:
#   1. Type-C sysfs (default) - works for host-to-host connections
#   2. libusb device enumeration (fallback) - requires gadget mode

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

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "⚠️  WARNING: Not running as root (sudo)" | tee -a "$DEBUG_FILE"
    echo ""
    echo "Root privileges are recommended for accurate port detection."
    echo "Without root access:"
    echo "  - Some sysfs attributes may be inaccessible"
    echo "  - USB device enumeration may show limited information"
    echo "  - Detection accuracy may be reduced"
    echo ""
    read -p "Continue in non-root mode (might not be accurate)? (y/N): " response
    response=${response,,}
    if [[ "$response" != "y" ]]; then
        echo "Aborted. Please run with: sudo $0"
        exit 1
    fi
    echo "" | tee -a "$DEBUG_FILE"
    echo "⚠️  User chose to continue without root privileges" >> "$DEBUG_FILE"
    echo "" >> "$DEBUG_FILE"
fi

# Determine which detection method to use
USE_SYSFS=true
USE_LIBUSB=false

if [[ ! -d "$TYPEC_PATH" ]]; then
    echo "⚠️  Type-C subsystem not found at $TYPEC_PATH" | tee -a "$DEBUG_FILE"
    echo "Will fall back to libusb device enumeration method." | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    USE_SYSFS=false
    USE_LIBUSB=true
elif [[ -z "$(ls -d "$TYPEC_PATH"/port[0-9]* 2>/dev/null)" ]]; then
    echo "⚠️  No Type-C ports found in $TYPEC_PATH" | tee -a "$DEBUG_FILE"
    echo "Will fall back to libusb device enumeration method." | tee -a "$DEBUG_FILE"
    echo "" | tee -a "$DEBUG_FILE"
    USE_SYSFS=false
    USE_LIBUSB=true
fi

# For libusb fallback, check if binary exists
if [[ "$USE_LIBUSB" == true ]] && [[ ! -x "$USB_NET_BIN" ]]; then
    echo "Error: usb-c-net binary not found at: $USB_NET_BIN" | tee -a "$DEBUG_FILE"
    echo "Please build the project first: ./scripts/host_build.sh" | tee -a "$DEBUG_FILE"
    exit 1
fi

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

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
    echo "This method detects USB device enumeration changes."
    echo "It requires one end to be in USB gadget/device mode."
    echo ""

    TEMP_DIR=$(mktemp -d)
    BEFORE_LIST="${TEMP_DIR}/before.txt"
    AFTER_LIST="${TEMP_DIR}/after.txt"

    # Step 1: Ask user to connect device
    echo "Step 1: Please connect a device to the target USB-C port."
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
    echo "Step 2: Please disconnect the USB-C cable now."
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

    echo "=== Identified USB-C Port ==="
    echo ""
    echo "The target USB-C port is:"
    echo "  Bus:     $BUS"
    echo "  Device:  $DEVICE"
    echo "  Speed:   ${SPEED} Mbps"
    echo "  ID:      $VENDOR_PRODUCT"
    echo "  Info:    $DESCRIPTION"
    echo ""

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

DETECTION_METHOD=libusb
USB_BUS=$BUS
USB_DEVICE=$DEVICE
USB_SPEED=$SPEED
USB_VENDOR_PRODUCT=$VENDOR_PRODUCT
USB_DESCRIPTION="$DESCRIPTION"

# Full device path for Docker passthrough
USB_DEVICE_PATH=/dev/bus/usb/$BUS/$DEVICE

# For use in scripts:
# source $OUTPUT_FILE
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
    detect_via_libusb
    exit $?
fi

# Should never reach here
echo "Error: No detection method available" | tee -a "$DEBUG_FILE"
exit 1
echo "========================================" | tee -a "$DEBUG_FILE"
echo "DEBUG PAUSE: Current state saved to: $DEBUG_FILE" | tee -a "$DEBUG_FILE"
echo "Please disconnect the USB-C cable now." | tee -a "$DEBUG_FILE"
echo "Press ENTER when ready to rescan..." | tee -a "$DEBUG_FILE"
read -p "" pause
echo "Resuming scan..." | tee -a "$DEBUG_FILE"
echo "" | tee -a "$DEBUG_FILE"

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
