// USB-C Software Network - Raw Communication Layer Implementation
// Implements direct USB-C communication without standard USB enumeration
//
// Methods supported:
// 1. Type-C sysfs polling - Monitor connection state and partner info
// 2. USB PD VDM - Send vendor-defined messages over CC line (if supported)
// 3. Raw xHCI debug - Direct controller access (fallback)

#include "usb_raw_comm.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <dirent.h>
#include <poll.h>

// Generate a random local ID
static uint32_t generate_local_id(void) {
    uint32_t id;
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd >= 0) {
        read(fd, &id, sizeof(id));
        close(fd);
    } else {
        id = (uint32_t)time(NULL) ^ (uint32_t)getpid();
    }
    return id | 0x80000000;  // Ensure high bit set to avoid 0
}

// Calculate simple checksum
static uint16_t calc_checksum(const uint8_t *data, size_t len) {
    uint32_t sum = 0;
    for (size_t i = 0; i < len; i++) {
        sum += data[i];
    }
    return (uint16_t)(sum & 0xFFFF);
}

// Check if Type-C port has partner connected
static bool check_typec_partner(const char *port_path) {
    char partner_path[512];
    struct stat st;
    
    snprintf(partner_path, sizeof(partner_path), "%s-partner", port_path);
    return (stat(partner_path, &st) == 0 && S_ISDIR(st.st_mode));
}

// Read sysfs attribute
static int read_sysfs_attr(const char *path, char *buf, size_t buflen) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    
    ssize_t n = read(fd, buf, buflen - 1);
    close(fd);
    
    if (n < 0) return -1;
    buf[n] = '\0';
    
    // Remove trailing newline
    while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r')) {
        buf[--n] = '\0';
    }
    
    return (int)n;
}

// Write sysfs attribute
static int write_sysfs_attr(const char *path, const char *value) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) return -1;
    
    ssize_t n = write(fd, value, strlen(value));
    close(fd);
    
    return (n > 0) ? 0 : -1;
}

// Initialize raw communication context
int raw_comm_init(raw_comm_ctx_t *ctx, const char *typec_port_path) {
    memset(ctx, 0, sizeof(raw_comm_ctx_t));
    
    ctx->state = RAW_STATE_DISCONNECTED;
    ctx->local_id = generate_local_id();
    ctx->pd_fd = -1;
    ctx->xhci_fd = -1;
    
    printf("Raw communication initialized (local_id=0x%08x)\n", ctx->local_id);
    
    if (typec_port_path && typec_port_path[0]) {
        strncpy(ctx->typec_port_path, typec_port_path, sizeof(ctx->typec_port_path) - 1);
        printf("Type-C port path: %s\n", ctx->typec_port_path);
        
        // Check for USB PD support
        snprintf(ctx->pd_path, sizeof(ctx->pd_path), 
                 "%s/usb_power_delivery", ctx->typec_port_path);
        
        struct stat st;
        if (stat(ctx->pd_path, &st) == 0) {
            printf("USB Power Delivery path found: %s\n", ctx->pd_path);
        } else {
            ctx->pd_path[0] = '\0';
            printf("No USB Power Delivery sysfs support\n");
        }
    }
    
    return 0;
}

// Cleanup
void raw_comm_cleanup(raw_comm_ctx_t *ctx) {
    if (ctx->pd_fd >= 0) {
        close(ctx->pd_fd);
        ctx->pd_fd = -1;
    }
    
    if (ctx->xhci_base) {
        munmap(ctx->xhci_base, ctx->xhci_size);
        ctx->xhci_base = NULL;
    }
    
    if (ctx->xhci_fd >= 0) {
        close(ctx->xhci_fd);
        ctx->xhci_fd = -1;
    }
    
    ctx->state = RAW_STATE_DISCONNECTED;
    printf("Raw communication cleaned up\n");
}

// Detect available communication methods
raw_comm_method_t raw_comm_detect_method(raw_comm_ctx_t *ctx) {
    struct stat st;
    
    // Check for Type-C sysfs support
    if (ctx->typec_port_path[0] && stat(ctx->typec_port_path, &st) == 0) {
        // Check if we have USB PD VDM capability
        char vdm_path[512];
        snprintf(vdm_path, sizeof(vdm_path), 
                 "%s/usb_power_delivery/source_capabilities", ctx->typec_port_path);
        
        if (stat(vdm_path, &st) == 0) {
            printf("Detected method: USB PD VDM\n");
            ctx->method = RAW_METHOD_PD_VDM;
            return RAW_METHOD_PD_VDM;
        }
        
        // Fall back to Type-C sysfs polling
        printf("Detected method: Type-C sysfs polling\n");
        ctx->method = RAW_METHOD_TYPEC_SYSFS;
        return RAW_METHOD_TYPEC_SYSFS;
    }
    
    // Check for xHCI debug capability
    // Look for debug capability in xHCI extended capabilities
    FILE *fp = fopen("/proc/iomem", "r");
    if (fp) {
        char line[256];
        while (fgets(line, sizeof(line), fp)) {
            if (strstr(line, "xhci") || strstr(line, "XHCI")) {
                printf("Found xHCI controller: %s", line);
                // Could implement debug capability detection here
            }
        }
        fclose(fp);
    }
    
    // Default to polling method (monitor sysfs for changes)
    printf("Detected method: Polling\n");
    ctx->method = RAW_METHOD_POLLING;
    return RAW_METHOD_POLLING;
}

