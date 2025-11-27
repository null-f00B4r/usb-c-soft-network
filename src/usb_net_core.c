// USB-C Software Network - Core USB Hardware Access Layer
// This implements direct USB communication without kernel gadget drivers
// Host-to-host USB-C networking using direct hardware access
//
// Supports two communication modes:
// 1. Standard libusb (requires one side to be USB device)
// 2. Raw communication (works with both sides as hosts)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <getopt.h>
#include <libusb-1.0/libusb.h>
#include "usb_raw_comm.h"

#define USB_TIMEOUT_MS 5000
#define USB_NET_MTU 1500
#define PACKET_MAGIC 0x55534243  // "USBC" in little-endian
#define MAX_SCAN_ATTEMPTS 30
#define SCAN_INTERVAL_MS 1000

// Packet types for our simple protocol
typedef enum {
    PKT_PING = 1,
    PKT_PONG = 2,
    PKT_DATA = 3,
    PKT_ACK  = 4
} packet_type_t;

// Simple packet header
typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint8_t  type;
    uint8_t  flags;
    uint16_t length;
    uint32_t seq;
} packet_header_t;

// Operating mode
typedef enum {
    MODE_NONE,
    MODE_HOST,
    MODE_DEVICE,
    MODE_RAW,    // Raw communication (no USB enumeration required)
    MODE_LIST    // Just list devices
} usb_net_mode_t;

// Configuration from env file
typedef struct {
    char detection_method[32];
    char typec_port[32];
    char typec_port_path[256];
    int usb_bus;
    char usb_port_path[32];      // Physical port path like "1-4" or "2-1.3"
    char usb_device_path[256];
} usb_net_config_t;

typedef struct {
    libusb_context *ctx;
    libusb_device_handle *dev_handle;
    uint8_t endpoint_in;
    uint8_t endpoint_out;
    int interface_num;
    usb_net_mode_t mode;
    usb_net_config_t config;
    uint32_t seq_num;
    raw_comm_ctx_t raw_ctx;      // Raw communication context
} usb_net_device_t;

// Initialize libusb and scan for USB-C devices
int usb_net_init(usb_net_device_t *device) {
    int ret;
    
    memset(device, 0, sizeof(usb_net_device_t));
    
    ret = libusb_init(&device->ctx);
    if (ret < 0) {
        fprintf(stderr, "Failed to initialize libusb: %s\n", libusb_error_name(ret));
        return -1;
    }
    
    libusb_set_option(device->ctx, LIBUSB_OPTION_LOG_LEVEL, LIBUSB_LOG_LEVEL_INFO);
    
    printf("USB-C Software Network initialized\n");
    printf("libusb initialized successfully\n");
    
    return 0;
}

// List all connected USB devices
void usb_net_list_devices(usb_net_device_t *device) {
    libusb_device **devs;
    ssize_t cnt;
    int i;
    
    cnt = libusb_get_device_list(device->ctx, &devs);
    if (cnt < 0) {
        fprintf(stderr, "Failed to get device list\n");
        return;
    }
    
    printf("\nFound %zd USB devices:\n", cnt);
    printf("%-4s %-6s %-6s %-8s %-8s %-15s %s\n", 
           "Bus", "Device", "Speed", "Vendor", "Product", "Current State", "Description");
    printf("%-4s %-6s %-6s %-8s %-8s %-15s %s\n",
           "---", "------", "-----", "------", "-------", "-------------", "-----------");
    
    for (i = 0; i < cnt; i++) {
        libusb_device *dev = devs[i];
        struct libusb_device_descriptor desc;
        
        if (libusb_get_device_descriptor(dev, &desc) == 0) {
            const char *speed_str = "Unknown";
            switch (libusb_get_device_speed(dev)) {
                case LIBUSB_SPEED_LOW: speed_str = "1.5"; break;
                case LIBUSB_SPEED_FULL: speed_str = "12"; break;
                case LIBUSB_SPEED_HIGH: speed_str = "480"; break;
                case LIBUSB_SPEED_SUPER: speed_str = "5000"; break;
                case LIBUSB_SPEED_SUPER_PLUS: speed_str = "10000"; break;
            }
            
            libusb_device_handle *h = NULL;
            char product[256] = "Unknown";
            const char *state = "Unknown";
            
            int open_result = libusb_open(dev, &h);
            if (open_result == 0) {
                state = "Connected";
                libusb_get_string_descriptor_ascii(h, desc.iProduct, 
                    (unsigned char*)product, sizeof(product));
                libusb_close(h);
            } else if (open_result == LIBUSB_ERROR_ACCESS) {
                state = "Connected";  // Device exists but permission denied
            } else if (open_result == LIBUSB_ERROR_NO_DEVICE) {
                state = "Not Connected";
            }
            
            printf("%03d  %03d    %-6s %04x:%04x %-15s %s\n",
                   libusb_get_bus_number(dev),
                   libusb_get_device_address(dev),
                   speed_str,
                   desc.idVendor,
                   desc.idProduct,
                   state,
                   product);
        }
    }
    
    libusb_free_device_list(devs, 1);
}

