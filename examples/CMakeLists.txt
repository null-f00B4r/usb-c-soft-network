# Examples CMakeLists.txt

# Simple USB network demo
add_executable(simple_usb_net simple_usb_net.c)
target_compile_definitions(simple_usb_net PRIVATE TEST_HARDWARE=$<BOOL:${TEST_HARDWARE}>)

install(TARGETS simple_usb_net DESTINATION bin)