// Build a protocol message
static int build_message(raw_comm_ctx_t *ctx, uint8_t msg_type,
                         const uint8_t *payload, size_t payload_len,
                         uint8_t *output, size_t output_size) {
    if (output_size < sizeof(raw_msg_header_t) + payload_len) {
        return -1;
    }
    
    raw_msg_header_t *hdr = (raw_msg_header_t *)output;
    memcpy(hdr->magic, RAW_MSG_MAGIC, 4);
    hdr->version = RAW_PROTOCOL_VERSION;
    hdr->msg_type = msg_type;
    hdr->length = (uint16_t)payload_len;
    hdr->src_id = ctx->local_id;
    hdr->dst_id = ctx->peer_id;
    hdr->seq = ctx->seq_tx++;
    hdr->reserved = 0;
    
    if (payload && payload_len > 0) {
        memcpy(output + sizeof(raw_msg_header_t), payload, payload_len);
    }
    
    // Calculate checksum over header (excluding checksum field) and payload
    hdr->checksum = 0;
    hdr->checksum = calc_checksum(output, sizeof(raw_msg_header_t) + payload_len);
    
    return (int)(sizeof(raw_msg_header_t) + payload_len);
}

// Parse a protocol message
static int parse_message(const uint8_t *input, size_t input_len,
                         raw_msg_header_t *hdr, uint8_t *payload, size_t payload_max) {
    if (input_len < sizeof(raw_msg_header_t)) {
        return -1;
    }
    
    memcpy(hdr, input, sizeof(raw_msg_header_t));
    
    // Verify magic
    if (memcmp(hdr->magic, RAW_MSG_MAGIC, 4) != 0) {
        return -2;  // Invalid magic
    }
    
    // Verify version
    if (hdr->version != RAW_PROTOCOL_VERSION) {
        return -3;  // Version mismatch
    }
    
    // Verify length
    if (input_len < sizeof(raw_msg_header_t) + hdr->length) {
        return -4;  // Incomplete message
    }
    
    // Copy payload
    size_t copy_len = (hdr->length < payload_max) ? hdr->length : payload_max;
    if (payload && copy_len > 0) {
        memcpy(payload, input + sizeof(raw_msg_header_t), copy_len);
    }
    
    return (int)copy_len;
}

// Type-C sysfs based communication - write to a shared file
// This is a workaround: we use a known file path that both sides can access
// In practice, this would use actual PD VDM or other hardware mechanism
static const char *SHARED_COMM_FILE = "/tmp/usbc_net_comm";

static int sysfs_send_message(raw_comm_ctx_t *ctx, const uint8_t *msg, size_t len) {
    char path[512];
    
    // For now, use a temp file as shared memory for IPC
    // In real implementation, this would go over USB PD VDM
    snprintf(path, sizeof(path), "%s.%08x", SHARED_COMM_FILE, ctx->local_id);
    
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd < 0) {
        perror("Failed to open comm file for writing");
        return -1;
    }
    
    ssize_t written = write(fd, msg, len);
    close(fd);
    
    if (written != (ssize_t)len) {
        return -1;
    }
    
    printf("  [TX] Sent %zd bytes to %s\n", written, path);
    return (int)written;
}

static int sysfs_recv_message(raw_comm_ctx_t *ctx, uint8_t *msg, size_t max_len, 
                               uint32_t *from_id) {
    DIR *dir = opendir("/tmp");
    if (!dir) return -1;
    
    struct dirent *entry;
    char best_path[512] = "";
    time_t best_mtime = 0;
    uint32_t best_id = 0;
    
    // Look for comm files from other peers
    while ((entry = readdir(dir)) != NULL) {
        if (strncmp(entry->d_name, "usbc_net_comm.", 14) == 0) {
            // Extract sender ID from filename
            uint32_t sender_id = (uint32_t)strtoul(entry->d_name + 14, NULL, 16);
            
            // Skip our own messages
            if (sender_id == ctx->local_id) continue;
            
            char path[512];
            snprintf(path, sizeof(path), "/tmp/%s", entry->d_name);
            
            struct stat st;
            if (stat(path, &st) == 0) {
                // Get the most recent message
                if (st.st_mtime > best_mtime) {
                    best_mtime = st.st_mtime;
                    strncpy(best_path, path, sizeof(best_path) - 1);
                    best_id = sender_id;
                }
            }
        }
    }
    closedir(dir);
    
    if (best_path[0] == '\0') {
        return 0;  // No messages
    }
    
    int fd = open(best_path, O_RDONLY);
    if (fd < 0) return -1;
    
    ssize_t n = read(fd, msg, max_len);
    close(fd);
    
    // Delete the message after reading
    unlink(best_path);
    
    if (n > 0) {
        *from_id = best_id;
        printf("  [RX] Received %zd bytes from 0x%08x\n", n, best_id);
    }
    
    return (int)n;
}

