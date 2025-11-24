#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR=build
BUILD_TYPE=${1:-RelWithDebInfo}
TEST_HARDWARE=${TEST_HARDWARE:-OFF}

echo "Using build type: ${BUILD_TYPE}"

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required but not found. Install CMake v4.1.2 or newer."
  exit 1
fi

# Locate Intel compilers (icx/icpx) and suggest them if missing
if command -v icx >/dev/null 2>&1 && command -v icpx >/dev/null 2>&1; then
  echo "Found Intel oneAPI compilers icx/icpx. Using them for build."
  export CC=icx
  export CXX=icpx
else
  echo "Intel oneAPI compilers (icx/icpx) not found in PATH. Please install them or run in the devcontainer with oneAPI installed."
  echo "Fallback: using system compilers (may fail due to project requirement for Intel compilers)."
fi

mkdir -p ${BUILD_DIR}
cmake -S . -B ${BUILD_DIR} -DCMAKE_BUILD_TYPE=${BUILD_TYPE} -DTEST_HARDWARE=${TEST_HARDWARE}
cmake --build ${BUILD_DIR} --parallel

echo "Done. Binary output in ${BUILD_DIR}" 