// Open a specific USB device for communication
int usb_net_open_device(usb_net_device_t *device, uint16_t vendor_id, uint16_t product_id) {
    device->dev_handle = libusb_open_device_with_vid_pid(device->ctx, vendor_id, product_id);
    
    if (!device->dev_handle) {
        fprintf(stderr, "Cannot open device %04x:%04x\n", vendor_id, product_id);
        return -1;
    }
    
    printf("Opened USB device %04x:%04x\n", vendor_id, product_id);
    
    // Detach kernel driver if active
    if (libusb_kernel_driver_active(device->dev_handle, 0) == 1) {
        printf("Kernel driver is active, detaching...\n");
        if (libusb_detach_kernel_driver(device->dev_handle, 0) != 0) {
            fprintf(stderr, "Could not detach kernel driver\n");
        }
    }
    
    // Claim interface 0
    int ret = libusb_claim_interface(device->dev_handle, 0);
    if (ret < 0) {
        fprintf(stderr, "Cannot claim interface: %s\n", libusb_error_name(ret));
        libusb_close(device->dev_handle);
        device->dev_handle = NULL;
        return -1;
    }
    
    device->interface_num = 0;
    
    // Find bulk endpoints
    struct libusb_config_descriptor *config;
    libusb_get_active_config_descriptor(libusb_get_device(device->dev_handle), &config);
    
    if (config) {
        const struct libusb_interface *iface = &config->interface[0];
        if (iface->num_altsetting > 0) {
            const struct libusb_interface_descriptor *iface_desc = &iface->altsetting[0];
            
            for (int i = 0; i < iface_desc->bNumEndpoints; i++) {
                const struct libusb_endpoint_descriptor *ep = &iface_desc->endpoint[i];
                
                if ((ep->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) == LIBUSB_TRANSFER_TYPE_BULK) {
                    if (ep->bEndpointAddress & LIBUSB_ENDPOINT_IN) {
                        device->endpoint_in = ep->bEndpointAddress;
                        printf("Found bulk IN endpoint: 0x%02x\n", device->endpoint_in);
                    } else {
                        device->endpoint_out = ep->bEndpointAddress;
                        printf("Found bulk OUT endpoint: 0x%02x\n", device->endpoint_out);
                    }
                }
            }
        }
        libusb_free_config_descriptor(config);
    }
    
    return 0;
}

// Send data over USB
int usb_net_send(usb_net_device_t *device, const uint8_t *data, int len) {
    int transferred;
    int ret;
    
    if (!device->dev_handle || !device->endpoint_out) {
        fprintf(stderr, "Device not opened or no OUT endpoint\n");
        return -1;
    }
    
    ret = libusb_bulk_transfer(device->dev_handle, device->endpoint_out,
                                (unsigned char*)data, len, &transferred, USB_TIMEOUT_MS);
    
    if (ret < 0) {
        fprintf(stderr, "Bulk write error: %s\n", libusb_error_name(ret));
        return -1;
    }
    
    return transferred;
}