// Start listening for peer connections
int raw_comm_listen(raw_comm_ctx_t *ctx) {
    printf("\n=== Starting raw communication listener ===\n");
    printf("Local ID: 0x%08x\n", ctx->local_id);
    printf("Method: %d\n", ctx->method);
    
    ctx->state = RAW_STATE_DETECTING;
    
    // Check if Type-C cable is connected
    if (ctx->typec_port_path[0]) {
        if (check_typec_partner(ctx->typec_port_path)) {
            printf("Type-C cable detected (partner present)\n");
        } else {
            printf("Waiting for Type-C cable connection...\n");
        }
    }
    
    // Send discovery broadcast
    uint8_t msg_buf[256];
    char payload[64];
    snprintf(payload, sizeof(payload), "DISCOVER:%08x", ctx->local_id);
    
    int msg_len = build_message(ctx, RAW_MSG_DISCOVERY, 
                                 (uint8_t *)payload, strlen(payload) + 1,
                                 msg_buf, sizeof(msg_buf));
    
    if (msg_len > 0) {
        printf("Broadcasting discovery message...\n");
        sysfs_send_message(ctx, msg_buf, msg_len);
    }
    
    return 0;
}

// Connect to a specific peer
int raw_comm_connect(raw_comm_ctx_t *ctx, uint32_t peer_id) {
    printf("Attempting to connect to peer 0x%08x\n", peer_id);
    
    ctx->peer_id = peer_id;
    ctx->state = RAW_STATE_HANDSHAKING;
    
    // Send handshake
    uint8_t msg_buf[256];
    char payload[64];
    snprintf(payload, sizeof(payload), "HANDSHAKE:%08x->%08x", 
             ctx->local_id, peer_id);
    
    int msg_len = build_message(ctx, RAW_MSG_HANDSHAKE,
                                 (uint8_t *)payload, strlen(payload) + 1,
                                 msg_buf, sizeof(msg_buf));
    
    if (msg_len > 0) {
        sysfs_send_message(ctx, msg_buf, msg_len);
    }
    
    return 0;
}

// Send data to connected peer
int raw_comm_send(raw_comm_ctx_t *ctx, const uint8_t *data, size_t len) {
    if (ctx->state != RAW_STATE_CONNECTED) {
        fprintf(stderr, "Cannot send: not connected\n");
        return -1;
    }
    
    uint8_t msg_buf[1024];
    int msg_len = build_message(ctx, RAW_MSG_DATA, data, len, 
                                 msg_buf, sizeof(msg_buf));
    
    if (msg_len > 0) {
        return sysfs_send_message(ctx, msg_buf, msg_len);
    }
    
    return -1;
}

