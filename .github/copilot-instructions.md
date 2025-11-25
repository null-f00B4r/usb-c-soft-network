# Copilot / Agent instructions for usb-c-soft-network

Summary
- Purpose: The repository provides a software-based USB-C network/communication implementation on Linux. Primary languages: C (low-level USB & network stack), C++ (higher-level protocol/harness), Python (tests, scripts), and Bash (build scripts/automation).
- Platform: Linux only; agents should not assume macOS or Windows build compatibility.

What to inspect first
- Read `README.md` (root) for the project overview and platform/language choices.
- Look for build/config files: `CMakeLists.txt`, `Makefile`, `configure`, `setup.py`, `pyproject.toml`, or `requirements.txt`.
- Look for runtime and system-integration code: `src/`, `include/`, `lib/`, `scripts/`, `tests/`, and `docs/` directories.

**CRITICAL: This project does NOT use USB gadget mode**
- Architecture: Host-to-host USB-C networking using Linux Type-C subsystem
- Detection method: `/sys/class/typec/` sysfs interface (NOT libusb gadget enumeration)
- USB gadget mode (`g_ether`, `usb_gadget`, configfs) is NOT required for core functionality
- The examples (`simple_usb_net.c`) reference gadget mode for demonstration purposes only
- Primary use case: Direct peer-to-peer USB-C communication between two Linux hosts

Key development patterns & conventions for this codebase
- C for low-level USB hardware interaction and network stack; C++ for higher-level abstractions. Python is used for tests and automation (per README).
- Files expected: low-level code often in `src/usb` or `src/driver` with headers in `include/`.
- Network-layer handling should manifest in code managing packet framing and IP-over-USB; search for keywords like `usbnet`, `libusb`, `ioctl`, `tun`, `tap`, `netlink`, and `ifconfig`.
- **Host-to-host architecture**: Uses Type-C subsystem (`/sys/class/typec/`) for port detection and connection management
- **NOT gadget-based**: Keywords like `g_ether`, `usb_gadget`, `configfs` are used in examples for demo purposes but are NOT part of the core architecture
- Prefer small, targeted changes that preserve Linux-first behavior and avoid introducing OS-specific features without compatibility checks.

Safe build & debug workflows (Agent guidance)
- Always inspect for build files first. If `CMakeLists.txt` exists, an expected workflow is:
  ```bash
  mkdir -p build && cd build
  cmake .. && make -j$(nproc)
  sudo make install (only if necessary; verify artifacts and tests first)
  ```
- For Make-only repositories, try `make` then `make test` if present.
- Python tooling: if `requirements.txt` or `pyproject.toml` exists, build and test in an isolated venv:
  ```bash
  python3 -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt  # or pip install -e .
  pytest  # run python tests
  ```
- Hardware safety: avoid running arbitrary code as root/mounting devices on the host system. Prefer using a VM/QEMU or container with USB passthrough or emulated devices for local testing. If a change requires host USB access, explicitly call it out in the PR and provide a reproducible safe test plan.

Search patterns that are highly relevant
- **Type-C subsystem (PRIMARY)**: `/sys/class/typec/`, `CONFIG_TYPEC`, `typec_ucsi`, `ucsi_acpi`, `typec` kernel module
- **Host-to-host USB-C**: `libusb`, direct USB communication patterns, Type-C port detection
- **Networking stack**: `tun`, `tap`, `netlink`, `ioctl`, `ethertype`, `arp`, `ip`, `ifconfig`, `tcpdump`
- **Low-level I/O**: `open()`, `read()`, `write()`, `ioctl(`, `/dev/bus/usb/`, `/sys/class/typec/`
- **Gadget mode (examples only, NOT core)**: `g_ether`, `usbnet`, `gadget`, `usb_gadget`, `configfs` - these are used in demo examples but not in the core implementation
- **Packaging / build**: `CMakeLists.txt`, `Makefile`, `configure`, `setup.py`, `requirements.txt`

Testing & verification guidance
- Look for existing `tests/` directory. If Python tests are present, use `pytest`.
- If there are hardware-specific integration tests, expect these to be optional or gated behind flags (eg `TEST_HARDWARE=1`); do not run hardware-integrated tests by default.
- Use `dmesg`/`journalctl` to view kernel logs if you need to diagnose device attachment and driver behavior.
- Network traffic can be inspected with `tcpdump -i <iface>` or by capturing the driver-level frames. Use `sudo` only after verifying the test is safe.

