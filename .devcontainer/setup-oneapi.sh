#!/usr/bin/env bash
set -euo pipefail

echo "(Devcontainer) OneAPI setup script run inside container."
echo "Attempting to configure repository and install oneapi compilers."

if command -v icx >/dev/null 2>&1; then
  echo "icx already installed"
  exit 0
fi

if [ -f /etc/debian_version ]; then
  echo "Adding Intel apt repo (best-effort)."
  wget -qO - https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SIGNING-KEY | gpg --dearmor | sudo tee /usr/share/keyrings/intel-archive-keyring.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/intel-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" | sudo tee /etc/apt/sources.list.d/intel-oneapi.list
  sudo apt-get update
  sudo apt-get install -y intel-oneapi-compiler-dpcpp-cpp-and-cpp-classic || true
fi

if ! command -v icx >/dev/null 2>&1; then
  echo "Intel oneAPI not installed or not available for this distribution. If needed, use a base image that already contains oneAPI or install the tarball installers per Intel documentation."
fi

echo "END of setup-oneapi.sh"