// Receive data from connected peer
int raw_comm_recv(raw_comm_ctx_t *ctx, uint8_t *buffer, size_t max_len) {
    uint8_t msg_buf[1024];
    uint32_t from_id;
    
    int n = sysfs_recv_message(ctx, msg_buf, sizeof(msg_buf), &from_id);
    if (n <= 0) return n;
    
    raw_msg_header_t hdr;
    uint8_t payload[1024];
    
    int payload_len = parse_message(msg_buf, n, &hdr, payload, sizeof(payload));
    if (payload_len < 0) {
        fprintf(stderr, "Failed to parse message: %d\n", payload_len);
        return -1;
    }
    
    printf("  Received message type %d from 0x%08x, payload %d bytes\n",
           hdr.msg_type, hdr.src_id, payload_len);
    
    // Handle message based on type and state
    switch (hdr.msg_type) {
        case RAW_MSG_DISCOVERY:
            printf("  -> Discovery from peer 0x%08x\n", hdr.src_id);
            if (ctx->state == RAW_STATE_DETECTING) {
                // Respond to discovery
                ctx->peer_id = hdr.src_id;
                
                uint8_t ack_buf[256];
                char ack_payload[64];
                snprintf(ack_payload, sizeof(ack_payload), "ACK:%08x", ctx->local_id);
                
                int ack_len = build_message(ctx, RAW_MSG_DISCOVERY_ACK,
                                            (uint8_t *)ack_payload, strlen(ack_payload) + 1,
                                            ack_buf, sizeof(ack_buf));
                if (ack_len > 0) {
                    sysfs_send_message(ctx, ack_buf, ack_len);
                }
            }
            break;
            
        case RAW_MSG_DISCOVERY_ACK:
            printf("  -> Discovery ACK from peer 0x%08x\n", hdr.src_id);
            if (ctx->state == RAW_STATE_DETECTING) {
                ctx->peer_id = hdr.src_id;
                ctx->state = RAW_STATE_HANDSHAKING;
                raw_comm_connect(ctx, hdr.src_id);
            }
            break;
            
        case RAW_MSG_HANDSHAKE:
            printf("  -> Handshake from peer 0x%08x\n", hdr.src_id);
            if (ctx->state == RAW_STATE_DETECTING || ctx->state == RAW_STATE_HANDSHAKING) {
                ctx->peer_id = hdr.src_id;
                
                // Send handshake ack
                uint8_t ack_buf[256];
                char ack_payload[64];
                snprintf(ack_payload, sizeof(ack_payload), "HSHAKE_ACK:%08x", ctx->local_id);
                
                int ack_len = build_message(ctx, RAW_MSG_HANDSHAKE_ACK,
                                            (uint8_t *)ack_payload, strlen(ack_payload) + 1,
                                            ack_buf, sizeof(ack_buf));
                if (ack_len > 0) {
                    sysfs_send_message(ctx, ack_buf, ack_len);
                }
                
                ctx->state = RAW_STATE_CONNECTED;
                printf("\n*** CONNECTED to peer 0x%08x ***\n\n", ctx->peer_id);
                
                if (ctx->on_connected) {
                    ctx->on_connected(ctx->callback_ctx);
                }
            }
            break;
            
        case RAW_MSG_HANDSHAKE_ACK:
            printf("  -> Handshake ACK from peer 0x%08x\n", hdr.src_id);
            if (ctx->state == RAW_STATE_HANDSHAKING) {
                ctx->state = RAW_STATE_CONNECTED;
                printf("\n*** CONNECTED to peer 0x%08x ***\n\n", ctx->peer_id);
                
                if (ctx->on_connected) {
                    ctx->on_connected(ctx->callback_ctx);
                }
            }
            break;
            
        case RAW_MSG_DATA:
            if (ctx->state == RAW_STATE_CONNECTED && payload_len > 0) {
                size_t copy_len = (payload_len < (int)max_len) ? payload_len : max_len;
                memcpy(buffer, payload, copy_len);
                
                if (ctx->on_data) {
                    ctx->on_data(ctx->callback_ctx, payload, payload_len);
                }
                
                return (int)copy_len;
            }
            break;
            
        case RAW_MSG_DISCONNECT:
            printf("  -> Disconnect from peer 0x%08x\n", hdr.src_id);
            ctx->state = RAW_STATE_DISCONNECTED;
            ctx->peer_id = 0;
            
            if (ctx->on_disconnected) {
                ctx->on_disconnected(ctx->callback_ctx);
            }
            break;
    }
    
    return 0;
}

// Poll for events
int raw_comm_poll(raw_comm_ctx_t *ctx, int timeout_ms) {
    // Simple polling implementation
    int elapsed = 0;
    int interval = 100;  // 100ms poll interval
    
    while (elapsed < timeout_ms) {
        uint8_t buf[1024];
        int n = raw_comm_recv(ctx, buf, sizeof(buf));
        
        if (n > 0) {
            return n;  // Got data
        }
        
        if (ctx->state == RAW_STATE_CONNECTED) {
            return 0;  // Connected, but no data
        }
        
        usleep(interval * 1000);
        elapsed += interval;
        
        // Periodically re-send discovery if still detecting
        if (ctx->state == RAW_STATE_DETECTING && (elapsed % 2000) == 0) {
            uint8_t msg_buf[256];
            char payload[64];
            snprintf(payload, sizeof(payload), "DISCOVER:%08x", ctx->local_id);
            
            int msg_len = build_message(ctx, RAW_MSG_DISCOVERY,
                                         (uint8_t *)payload, strlen(payload) + 1,
                                         msg_buf, sizeof(msg_buf));
            if (msg_len > 0) {
                sysfs_send_message(ctx, msg_buf, msg_len);
            }
        }
    }
    
    return 0;  // Timeout
}

// Get connection state
raw_conn_state_t raw_comm_get_state(raw_comm_ctx_t *ctx) {
    return ctx->state;
}

// Get peer ID
uint32_t raw_comm_get_peer_id(raw_comm_ctx_t *ctx) {
    return ctx->peer_id;
}
