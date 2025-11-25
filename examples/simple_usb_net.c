/*
 * simple_usb_net.c - Simple IP-over-USB demo for usb-c-soft-network
 *
 * This example demonstrates basic USB-C network setup and packet transfer.
 * It creates a virtual network interface over USB-C and allows basic
 * IP communication between two connected devices.
 *
 * Build: See README.md for build instructions
 * Usage: ./simple_usb_net [host|device]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define USB_NET_MTU 1500
#define USB_NET_PORT 9999
#define HOST_IP "192.168.7.1"
#define DEVICE_IP "192.168.7.2"

typedef enum {
    MODE_HOST,
    MODE_DEVICE
} usb_net_mode_t;

static void print_usage(const char *prog) {
    fprintf(stderr, "Usage: %s [host|device]\n", prog);
    fprintf(stderr, "  host   - Run as USB host (computer side)\n");
    fprintf(stderr, "  device - Run as USB device (gadget side)\n");
}

static int setup_usb_gadget(void) {
    printf("Setting up USB gadget mode...\n");
    printf("Note: This requires root privileges and proper kernel modules.\n");
    printf("Modules needed: g_ether or configfs gadget\n");
    
    // In a real implementation, this would:
    // 1. Load g_ether or configure USB gadget via configfs
    // 2. Set up network interface (usb0)
    // 3. Configure IP address
    
    printf("Virtual setup: USB gadget would be configured here\n");
    printf("Expected interface: usb0 with IP %s\n", DEVICE_IP);
    
    return 0;
}

static int setup_usb_host(void) {
    printf("Setting up USB host mode...\n");
    printf("Note: This requires root privileges and USB device connected.\n");
    
    // In a real implementation, this would:
    // 1. Detect USB network device
    // 2. Configure network interface (usb0 or similar)
    // 3. Set up IP routing
    
    printf("Virtual setup: USB host would be configured here\n");
    printf("Expected interface: usb0 with IP %s\n", HOST_IP);
    
    return 0;
}

static int run_host_demo(void) {
    int sockfd;
    struct sockaddr_in server_addr, client_addr;
    char buffer[USB_NET_MTU];
    socklen_t addr_len = sizeof(client_addr);
    
    printf("\n=== Running as USB HOST ===\n");
    
    if (setup_usb_host() < 0) {
        fprintf(stderr, "Failed to setup USB host\n");
        return -1;
    }
    
    // Create UDP socket for demo
    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) {
        perror("socket");
        return -1;
    }
    
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = inet_addr(HOST_IP);
    server_addr.sin_port = htons(USB_NET_PORT);
    
    if (bind(sockfd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        perror("bind");
        close(sockfd);
        return -1;
    }
    
    printf("Listening on %s:%d\n", HOST_IP, USB_NET_PORT);
    printf("Waiting for messages from device...\n");
    
    // Demo: receive and echo packets
    while (1) {
        ssize_t n = recvfrom(sockfd, buffer, sizeof(buffer) - 1, 0,
                            (struct sockaddr *)&client_addr, &addr_len);
        if (n < 0) {
            perror("recvfrom");
            break;
        }
        
        buffer[n] = '\0';
        printf("Received: %s\n", buffer);
        
        // Echo back
        const char *response = "ACK from host";
        sendto(sockfd, response, strlen(response), 0,
               (struct sockaddr *)&client_addr, addr_len);
    }
    
    close(sockfd);
    return 0;
}

static int run_device_demo(void) {
    int sockfd;
    struct sockaddr_in server_addr;
    char buffer[USB_NET_MTU];
    int count = 0;
    
    printf("\n=== Running as USB DEVICE ===\n");
    
    if (setup_usb_gadget() < 0) {
        fprintf(stderr, "Failed to setup USB gadget\n");
        return -1;
    }
    
    // Create UDP socket for demo
    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) {
        perror("socket");
        return -1;
    }
    
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = inet_addr(HOST_IP);
    server_addr.sin_port = htons(USB_NET_PORT);
    
    printf("Sending messages to host at %s:%d\n", HOST_IP, USB_NET_PORT);
    
    // Demo: send packets and receive responses
    while (count < 5) {
        snprintf(buffer, sizeof(buffer), "Hello from device #%d", count++);
        
        printf("Sending: %s\n", buffer);
        ssize_t n = sendto(sockfd, buffer, strlen(buffer), 0,
                          (struct sockaddr *)&server_addr, sizeof(server_addr));
        if (n < 0) {
            perror("sendto");
            break;
        }
        
        // Wait for response
        struct sockaddr_in from_addr;
        socklen_t from_len = sizeof(from_addr);
        n = recvfrom(sockfd, buffer, sizeof(buffer) - 1, 0,
                    (struct sockaddr *)&from_addr, &from_len);
        if (n > 0) {
            buffer[n] = '\0';
            printf("Received: %s\n", buffer);
        }
        
        sleep(2);
    }
    
    close(sockfd);
    printf("Demo completed.\n");
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        print_usage(argv[0]);
        return 1;
    }
    
    usb_net_mode_t mode;
    if (strcmp(argv[1], "host") == 0) {
        mode = MODE_HOST;
    } else if (strcmp(argv[1], "device") == 0) {
        mode = MODE_DEVICE;
    } else {
        fprintf(stderr, "Invalid mode: %s\n", argv[1]);
        print_usage(argv[0]);
        return 1;
    }
    
    printf("USB-C Software Network Demo\n");
    printf("============================\n");
    
    int ret;
    if (mode == MODE_HOST) {
        ret = run_host_demo();
    } else {
        ret = run_device_demo();
    }
    
    return ret;
}