// Receive data over USB
int usb_net_recv(usb_net_device_t *device, uint8_t *buffer, int max_len) {
    int transferred;
    int ret;
    
    if (!device->dev_handle || !device->endpoint_in) {
        fprintf(stderr, "Device not opened or no IN endpoint\n");
        return -1;
    }
    
    ret = libusb_bulk_transfer(device->dev_handle, device->endpoint_in,
                                buffer, max_len, &transferred, USB_TIMEOUT_MS);
    
    if (ret < 0 && ret != LIBUSB_ERROR_TIMEOUT) {
        fprintf(stderr, "Bulk read error: %s\n", libusb_error_name(ret));
        return -1;
    }
    
    return transferred;
}

// Cleanup
void usb_net_cleanup(usb_net_device_t *device) {
    if (device->dev_handle) {
        libusb_release_interface(device->dev_handle, device->interface_num);
        libusb_close(device->dev_handle);
        device->dev_handle = NULL;
    }
    
    if (device->ctx) {
        libusb_exit(device->ctx);
        device->ctx = NULL;
    }
    
    printf("USB-C Software Network cleaned up\n");
}

// Load configuration from env file
int load_config(usb_net_device_t *device, const char *config_path) {
    FILE *fp;
    char line[512];
    char *key, *value;
    
    fp = fopen(config_path, "r");
    if (!fp) {
        fprintf(stderr, "Warning: Cannot open config file: %s\n", config_path);
        return -1;
    }
    
    printf("Loading config from: %s\n", config_path);
    
    while (fgets(line, sizeof(line), fp)) {
        // Skip comments and empty lines
        if (line[0] == '#' || line[0] == '\n') continue;
        
        // Remove trailing newline
        line[strcspn(line, "\n")] = 0;
        
        // Parse KEY=VALUE
        key = strtok(line, "=");
        value = strtok(NULL, "");
        
        if (!key || !value) continue;
        
        // Remove quotes from value if present
        if (value[0] == '"') {
            value++;
            value[strlen(value)-1] = '\0';
        }
        
        if (strcmp(key, "DETECTION_METHOD") == 0) {
            strncpy(device->config.detection_method, value, sizeof(device->config.detection_method)-1);
        } else if (strcmp(key, "TYPEC_PORT") == 0) {
            strncpy(device->config.typec_port, value, sizeof(device->config.typec_port)-1);
        } else if (strcmp(key, "TYPEC_PORT_PATH") == 0) {
            strncpy(device->config.typec_port_path, value, sizeof(device->config.typec_port_path)-1);
        } else if (strcmp(key, "USB_BUS") == 0) {
            device->config.usb_bus = atoi(value);
        } else if (strcmp(key, "USB_PORT_PATH") == 0) {
            strncpy(device->config.usb_port_path, value, sizeof(device->config.usb_port_path)-1);
        } else if (strcmp(key, "USB_DEVICE_PATH") == 0) {
            strncpy(device->config.usb_device_path, value, sizeof(device->config.usb_device_path)-1);
        }
    }
    
    fclose(fp);
    
    printf("Config loaded: method=%s, bus=%d, port_path=%s\n", 
           device->config.detection_method, device->config.usb_bus,
           device->config.usb_port_path[0] ? device->config.usb_port_path : "(not set)");
    
    return 0;
}

// Attempt Type-C data role swap via sysfs
int typec_role_swap(usb_net_device_t *device, const char *role) {
    char path[512];
    int fd;
    
    if (strlen(device->config.typec_port_path) == 0) {
        printf("No Type-C port path configured, skipping role swap\n");
        return -1;
    }
    
    snprintf(path, sizeof(path), "%s/data_role", device->config.typec_port_path);
    
    fd = open(path, O_WRONLY);
    if (fd < 0) {
        printf("Cannot open %s for role swap: %s\n", path, strerror(errno));
        return -1;
    }
    
    if (write(fd, role, strlen(role)) < 0) {
        printf("Role swap to '%s' failed: %s\n", role, strerror(errno));
        close(fd);
        return -1;
    }
    
    close(fd);
    printf("Type-C role swap to '%s' successful\n", role);
    return 0;
}

