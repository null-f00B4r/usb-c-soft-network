#!/usr/bin/env bash
set -euo pipefail

# Build the project on host metal without Docker. This script is conservative and
# tries to detect Intel oneAPI compilers; if missing, prompts installer hints.

BUILD_DIR=build
BUILD_TYPE=${1:-RelWithDebInfo}
FORCE_NO_DOCKER=${FORCE_NO_DOCKER:-0}

echo "Starting host build (no Docker)."

if [[ -z "${SKIP_COMPILER_CHECK:-}" ]]; then
  if ! command -v icx >/dev/null 2>&1; then
    cat <<'WARN'
WARNING: Intel oneAPI compilers (icx/icpx) not found.
This project prefers Intel oneAPI compilers. Install them before proceeding.
See: https://www.intel.com/content/www/us/en/developer/tools/oneapi.html
WARN
    read -p "Continue build with system compilers (gcc/clang) anyway? [y/N] " yn
    case "$yn" in
        [Yy]*) echo "Continuing with system compilers.";;
        *) echo "Aborting; please install Intel oneAPI or run with SKIP_COMPILER_CHECK=1."; exit 1;;
    esac
  fi
fi

mkdir -p ${BUILD_DIR}

# Set Intel compilers if available
CMAKE_EXTRA_FLAGS=""
if command -v icx >/dev/null 2>&1 && command -v icpx >/dev/null 2>&1; then
  echo "Using Intel oneAPI compilers (icx/icpx)"
  CMAKE_EXTRA_FLAGS="-DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx"
fi

cmake -S . -B ${BUILD_DIR} -DCMAKE_BUILD_TYPE=${BUILD_TYPE} ${CMAKE_EXTRA_FLAGS}
cmake --build ${BUILD_DIR} --parallel

echo "Host build completed."
