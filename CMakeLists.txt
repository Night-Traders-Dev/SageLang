cmake_minimum_required(VERSION 3.13)

# ============================================================================
# Project Configuration
# ============================================================================

project(SageLang VERSION 0.8.0 LANGUAGES C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ============================================================================
# Build Options
# ============================================================================

option(BUILD_PICO "Build for Raspberry Pi Pico (RP2040)" OFF)
option(ENABLE_DEBUG "Enable debug symbols and logging" OFF)
option(ENABLE_TESTS "Build test executables" OFF)

# ============================================================================
# Pico SDK Setup (if building for Pico)
# ============================================================================

if(BUILD_PICO)
    # Include Pico SDK (must have pico_sdk_import.cmake in project root)
    include(pico_sdk_import.cmake)

    # Initialize the Pico SDK
    pico_sdk_init()

    message(STATUS "Building for Raspberry Pi Pico (RP2040)")
    add_compile_definitions(PICO_BUILD=1)
endif()

# ============================================================================
# Compiler Flags
# ============================================================================

if(ENABLE_DEBUG)
    add_compile_options(-g -O0 -DDEBUG)
    message(STATUS "Debug mode enabled")
else()
    add_compile_options(-O2)
endif()

# Warning flags
add_compile_options(
    -Wall
    -Wextra
    -Wpedantic
    -Wno-unused-parameter
    -Wno-unused-function
)

# Add POSIX source for strdup
add_compile_definitions(_POSIX_C_SOURCE=200809L)

# ============================================================================
# Source Files
# ============================================================================

set(SAGE_CORE_SOURCES
    src/ast.c
    src/env.c
    src/gc.c
    src/interpreter.c
    src/lexer.c
    src/module.c
    src/parser.c
    src/value.c
)

set(SAGE_MAIN_SOURCE
    src/main.c
)

set(SAGE_HEADERS
    include/ast.h
    include/env.h
    include/gc.h
    include/interpreter.h
    include/lexer.h
    include/module.h
    include/token.h
    include/value.h
)

# Hardware abstraction sources (optional)
set(SAGE_BOARD_SOURCES
    boards/pico_gpio.c
)

set(SAGE_BOARD_HEADERS
    include/pico_gpio.h
)

# Optional heartbeat implementation
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/heartbeat.c")
    list(APPEND SAGE_CORE_SOURCES src/heartbeat.c)
    message(STATUS "Including heartbeat.c")
endif()

# ============================================================================
# Include Directories
# ============================================================================

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# ============================================================================
# Main Executable (Desktop/Linux build)
# ============================================================================

if(NOT BUILD_PICO)
    # Standard desktop executable
    add_executable(sage
        ${SAGE_MAIN_SOURCE}
        ${SAGE_CORE_SOURCES}
    )

    # Link math library
    target_link_libraries(sage m)

    # Install target
    install(TARGETS sage DESTINATION bin)

    message(STATUS "Building standard executable: sage")
endif()

# ============================================================================
# Pico Executable (Embedded build)
# ============================================================================

if(BUILD_PICO)
    # Pico executable with GPIO support
    add_executable(sage_pico
        ${SAGE_MAIN_SOURCE}
        ${SAGE_CORE_SOURCES}
        ${SAGE_BOARD_SOURCES}
    )

    # Link Pico SDK libraries
    target_link_libraries(sage_pico
        pico_stdlib
        pico_multicore
        pico_time
        hardware_gpio
        hardware_sync
        hardware_uart
        hardware_irq
    )

    # Enable USB output, disable UART output
    pico_enable_stdio_usb(sage_pico 1)
    pico_enable_stdio_uart(sage_pico 0)

    # Create map/bin/hex/uf2 files
    pico_add_extra_outputs(sage_pico)

    message(STATUS "Building Pico executable: sage_pico.uf2")

    # Optional: Build heartbeat example
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/heartbeat.c")
        add_executable(heartbeat_example
            src/heartbeat.c
            ${SAGE_BOARD_SOURCES}
        )

        target_link_libraries(heartbeat_example
            pico_stdlib
            pico_multicore
            pico_time
            hardware_gpio
            hardware_sync
        )

        pico_enable_stdio_usb(heartbeat_example 1)
        pico_enable_stdio_uart(heartbeat_example 0)
        pico_add_extra_outputs(heartbeat_example)

        message(STATUS "Building heartbeat example: heartbeat_example.uf2")
    endif()
endif()

# ============================================================================
# Test Executables (optional)
# ============================================================================

if(ENABLE_TESTS AND NOT BUILD_PICO)
    enable_testing()

    # Lexer test
    add_executable(test_lexer
        tests/test_lexer.c
        ${SAGE_CORE_SOURCES}
    )
    target_link_libraries(test_lexer m)
    add_test(NAME LexerTest COMMAND test_lexer)

    # Parser test
    add_executable(test_parser
        tests/test_parser.c
        ${SAGE_CORE_SOURCES}
    )
    target_link_libraries(test_parser m)
    add_test(NAME ParserTest COMMAND test_parser)

    # GC test
    add_executable(test_gc
        tests/test_gc.c
        ${SAGE_CORE_SOURCES}
    )
    target_link_libraries(test_gc m)
    add_test(NAME GCTest COMMAND test_gc)

    message(STATUS "Test executables enabled")
endif()

# ============================================================================
# Custom Targets (Desktop only)
# ============================================================================

if(NOT BUILD_PICO)
    # Run sage with an example
    add_custom_target(run_example
        COMMAND $<TARGET_FILE:sage> ${CMAKE_CURRENT_SOURCE_DIR}/examples/hello.sage
        DEPENDS sage
        COMMENT "Running hello.sage example"
    )

    # Run all examples
    add_custom_target(run_all_examples
        COMMAND bash -c "for f in ${CMAKE_CURRENT_SOURCE_DIR}/examples/*.sage; do echo '=== $$f ==='; $<TARGET_FILE:sage> $$f; done"
        DEPENDS sage
        COMMENT "Running all .sage examples"
    )

    # Clean build artifacts
    add_custom_target(clean_all
        COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}
        COMMENT "Cleaning all build artifacts"
    )
