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

⚠️ **IMPORTANT**: This project requires **direct hardware access** and **root privileges**.

This project is intended for **educational and experimental purposes only**. It is not production-ready and should not be used in critical systems.

**Key Security Considerations:**
- Requires root/sudo for USB device access
- Direct hardware manipulation can damage devices if misused
- Hardware tests must only run in controlled environments
- **Never run untrusted code with hardware access enabled**

**Safe Development Practices:**
- ✅ Use the devcontainer for isolated development
- ✅ Test in VMs with USB passthrough before using real hardware
- ✅ Review the [SECURITY.md](SECURITY.md) policy before contributing
- ❌ Don't run hardware tests on production systems
- ❌ Don't enable hardware tests for forked repositories in CI

See [SECURITY.md](SECURITY.md) for detailed security guidelines and vulnerability reporting.

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

### Quick Start

#### Using DevContainer (Recommended)
The easiest way to build is using the provided devcontainer with Intel oneAPI compilers:

```bash
# Build the devcontainer image
docker build -f .devcontainer/Dockerfile -t usb-c-soft-network-ci:latest .

# Run the build inside the container
docker run --rm -v "$PWD:/workspaces/usb-c-soft-network" \
    usb-c-soft-network-ci:latest ./scripts/build.sh
```

#### On Host with Intel oneAPI

If you have Intel oneAPI compilers installed:

```bash
# Using the host build script
./scripts/host_build.sh RelWithDebInfo

# Or manually with CMake
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
cmake --build build --parallel
```

#### On Host with System Compilers

For development/testing with GCC/Clang (not recommended for production):

```bash
SKIP_COMPILER_CHECK=1 ./scripts/host_build.sh RelWithDebInfo
```

### Build Options

- `BUILD_EXAMPLES=ON/OFF` - Build example programs (default: ON)
- `TEST_HARDWARE=ON/OFF` - Enable hardware integration tests (default: OFF, requires hardware)

Example:
```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx \
      -DTEST_HARDWARE=ON -DBUILD_EXAMPLES=ON
cmake --build build --parallel
```

### Installing Intel oneAPI Compilers

This project is designed to be built with Intel oneAPI compilers for optimal performance.

**Download and Install:**
```bash
# Visit: https://www.intel.com/content/www/us/en/developer/tools/oneapi.html
# Or use the devcontainer setup script:
sudo .devcontainer/setup-oneapi.sh
```

**Verify Installation:**
```bash
icx --version
icpx --version
```

### Script Permissions

If you get script-permission issues, run:
```bash
make setup-scripts
```

## Running Examples

The project includes practical examples demonstrating IP-over-USB functionality.

### Simple USB Network Demo

After building, you can run the example:

```bash
# On the USB device (gadget) side:
sudo ./build/examples/simple_usb_net device

# On the USB host side:
sudo ./build/examples/simple_usb_net host
```

For detailed instructions, prerequisites, and troubleshooting, see [`examples/README.md`](examples/README.md).

### Hardware Requirements for Examples

- Two Linux machines (or one machine + VM with USB passthrough)
- USB-C cable
- Root privileges
- Kernel modules: `g_ether` or configfs gadget support

### Safe Testing with VMs

For testing without two physical machines:

```bash
# Identify USB-C port (auto-detects best method: sysfs or libusb)
sudo ./scripts/identify-usb-c-port.sh

# Run VM-based tests
./scripts/run-vm-tests.sh
```

## Testing

### Unit Tests

```bash
# Build with tests
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
cmake --build build --parallel

# Run tests (when implemented)
ctest --test-dir build --output-on-failure
```

### Hardware Integration Tests

**WARNING:** Hardware tests require physical USB devices and root privileges.

```bash
# Build with hardware tests enabled
cmake -S . -B build -DTEST_HARDWARE=ON \
      -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
cmake --build build --parallel

# Run hardware tests (use with caution)
sudo ctest --test-dir build --output-on-failure
```

### CI/CD

The project uses GitHub Actions for continuous integration with security-hardened hardware test gating.

**Standard CI (runs on all PRs):**
- ✅ Automatic builds on push and pull requests
- ✅ DevContainer-based builds ensure consistency
- ✅ Builds with `TEST_HARDWARE=OFF` (no privileged access)

**Hardware Tests (security-gated):**
- 🔒 **Never run on forked PRs** (security protection)
- 🔒 Only run on PRs from the main repository with `hardware-tests` label
- 🔒 Or via manual `workflow_dispatch` with `run_hardware_tests: true`
- ⚠️ Requires privileged Docker and connected hardware

**To trigger hardware tests (maintainers only):**
1. For PRs from main repo: Add the `hardware-tests` label
2. For manual runs: Use workflow dispatch with `run_hardware_tests: true`

**Security Note**: Hardware tests use `--privileged` Docker mode and are restricted to trusted contexts only. See [SECURITY.md](SECURITY.md) for details.

2. Use workflow dispatch with `run_hardware_tests: true`

## Development

### VS Code DevContainer

Open the project in VS Code with the Remote-Containers extension:

1. Install the "Remote - Containers" extension
2. Open the project folder
3. Click "Reopen in Container" when prompted
4. The devcontainer will build with Intel oneAPI compilers pre-installed

### Project Structure

```
usb-c-soft-network/
├── .devcontainer/          # DevContainer configuration
│   ├── Dockerfile          # Container build with Intel oneAPI
│   ├── devcontainer.json   # VS Code devcontainer config
│   └── setup-oneapi.sh     # Intel oneAPI installation script
├── .github/                # CI/CD workflows
├── examples/               # Example programs
│   ├── simple_usb_net.c    # IP-over-USB demo
│   ├── CMakeLists.txt      # Examples build config
│   └── README.md           # Examples documentation
├── scripts/                # Build and utility scripts
│   ├── build.sh            # Container build script
│   ├── host_build.sh       # Host build script
│   ├── identify-usb-c-port.sh # Interactive port identification
│   └── run-vm-tests.sh     # VM-based testing
├── src/                    # Main source code
├── CMakeLists.txt          # Main build configuration
├── README.md               # This file
└── TODO.md                 # Project roadmap

```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Build and test locally
5. Submit a pull request

See [`TODO.md`](TODO.md) for the project roadmap and planned features.

## Troubleshooting

### Build Issues

**"Intel oneAPI compilers not found"**
- Install Intel oneAPI: https://www.intel.com/content/www/us/en/developer/tools/oneapi.html
- Or use `SKIP_COMPILER_CHECK=1` for development with system compilers

**"Permission denied" on scripts**
- Run `chmod +x scripts/*.sh` or `make setup-scripts`

### Runtime Issues

**"Cannot access /dev/bus/usb/"**
- Run with `sudo` or add your user to the appropriate group
- Check USB device permissions

**"No such device" (USB)**
- Verify cable is connected and device is detected: `lsusb`
- Check kernel logs: `dmesg | tail`
- Load required modules: `sudo modprobe g_ether`

**Network interface not appearing**
- Check `ip link show` for `usb0` or similar interface
- Verify kernel USB gadget support: `lsmod | grep usb`

## Performance Considerations

- **Intel oneAPI compilers** provide optimized code generation for Intel CPUs
- **Hardware tests** should only be run in controlled environments
- **USB bulk transfers** are preferred for maximum throughput
- **DMA operations** reduce CPU overhead (when hardware supports it)

