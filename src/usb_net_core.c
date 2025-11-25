// USB-C Software Network - Core USB Hardware Access Layer
// This implements direct USB communication without kernel gadget drivers

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libusb-1.0/libusb.h>

#define USB_VENDOR_ID  0x1d6b  // Linux Foundation
#define USB_PRODUCT_ID 0x0104  // Multifunction Composite Gadget
#define USB_TIMEOUT_MS 5000

typedef struct {
    libusb_context *ctx;
    libusb_device_handle *dev_handle;
    uint8_t endpoint_in;
    uint8_t endpoint_out;
    int interface_num;
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

int main(int argc, char *argv[]) {
    usb_net_device_t device;
    int ret;
    
    printf("=== USB-C Software Network (Direct Hardware Access) ===\n");
    printf("No kernel gadget drivers required!\n\n");
    
    ret = usb_net_init(&device);
    if (ret < 0) {
        return 1;
    }
    
    // List all USB devices
    usb_net_list_devices(&device);
    
    printf("\nThis is a demonstration of direct USB hardware access.\n");
    printf("The full network stack implementation is in progress.\n");
    printf("\nNext steps:\n");
    printf("  1. Detect USB-C specific features (Type-C controller access)\n");
    printf("  2. Implement custom USB descriptors for network class\n");
    printf("  3. Create packet framing protocol over bulk endpoints\n");
    printf("  4. Add IP layer and routing\n");
    printf("  5. Implement USB-C PD (Power Delivery) negotiation\n");
    
    usb_net_cleanup(&device);
    
    return 0;
}
