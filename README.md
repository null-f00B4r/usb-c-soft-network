# usb-c-soft-network
USB type C Software-based Network

## Description
A software-based implementation of a USB type C network interface, allowing devices to communicate over USB-C without dedicated hardware support. This project aims to provide a flexible and efficient way to establish network connections using USB-C ports, leveraging direct hardware access and control.

## Features
- **Software-based**: No need for specialized hardware, making it accessible for a wide range of devices.
- **Hardware Requirements** (or lack thereof): You don't need a fancy USB network adapter or special cables, just a regular USB-C cable and two devices with USB-C ports. 
    + Well, you don't accidentally need two devices, if you want to send data to yourself ... .
- **Flexible Protocols**: Supports file transfer and implements a simple IP over USB-C protocol.
- **High Performance**: Optimized for low latency and high throughput to ensure efficient data transfer.
- **Platform**: Linux, what else?
    + For use with other operating systems -> **Install Linux**
- **Message of the Day**: "Have a nice day!"

## Security
Be aware that this project is intended for educational and experimental purposes only. It may not include all necessary security features for production use. Users are advised to implement additional security measures as needed.

## Warranty
This project is provided "as is" without any warranties, express or implied. The author disclaims all warranties, including but not limited to implied warranties of merchantability and fitness for a particular purpose. In no event shall the author be liable for any damages arising from the use of this project.

### Disclaimer
Well, this project uses direct hardware access, so there might be a mushroom cloud appearing slightly above your device if something goes wrong. Use at your own risk!

## Language
- C for low-level USB-C interactions and network stack implementation.
- C++ for higher-level abstractions and protocol handling.
- Python for testing, scripting, and automation tasks.
- Bash for build scripts and deployment automation.

## Building

Quick build & test using the included devcontainer (recommended):
```bash
docker build -f .devcontainer/Dockerfile -t usb-c-soft-network-ci:latest .
docker run --rm -v "$PWD:/workspaces/usb-c-soft-network" usb-c-soft-network-ci:latest ./scripts/build.sh
```

Quick build on host (non-Docker):
```bash
SKIP_COMPILER_CHECK=1 ./scripts/host_build.sh RelWithDebInfo
```

To run hardware integration tests, use the `TEST_HARDWARE` cmake flag (off by default):
```bash
cmake -S . -B build -DTEST_HARDWARE=ON
cmake --build build
ctest --test-dir build
```