Version control & PR Guidance
- Respect existing import and module structures; keep hardware-interaction code separate from protocol/format and from tests.
- Provide a short, clear description for PRs that touch device or kernel-facing code: list manual steps for reproducing the change safely, relevant logs and expected behaviors (interfaces up, packets forwarded, no kernel oops/panic).

What not to do (safety and maintenance constraints)
- Do not introduce host-specific or non-Linux code paths without a clear reason and regression tests.
- Avoid running un-vetted binaries with `sudo` during automated testing.
- Avoid changes that rely on kernel module recompiles or privileged operations without clear steps to revert and logs to show no regression.

Ambiguities and when to ask maintainers
- If there are no build files or tests, ask whether the project owner prefers `CMake`, `Make`, or `setup.py` for C/C++/Python builds.
- For hardware tests or CI integration, ask if there's a preferred simulated environment, a CI lab, or a hardware matrix.

Quick start actions for AI agents
1. Open `README.md` => confirm languages and platform (Linux, C/C++, Python).  
2. Search repo for: `CMakeLists.txt`, `Makefile`, `setup.py`, `requirements.txt`, `src/`, `include/`, `tests/`.  
3. Search repo for hardware and network keywords: `libusb`, `usbnet`, `g_ether`, `tun`, `tap`, `ioctl`.  
4. If build files exist: run build in a safe environment and try the test suite. If tests are missing: open a small issue requesting a CI/test harness and a developer note about safe testing methodology.
5. If you are running locally without Docker: use `scripts/host_build.sh`. You may be prompted to install Intel oneAPI; prefer running with `SKIP_COMPILER_CHECK=1` if you intend to build with system compilers for non-production testing.
   - Example (host):
     ```bash
     SKIP_COMPILER_CHECK=1 ./scripts/host_build.sh RelWithDebInfo
     ```
   - Example (devcontainer/docker):
     ```bash
     docker build -f .devcontainer/Dockerfile -t usb-c-soft-network-ci:latest .
     docker run --rm -v "$PWD:/workspaces/usb-c-soft-network" usb-c-soft-network-ci:latest ./scripts/build.sh
     ```

Helpful scripts and files to inspect
- `scripts/build.sh` — builds the repo inside a container and will prefer Intel oneAPI compilers.
- `scripts/host_build.sh` — host build script for non-Docker builds, with warnings if oneAPI is missing.
- `scripts/identify-usb-c-port.sh` — interactive script to identify the target USB-C port using sysfs or libusb detection methods.
- `scripts/run-vm-tests.sh` — lightweight QEMU-run example for VM-based hardware testing.
- `.devcontainer/Dockerfile` and `.devcontainer/devcontainer.json` — devcontainer configuration and setup helper `setup-oneapi.sh`.


Examples from this repository (discoverable)
- The primary documentation is `README.md`—it explicitly says: "C for low-level USB-C interactions and network stack implementation; C++ for higher-level abstractions; Python for testing" and "Platform: Linux".

Final note
- This repo deals with hardware-level behavior: be conservative. Prefer to make changes that are testable in simulated or virtualized environments; if changes require raw device access, provide a safe reproduction and revert instructions.

Questions for maintainers/PR reviewers
- Do you have a preferred build system (Make/CMake/meson)?
- How should we handle hardware integration tests, and does a CI lab exist for PR verification?
- Where should contributors place new tests and hardware-protection helpers (ie `tests/`, `integration/`, `tools/`)?

-- End of agent guidance

### Build & Tooling specifics (repo conventions)
- The repo requires: `cmake_minimum_required(VERSION 4.1.2)`; C and C++ standards are 23.
- The project is configured to be built with Intel oneAPI compilers by default. CMake checks the compiler at configure-time and will fail when the detected compiler is not Intel (icx/icpx / IntelLLVM).
- Hardware integration tests are gated with the `TEST_HARDWARE` CMake option. Always leave this OFF by default unless running in a controlled environment.

