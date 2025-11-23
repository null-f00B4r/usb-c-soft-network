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

if(NOT (CMAKE_C_COMPILER_ID MATCHES "Intel" OR CMAKE_C_COMPILER_ID MATCHES "IntelLLVM"))
  message(FATAL_ERROR "This project is configured to be built using Intel oneAPI compilers (icx/icpx). Found ${CMAKE_C_COMPILER_ID}. Please install Intel oneAPI and configure CMake accordingly.")
endif()

add_compile_options($<$<C_COMPILER_ID:Intel>:-std=c23>)
add_compile_options($<$<CXX_COMPILER_ID:Intel>:-std=c++23>)

# Minimal target so the project can start
add_executable(dummy src/main.c)
target_compile_definitions(dummy PRIVATE TEST_HARDWARE=$<BOOL:${TEST_HARDWARE}>)

install(TARGETS dummy DESTINATION bin)