// Find and open a USB device on the specified bus with bulk endpoints
int find_peer_device(usb_net_device_t *device) {
    libusb_device **devs;
    ssize_t cnt;
    int target_bus = device->config.usb_bus;
    const char *target_port_path = device->config.usb_port_path;
    
    cnt = libusb_get_device_list(device->ctx, &devs);
    if (cnt < 0) {
        fprintf(stderr, "Failed to get device list\n");
        return -1;
    }
    
    if (target_port_path[0]) {
        printf("Scanning for peer device on port path %s (bus %d)...\n", target_port_path, target_bus);
    } else {
        printf("Scanning for peer device on bus %d (no port path filter)...\n", target_bus);
    }
    
    for (int i = 0; i < cnt; i++) {
        libusb_device *dev = devs[i];
        struct libusb_device_descriptor desc;
        
        if (libusb_get_device_descriptor(dev, &desc) != 0) continue;
        
        int bus = libusb_get_bus_number(dev);
        int dev_addr = libusb_get_device_address(dev);
        
        // Filter by target bus if specified
        if (target_bus > 0 && bus != target_bus) continue;
        
        // Filter by port path if specified
        if (target_port_path[0]) {
            // Get the port path for this device from sysfs
            char sysfs_path[256];
            char dev_port_path[64] = "";
            
            // Try to find this device's port path by matching bus and device number
            snprintf(sysfs_path, sizeof(sysfs_path), "/sys/bus/usb/devices/%s/devnum", target_port_path);
            FILE *f = fopen(sysfs_path, "r");
            if (f) {
                int sysfs_devnum = 0;
                if (fscanf(f, "%d", &sysfs_devnum) == 1) {
                    fclose(f);
                    // Check busnum too
                    snprintf(sysfs_path, sizeof(sysfs_path), "/sys/bus/usb/devices/%s/busnum", target_port_path);
                    f = fopen(sysfs_path, "r");
                    if (f) {
                        int sysfs_busnum = 0;
                        if (fscanf(f, "%d", &sysfs_busnum) == 1) {
                            if (sysfs_busnum == bus && sysfs_devnum == dev_addr) {
                                // This device matches our target port path!
                                printf("  Found device at target port %s: %04x:%04x\n", 
                                       target_port_path, desc.idVendor, desc.idProduct);
                            } else {
                                // Skip - not on our target port
                                fclose(f);
                                continue;
                            }
                        }
                        fclose(f);
                    }
                } else {
                    fclose(f);
                    // Port path exists but no device there currently
                    continue;
                }
            } else {
                // Target port path doesn't have a device connected
                continue;
            }
        }
        
        // Skip root hubs (VID 1d6b is Linux Foundation)
        if (desc.idVendor == 0x1d6b) continue;
        
        // Skip hubs (class 0x09)
        if (desc.bDeviceClass == 0x09) continue;
        
        // Try to open this device
        libusb_device_handle *handle;
        int ret = libusb_open(dev, &handle);
        if (ret != 0) {
            continue;  // Can't open, try next
        }
        
        // Check if device has bulk endpoints
        struct libusb_config_descriptor *config;
        ret = libusb_get_active_config_descriptor(dev, &config);
        if (ret != 0) {
            libusb_close(handle);
            continue;
        }
        
        uint8_t ep_in = 0, ep_out = 0;
        
        for (int iface = 0; iface < config->bNumInterfaces; iface++) {
            const struct libusb_interface *interface = &config->interface[iface];
            for (int alt = 0; alt < interface->num_altsetting; alt++) {
                const struct libusb_interface_descriptor *iface_desc = &interface->altsetting[alt];
                
                for (int ep = 0; ep < iface_desc->bNumEndpoints; ep++) {
                    const struct libusb_endpoint_descriptor *ep_desc = &iface_desc->endpoint[ep];
                    
                    if ((ep_desc->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) == LIBUSB_TRANSFER_TYPE_BULK) {
                        if (ep_desc->bEndpointAddress & LIBUSB_ENDPOINT_IN) {
                            ep_in = ep_desc->bEndpointAddress;
                        } else {
                            ep_out = ep_desc->bEndpointAddress;
                        }
                    }
                }
                
                // If we found both endpoints, use this interface
                if (ep_in && ep_out) {
                    // Detach kernel driver if needed
                    if (libusb_kernel_driver_active(handle, iface) == 1) {
                        libusb_detach_kernel_driver(handle, iface);
                    }
                    
                    ret = libusb_claim_interface(handle, iface);
                    if (ret == 0) {
                        device->dev_handle = handle;
                        device->endpoint_in = ep_in;
                        device->endpoint_out = ep_out;
                        device->interface_num = iface;
                        
                        printf("Found peer device: %04x:%04x on bus %d\n",
                               desc.idVendor, desc.idProduct, bus);
                        printf("  Bulk IN: 0x%02x, Bulk OUT: 0x%02x\n", ep_in, ep_out);
                        
                        libusb_free_config_descriptor(config);
                        libusb_free_device_list(devs, 1);
                        return 0;
                    }
                }
            }
        }
        
        libusb_free_config_descriptor(config);
        libusb_close(handle);
    }
    
    libusb_free_device_list(devs, 1);
    return -1;
}