endif()

# ============================================================================
# Installation (Desktop only)
# ============================================================================

if(NOT BUILD_PICO)
    # Install sage executable
    install(TARGETS sage
        RUNTIME DESTINATION bin
    )

    # Install standard library modules
    install(DIRECTORY lib/
        DESTINATION share/sage/lib
        FILES_MATCHING PATTERN "*.sage"
    )

    # Install examples
    install(DIRECTORY examples/
        DESTINATION share/sage/examples
        FILES_MATCHING PATTERN "*.sage"
    )

    # Install documentation
    install(FILES 
        README.md
        ROADMAP.md
        LICENSE
        documentation/SageLang_Guide.md
        DESTINATION share/doc/sage
    )
endif()

# ============================================================================
# Print Configuration Summary
# ============================================================================

message(STATUS "")
message(STATUS "=================================================")
message(STATUS "SageLang v${PROJECT_VERSION} Configuration")
message(STATUS "=================================================")
message(STATUS "Build type:      ${CMAKE_BUILD_TYPE}")
message(STATUS "C Compiler:      ${CMAKE_C_COMPILER}")
message(STATUS "Build for Pico:  ${BUILD_PICO}")
message(STATUS "Debug mode:      ${ENABLE_DEBUG}")
message(STATUS "Tests enabled:   ${ENABLE_TESTS}")
message(STATUS "Source dir:      ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "Binary dir:      ${CMAKE_BINARY_DIR}")

if(BUILD_PICO)
    message(STATUS "")
    message(STATUS "Pico SDK Configuration:")
    message(STATUS "  - Pico SDK path: ${PICO_SDK_PATH}")
    message(STATUS "  - Board: pico (RP2040)")
    message(STATUS "  - Output: sage_pico.uf2")
endif()

message(STATUS "=================================================")
message(STATUS "")

# ============================================================================
# Documentation
# ============================================================================

# Usage:
# 
# Standard build (Linux/Desktop):
#   mkdir build && cd build
#   cmake ..
#   make -j$(nproc)
#   ./sage ../examples/hello.sage
#
# Pico build:
#   mkdir build_pico && cd build_pico
#   cmake -DBUILD_PICO=ON ..
#   make -j$(nproc)
#   # Copy sage_pico.uf2 to Pico in BOOTSEL mode
#
# Debug build:
#   cmake -DENABLE_DEBUG=ON ..
#   make
#
# With tests:
#   cmake -DENABLE_TESTS=ON ..
#   make
#   ctest
#
# Run examples (desktop only):
#   make run_example
#   make run_all_examples
#
# Install:
#   sudo make install