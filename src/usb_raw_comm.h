// USB-C Software Network - Raw Communication Layer
// Implements direct USB-C communication without standard USB enumeration
// Uses USB Power Delivery messaging and raw xHCI access
//
// This module provides an alternative to standard USB host/device model
// by communicating over USB-C CC (Configuration Channel) pins via PD
// and/or using raw xHCI controller access.

#ifndef USB_RAW_COMM_H
#define USB_RAW_COMM_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// Communication methods
typedef enum {
    RAW_METHOD_NONE = 0,
    RAW_METHOD_PD_VDM,      // USB Power Delivery Vendor Defined Messages
    RAW_METHOD_TYPEC_SYSFS, // Type-C sysfs interface
    RAW_METHOD_XHCI_DEBUG,  // xHCI Debug Capability
    RAW_METHOD_POLLING      // Polling-based raw access
} raw_comm_method_t;

// Connection state
typedef enum {
    RAW_STATE_DISCONNECTED = 0,
    RAW_STATE_DETECTING,
    RAW_STATE_HANDSHAKING,
    RAW_STATE_CONNECTED,
    RAW_STATE_ERROR
} raw_conn_state_t;

// Raw communication context
typedef struct {
    raw_comm_method_t method;
    raw_conn_state_t state;
    
    // Type-C sysfs paths
    char typec_port_path[256];
    char pd_path[256];
    int pd_fd;
    
    // xHCI debug capability
    void *xhci_base;
    size_t xhci_size;
    int xhci_fd;
    
    // Communication buffers
    uint8_t tx_buffer[1024];
    uint8_t rx_buffer[1024];
    
    // Protocol state
    uint32_t local_id;
    uint32_t peer_id;
    uint32_t seq_tx;
    uint32_t seq_rx;
    
    // Callbacks
    void (*on_connected)(void *ctx);
    void (*on_data)(void *ctx, const uint8_t *data, size_t len);
    void (*on_disconnected)(void *ctx);
    void *callback_ctx;
} raw_comm_ctx_t;

// Protocol message types (over CC/PD)
#define RAW_MSG_DISCOVERY   0x01  // Initial discovery ping
#define RAW_MSG_DISCOVERY_ACK 0x02  // Discovery acknowledgment  
#define RAW_MSG_HANDSHAKE   0x03  // Handshake initiation
#define RAW_MSG_HANDSHAKE_ACK 0x04  // Handshake acknowledgment
#define RAW_MSG_DATA        0x10  // Data packet
#define RAW_MSG_DATA_ACK    0x11  // Data acknowledgment
#define RAW_MSG_KEEPALIVE   0x20  // Keep-alive ping
#define RAW_MSG_DISCONNECT  0xFF  // Disconnect notification

// Protocol message header
typedef struct __attribute__((packed)) {
    uint8_t  magic[4];    // "UCNP" - USB-C Net Protocol
    uint8_t  version;     // Protocol version
    uint8_t  msg_type;    // Message type
    uint16_t length;      // Payload length
    uint32_t src_id;      // Source identifier
    uint32_t dst_id;      // Destination identifier (0 = broadcast)
    uint32_t seq;         // Sequence number
    uint16_t checksum;    // Simple checksum
    uint16_t reserved;
} raw_msg_header_t;

#define RAW_MSG_MAGIC "UCNP"
#define RAW_PROTOCOL_VERSION 1

// Initialize raw communication
int raw_comm_init(raw_comm_ctx_t *ctx, const char *typec_port_path);

// Cleanup raw communication
void raw_comm_cleanup(raw_comm_ctx_t *ctx);

// Detect available communication methods
raw_comm_method_t raw_comm_detect_method(raw_comm_ctx_t *ctx);

// Start listening for peer connection
int raw_comm_listen(raw_comm_ctx_t *ctx);

// Connect to peer
int raw_comm_connect(raw_comm_ctx_t *ctx, uint32_t peer_id);

// Send data
int raw_comm_send(raw_comm_ctx_t *ctx, const uint8_t *data, size_t len);

// Receive data (non-blocking)
int raw_comm_recv(raw_comm_ctx_t *ctx, uint8_t *buffer, size_t max_len);

// Poll for events
int raw_comm_poll(raw_comm_ctx_t *ctx, int timeout_ms);

// Get connection state
raw_conn_state_t raw_comm_get_state(raw_comm_ctx_t *ctx);

// Get peer ID (after connection established)
uint32_t raw_comm_get_peer_id(raw_comm_ctx_t *ctx);

#endif // USB_RAW_COMM_H