// Send a packet with our simple protocol
int send_packet(usb_net_device_t *device, packet_type_t type, const uint8_t *data, int len) {
    uint8_t buffer[USB_NET_MTU + sizeof(packet_header_t)];
    packet_header_t *hdr = (packet_header_t *)buffer;
    
    hdr->magic = PACKET_MAGIC;
    hdr->type = type;
    hdr->flags = 0;
    hdr->length = len;
    hdr->seq = device->seq_num++;
    
    if (data && len > 0) {
        memcpy(buffer + sizeof(packet_header_t), data, len);
    }
    
    return usb_net_send(device, buffer, sizeof(packet_header_t) + len);
}

// Receive a packet
int recv_packet(usb_net_device_t *device, packet_type_t *type, uint8_t *data, int max_len) {
    uint8_t buffer[USB_NET_MTU + sizeof(packet_header_t)];
    int received;
    
    received = usb_net_recv(device, buffer, sizeof(buffer));
    if (received < (int)sizeof(packet_header_t)) {
        return -1;
    }
    
    packet_header_t *hdr = (packet_header_t *)buffer;
    
    if (hdr->magic != PACKET_MAGIC) {
        fprintf(stderr, "Invalid packet magic: 0x%08x\n", hdr->magic);
        return -1;
    }
    
    *type = hdr->type;
    
    int data_len = received - sizeof(packet_header_t);
    if (data_len > max_len) data_len = max_len;
    
    if (data && data_len > 0) {
        memcpy(data, buffer + sizeof(packet_header_t), data_len);
    }
    
    return data_len;
}

// Run as USB host - scan for device and initiate communication
int run_host_mode(usb_net_device_t *device) {
    int attempts = 0;
    
    printf("\n=== Running in HOST mode ===\n");
    printf("Waiting for peer device to connect...\n\n");
    
    // Try to find a peer device
    while (attempts < MAX_SCAN_ATTEMPTS) {
        if (find_peer_device(device) == 0) {
            break;
        }
        
        attempts++;
        printf("Scan attempt %d/%d - no peer found, waiting...\n", 
               attempts, MAX_SCAN_ATTEMPTS);
        usleep(SCAN_INTERVAL_MS * 1000);
    }
    
    if (!device->dev_handle) {
        fprintf(stderr, "Failed to find peer device after %d attempts\n", MAX_SCAN_ATTEMPTS);
        return -1;
    }
    
    printf("\nPeer device found! Starting communication...\n\n");
    
    // Send PING packets and wait for PONG
    for (int i = 0; i < 5; i++) {
        char msg[64];
        snprintf(msg, sizeof(msg), "PING #%d from host", i + 1);
        
        printf("Sending: %s\n", msg);
        int ret = send_packet(device, PKT_PING, (uint8_t*)msg, strlen(msg) + 1);
        if (ret < 0) {
            fprintf(stderr, "Send failed\n");
            continue;
        }
        
        // Wait for response
        uint8_t recv_data[256];
        packet_type_t pkt_type;
        ret = recv_packet(device, &pkt_type, recv_data, sizeof(recv_data) - 1);
        if (ret >= 0) {
            recv_data[ret] = '\0';
            printf("Received: type=%d, data='%s'\n", pkt_type, recv_data);
        } else {
            printf("No response (timeout)\n");
        }
        
        sleep(1);
    }
    
    printf("\nHost mode communication test complete\n");
    return 0;
}

