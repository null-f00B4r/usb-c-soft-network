cmake_minimum_required(VERSION 4.1.2)

project(usb-c-soft-network LANGUAGES C CXX)

# Compiler standards
set(CMAKE_C_STANDARD 23)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED TRUE)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)

# Option to enable hardware tests
option(TEST_HARDWARE "Enable hardware integration tests (dangerous)" OFF)

if(NOT CMAKE_C_COMPILER)
  message(STATUS "C compiler not explicitly set; using system default")
endif()
if(NOT CMAKE_CXX_COMPILER)
  message(STATUS "C++ compiler not explicitly set; using system default")
endif()

# Allow override via environment variable for testing/development
if(NOT DEFINED ENV{SKIP_COMPILER_CHECK})
  if(NOT (CMAKE_C_COMPILER_ID MATCHES "Intel" OR CMAKE_C_COMPILER_ID MATCHES "IntelLLVM"))
    message(FATAL_ERROR "This project is configured to be built using Intel oneAPI compilers (icx/icpx). Found ${CMAKE_C_COMPILER_ID}. Please install Intel oneAPI and configure CMake accordingly, or set SKIP_COMPILER_CHECK=1 to bypass this check.")
  endif()
else()
  message(WARNING "Compiler check skipped (SKIP_COMPILER_CHECK set). Using ${CMAKE_C_COMPILER_ID}. For production builds, use Intel oneAPI compilers.")
endif()

add_compile_options($<$<C_COMPILER_ID:Intel>:-std=c23>)
add_compile_options($<$<CXX_COMPILER_ID:Intel>:-std=c++23>)

# Minimal target so the project can start
add_executable(dummy src/main.c)
target_compile_definitions(dummy PRIVATE TEST_HARDWARE=$<BOOL:${TEST_HARDWARE}>)

install(TARGETS dummy DESTINATION bin)

# Examples
option(BUILD_EXAMPLES "Build example programs" ON)
if(BUILD_EXAMPLES)
  add_subdirectory(examples)
endif()
