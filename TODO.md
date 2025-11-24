# TODO: usb-c-soft-network — Roadmap and Milestones

This file outlines recommended milestones and detailed tasks to help contributors and agents work on the project without prior deep domain knowledge. Each milestone includes completion criteria and test steps.

## Milestone 1 — Repository Bootstrapping (Priority: High) ✅ COMPLETED
Objective: Make the repo buildable in a container with a minimal runnable example.

Tasks:
- [x] Add CMake build skeleton (CMakeLists.txt) and a placeholder entrypoint in `src/main.c` or `src/main.cpp`.
  - Success: `./scripts/build.sh` completes without fatal CMake errors inside the devcontainer.
  - Test: Build in the devcontainer with `docker build -f .devcontainer/Dockerfile -t usb-c-soft-network-ci:latest .` and run `docker run --rm usb-c-soft-network-ci:latest ./scripts/build.sh`.
- [x] Add `scripts/build.sh` and `scripts/host_build.sh` to support building inside container and on host.
  - Success: Build scripts detect Intel compilers and provide friendly fallbacks.
  - Test: Run `./scripts/build.sh` in devcontainer; run `SKIP_COMPILER_CHECK=1 ./scripts/host_build.sh` on host.

## Milestone 2 — Devcontainer + OneAPI (Priority: High) ✅ COMPLETED
Objective: Add devcontainer and oneAPI installation workflow so developers can start quickly.

Tasks:
- [x] Add `.devcontainer/Dockerfile` and `.devcontainer/devcontainer.json`.
  - Success: VS Code can reopen the workspace in the devcontainer without human intervention.
  - Test: Use `Remote-Containers: Reopen in Container` or `docker build` step in CI.
- [x] Add setup script to install Intel oneAPI compilers.
  - Success: `icx --version` and `icpx --version` return valid output inside the container.
  - Test: Run `sudo /usr/local/bin/setup-oneapi.sh` inside devcontainer and verify version output.

## Milestone 3 — CI and Gated Hardware Tests (Priority: High) ✅ COMPLETED
Objective: Add CI pipeline that builds in the devcontainer and gates hardware tests behind flags and labels.

Tasks:
- [x] Add GitHub Action to build in the devcontainer.
  - Success: Build job completes and produces built artifacts on push.
  - Test: Confirm `./scripts/build.sh` executes successfully in the CI image.
- [x] Add a gated hardware testing job that runs only when a `hardware-tests` label is set or `workflow_dispatch` input `run_hardware_tests=true`.
  - Success: Job doesn't run by default; it runs when triggered and uses a privileged Docker run.
  - Test: Trigger a workflow dispatch with `run_hardware_tests: 'true'` and confirm hardware job runs.

## Milestone 4 — Hardware Passthrough Tools and Tests (Priority: Medium) ✅ COMPLETED
Objective: Create safe tooling for hardware passthrough, and small tests that can be run with hardware connected.

Tasks:
- [x] Add `scripts/find-usb-c-ports.sh` to discover /sys/class/typec and `lsusb` outputs.
  - Success: Script lists candidate devices and prints a sample Docker passthrough command.
  - Test: Run the script on a machine with Type-C ports.
- [x] Add hardware-integration tests that are gated behind `TEST_HARDWARE=ON` in CMake.
  - Success: CMake variable controls tests compiled with `-DTEST_HARDWARE=ON`.
  - Test: `cmake -DTEST_HARDWARE=ON` triggers hardware tests being compiled or additional tests being executed.
- [x] Add `scripts/run-vm-tests.sh` for QEMU-based testing with USB passthrough.
  - Success: Script provides safe VM-based testing environment.
  - Test: Run with USB_BUSDEV set to test VM integration.

## Milestone 5 — Documentation and Examples (Priority: Medium)
Objective: Make it easy for maintainers and contributors to understand and extend the project.

Tasks:
- [ ] Add `example/` or `samples/` with a small IP-over-USB demo.
  - Success: A small demo can be run on two machines (or inside two VMs) with Type-C passthrough.
  - Test: Demonstrate a ping or simple file transfer over the USB-C emulated network.
- [ ] Expand README with build steps, devcontainer usage, and testing instructions.
  - Success: Developer can follow README to build and verify the project end-to-end inside the devcontainer.
  - Test: Follow the README from a fresh machine (or clean VM) and successfully build and run the demo.

## Milestone 6 — Security, CI, and Vaulting Secrets (Priority: Low)
Objective: Harden the CI and local dev process for hardware-sensitive builds.

Tasks:
- [ ] Ensure hardware tests require explicit consent and are run only in a controlled environment (no secrets leaked).
  - Success: No CI or workflows expose secrets to untrusted forks or PR builds; hardware tests require `workflow_dispatch` with secrets protected.
  - Test: Run a PR build from a fork and show hardware tests are not executed.

---
For additional context, see `.github/copilot-instructions.md` which provides guidance for AI agents working on this repo.