// Run as USB device - wait for host connection and respond
int run_device_mode(usb_net_device_t *device) {
    printf("\n=== Running in DEVICE mode ===\n");
    
    // Try Type-C role swap to device if sysfs is available
    if (strlen(device->config.typec_port_path) > 0) {
        printf("Attempting Type-C data role swap to device...\n");
        typec_role_swap(device, "device");
        sleep(2);  // Give time for role swap to complete
    }
    
    printf("Waiting for host connection...\n\n");
    
    // In device mode, we also scan but we'll respond instead of initiate
    int attempts = 0;
    while (attempts < MAX_SCAN_ATTEMPTS) {
        if (find_peer_device(device) == 0) {
            break;
        }
        
        attempts++;
        printf("Scan attempt %d/%d - no host found, waiting...\n", 
               attempts, MAX_SCAN_ATTEMPTS);
        usleep(SCAN_INTERVAL_MS * 1000);
    }
    
    if (!device->dev_handle) {
        fprintf(stderr, "Failed to find host device after %d attempts\n", MAX_SCAN_ATTEMPTS);
        return -1;
    }
    
    printf("\nHost connected! Waiting for packets...\n\n");
    
    // Receive loop - respond to PINGs with PONGs
    int recv_count = 0;
    while (recv_count < 10) {
        uint8_t recv_data[256];
        packet_type_t pkt_type;
        
        int ret = recv_packet(device, &pkt_type, recv_data, sizeof(recv_data) - 1);
        if (ret < 0) {
            continue;  // Timeout, keep waiting
        }
        
        recv_data[ret] = '\0';
        printf("Received: type=%d, data='%s'\n", pkt_type, recv_data);
        recv_count++;
        
        // Respond to PING with PONG
        if (pkt_type == PKT_PING) {
            char response[64];
            snprintf(response, sizeof(response), "PONG from device");
            printf("Sending: %s\n", response);
            send_packet(device, PKT_PONG, (uint8_t*)response, strlen(response) + 1);
        }
    }
    
    printf("\nDevice mode communication test complete\n");
    return 0;
}

// Run in raw communication mode (no USB enumeration required)
// This allows two USB hosts to communicate directly over USB-C
int run_raw_mode(usb_net_device_t *device) {
    printf("\n=== Running in RAW mode (no USB enumeration) ===\n");
    printf("This mode allows direct host-to-host communication.\n\n");
    
    // Initialize raw communication
    raw_comm_init(&device->raw_ctx, device->config.typec_port_path);
    
    // Detect available communication method
    raw_comm_method_t method = raw_comm_detect_method(&device->raw_ctx);
    printf("Using communication method: %d\n", method);
    
    // Start listening for peer
    raw_comm_listen(&device->raw_ctx);
    
    // Main communication loop
    printf("\nWaiting for peer connection...\n");
    printf("(Run this same command on the other device)\n\n");
    
    int timeout_count = 0;
    int max_timeouts = 60;  // 60 seconds total
    
    while (timeout_count < max_timeouts) {
        // Poll for incoming messages (1 second timeout)
        raw_comm_poll(&device->raw_ctx, 1000);
        
        raw_conn_state_t state = raw_comm_get_state(&device->raw_ctx);
        
        if (state == RAW_STATE_CONNECTED) {
            uint32_t peer_id = raw_comm_get_peer_id(&device->raw_ctx);
            printf("\nConnected to peer 0x%08x!\n", peer_id);
            break;
        }
        
        timeout_count++;
        
        if (timeout_count % 5 == 0) {
            printf("Still waiting for peer... (%d/%d)\n", timeout_count, max_timeouts);
        }
    }
    
    if (raw_comm_get_state(&device->raw_ctx) != RAW_STATE_CONNECTED) {
        printf("\nFailed to connect to peer after %d seconds\n", max_timeouts);
        raw_comm_cleanup(&device->raw_ctx);
        return -1;
    }
    
    // Connected! Now exchange some test messages
    printf("\n=== Connection established! Testing data exchange... ===\n\n");
    
    for (int i = 0; i < 5; i++) {
        char msg[64];
        snprintf(msg, sizeof(msg), "Test message #%d from 0x%08x", 
                 i + 1, device->raw_ctx.local_id);
        
        printf("Sending: %s\n", msg);
        raw_comm_send(&device->raw_ctx, (uint8_t *)msg, strlen(msg) + 1);
        
        // Wait for response
        uint8_t recv_buf[256];
        raw_comm_poll(&device->raw_ctx, 2000);
        int n = raw_comm_recv(&device->raw_ctx, recv_buf, sizeof(recv_buf) - 1);
        if (n > 0) {
            recv_buf[n] = '\0';
            printf("Received: %s\n", recv_buf);
        }
        
        sleep(1);
    }
    
    printf("\nRaw mode communication test complete\n");
    raw_comm_cleanup(&device->raw_ctx);
    return 0;
}