### Runtime Requirements (verified by check-system-requirements.sh)
**Kernel Requirements (CRITICAL):**
- Linux kernel 5.10+ with Type-C subsystem enabled
- `CONFIG_TYPEC=m` or `CONFIG_TYPEC=y` - Type-C subsystem
- `CONFIG_TYPEC_UCSI=m` - USB Type-C Connector System Software Interface (for most systems)
- `CONFIG_UCSI_ACPI=m` - ACPI UCSI driver (common on x86/x64 systems)
- Type-C kernel modules must be loadable: `typec`, `typec_ucsi`

**Hardware Requirements:**
- USB-C port(s) with data support (not charge-only)
- Data-capable USB-C cable (not charge-only)
- Type-C port manager exposed through `/sys/class/typec/portX`
- Root/sudo privileges for hardware access

**Build Requirements:**
- CMake 4.1.2 or newer
- C23 and C++23 compiler support
- Intel oneAPI compilers (icx/icpx) - recommended
  - Or GCC/Clang with `SKIP_COMPILER_CHECK=1` environment variable (development only)
- libusb-1.0 development headers (`libusb-1.0-dev` on Debian/Ubuntu)
- pkg-config tool

**NOT Required:**
- USB gadget mode support (this is NOT a gadget-mode project)
- `g_ether` kernel module (used in examples for demo purposes only)
- USB gadget configfs (not part of core architecture)
- Specialized USB hardware or adapters

### Devcontainer & oneAPI
- A devcontainer is provided at `.devcontainer/` with a `Dockerfile` (based on `debian:latest-slim`) that installs base build tools and includes `setup-oneapi.sh` to install Intel oneAPI compilers. Using the devcontainer is the recommended safe way to build or run tests.
  - If you prefer to use an image that already includes the Intel oneAPI SDK, build the devcontainer with: `docker build --build-arg BASE_IMAGE=intel/oneapi-basekit:latest -f .devcontainer/Dockerfile -t usb-c-soft-network-ci:latest .` and then run the container as shown in the Quick Start.
- If you must install Intel oneAPI on a host machine, follow vendor instructions: https://www.intel.com/content/www/us/en/developer/tools/oneapi.html. Tests are expected to run with Intel compilers; the scripts will fallback to system compilers only when explicitly configured to do so.

### CI and gated HW tests
- CI uses a matrix to build in the devcontainer image and runs in `ubuntu-latest` runner. Hardware tests are gated — they run only when the `hardware-tests` label is present on a PR or when `workflow_dispatch` input `run_hardware_tests` is set to `true`.
- CI builds are executed inside the created devcontainer Docker image to provide a consistent environment and to allow on-demand oneAPI installation.

### Hardware Safety & Passthrough
- Use the provided `scripts/identify-usb-c-port.sh` script to identify the target USB-C port. It auto-detects the best method (sysfs for host-to-host, libusb for gadget mode) and generates a config file with device information. Always verify the device with `lsusb` and `dmesg` before passing it to a container.
- Hardware tests are explicitly gated with `TEST_HARDWARE`. They are not included in default PR builds; they require physical hardware and privileged runners.

### Using MCP servers (sequential-thinking and Memory)
- When performing a non-trivial, multi-step task, prefer using the `sequential-thinking` MCP server to generate a plan that the agent will execute step-by-step.
  - Example workflow: Request a plan from `sequential-thinking` for 'Add USB passthrough test and CI gate'. The plan should include: compile-only checks, adding `TEST_HARDWARE`-flagged tests, a small VM run example, an updated devcontainer, and a gated CI job.
- Use the `memory` MCP server (eg, `modelcontextprotocol/server-memory`) to store important artifacts and results such as build artifact paths, devcontainer image SHAs, selected USB device paths, or test summaries so future runs can re-use them.
  - Example observations to store in Memory:
    - `devcontainer_image_sha: <sha>` — so future steps reference the correct image
    - `build_artifact_path: /workspaces/usb-c-soft-network/build` — for downstream runners
    - `selected_usb_device: /dev/bus/usb/002/003` — for hardware passthrough reproducibility
    - `last_hardware_test_result: PASS/FAIL` — pass/fail summary and a small stdout snippet


---
If anything in this guidance is unclear or you want the repo to prefer a different compilation model, please open an issue asking for a policy decision on this repository's build and test strategy.