void print_usage(const char *prog) {
    printf("Usage: %s [OPTIONS]\n\n", prog);
    printf("Options:\n");
    printf("  --mode host|device|raw|list   Operating mode (default: list)\n");
    printf("  --config <path>               Path to config file (default: target_usb_c_port.env)\n");
    printf("  --help                        Show this help message\n");
    printf("\nModes:\n");
    printf("  host    - Act as USB host, scan for device, send PING packets\n");
    printf("  device  - Act as USB device, wait for host, respond with PONG\n");
    printf("  raw     - Raw mode: direct host-to-host without USB enumeration\n");
    printf("  list    - Just list USB devices and exit\n");
    printf("\nExamples:\n");
    printf("  %s --mode raw                  # Recommended for host-to-host\n", prog);
    printf("  %s --mode host\n", prog);
    printf("  %s --mode device --config /path/to/config.env\n", prog);
}

int main(int argc, char *argv[]) {
    usb_net_device_t device;
    usb_net_mode_t mode = MODE_LIST;
    const char *config_path = "target_usb_c_port.env";
    int ret;
    
    // Parse command line arguments
    static struct option long_options[] = {
        {"mode",   required_argument, 0, 'm'},
        {"config", required_argument, 0, 'c'},
        {"help",   no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "m:c:h", long_options, NULL)) != -1) {
        switch (opt) {
            case 'm':
                if (strcmp(optarg, "host") == 0) {
                    mode = MODE_HOST;
                } else if (strcmp(optarg, "device") == 0) {
                    mode = MODE_DEVICE;
                } else if (strcmp(optarg, "raw") == 0) {
                    mode = MODE_RAW;
                } else if (strcmp(optarg, "list") == 0) {
                    mode = MODE_LIST;
                } else {
                    fprintf(stderr, "Invalid mode: %s\n", optarg);
                    print_usage(argv[0]);
                    return 1;
                }
                break;
            case 'c':
                config_path = optarg;
                break;
            case 'h':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    printf("=== USB-C Software Network (Direct Hardware Access) ===\n");
    printf("No kernel gadget drivers required!\n\n");
    
    ret = usb_net_init(&device);
    if (ret < 0) {
        return 1;
    }
    
    // Load configuration
    load_config(&device, config_path);
    device.mode = mode;
    
    // Execute based on mode
    switch (mode) {
        case MODE_HOST:
            ret = run_host_mode(&device);
            break;
        case MODE_DEVICE:
            ret = run_device_mode(&device);
            break;
        case MODE_RAW:
            ret = run_raw_mode(&device);
            break;
        case MODE_LIST:
        default:
            usb_net_list_devices(&device);
            printf("\nUse --mode raw for host-to-host communication\n");
            printf("Or --mode host/device for traditional USB mode\n");
            ret = 0;
            break;
    }
    
    usb_net_cleanup(&device);
    
    return ret < 0 ? 1 : 0;
}
