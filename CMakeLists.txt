cmake_minimum_required(VERSION 3.13)

# ============================================================================
# CRITICAL: Pico SDK Import MUST come BEFORE project()
# ============================================================================

# Build Options - MUST be set before pico_sdk_import
option(BUILD_PICO "Build for Raspberry Pi Pico (RP2040)" OFF)
option(BUILD_SAGE "Build using self-hosted Sage interpreter (bootstrap)" OFF)
option(ENABLE_DEBUG "Enable debug symbols and logging" OFF)
option(ENABLE_TESTS "Build test executables" OFF)

# Import Pico SDK if building for Pico (BEFORE project())
if(BUILD_PICO)
    # Set Pico platform before anything else
    set(PICO_PLATFORM rp2040)

    # Include Pico SDK (must have pico_sdk_import.cmake in project root)
    include(pico_sdk_import.cmake)
endif()

# ============================================================================
# Project Configuration
# ============================================================================

project(SageLang VERSION 1.0.0 LANGUAGES C CXX ASM)

# Initialize Pico SDK AFTER project() but before anything else
if(BUILD_PICO)
    pico_sdk_init()
    message(STATUS "Building for Raspberry Pi Pico (RP2040)")
    add_compile_definitions(PICO_BUILD=1)
endif()

# ============================================================================
# Standard Settings
# ============================================================================

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

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

# Add POSIX source for strdup (desktop only)
if(NOT BUILD_PICO)
    add_compile_definitions(_POSIX_C_SOURCE=200809L)
endif()

# Find networking dependencies (desktop only)
if(NOT BUILD_PICO)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(CURL REQUIRED libcurl)
    pkg_check_modules(OPENSSL REQUIRED openssl)
    pkg_check_modules(VULKAN vulkan)
    pkg_check_modules(GLFW glfw3)
    include_directories(${CURL_INCLUDE_DIRS} ${OPENSSL_INCLUDE_DIRS})
    if(VULKAN_FOUND)
        include_directories(${VULKAN_INCLUDE_DIRS})
        add_compile_definitions(SAGE_HAS_VULKAN=1)
    endif()
    if(GLFW_FOUND)
        include_directories(${GLFW_INCLUDE_DIRS})
        add_compile_definitions(SAGE_HAS_GLFW=1)
    endif()
endif()

# ============================================================================
# Source Files
# ============================================================================

set(SAGE_CORE_SOURCES
    src/c/ast.c
    src/c/codegen.c
    src/c/compiler.c
    src/c/constfold.c
    src/c/dce.c
    src/c/diagnostic.c
    src/c/env.c
    src/c/formatter.c
    src/c/gc.c
    src/c/inline.c
    src/c/interpreter.c
    src/c/linter.c
    src/c/lexer.c
    src/c/llvm_backend.c
    src/c/lsp.c
    src/c/module.c
    src/c/net.c
    src/c/parser.c
    src/c/pass.c
    src/c/sage_thread.c
    src/c/stdlib.c
    src/c/typecheck.c
    src/c/value.c
    src/c/graphics.c
)

set(SAGE_VM_SOURCES
    src/vm/bytecode.c
    src/vm/program.c
    src/vm/runtime.c
    src/vm/vm.c
)

set(SAGE_MAIN_SOURCE
    src/c/main.c
)

set(SAGE_HEADERS
    include/ast.h
    include/codegen.h
    include/compiler.h
    include/diagnostic.h
    include/env.h
    include/formatter.h
    include/gc.h
    include/interpreter.h
    include/lexer.h
    include/linter.h
    include/llvm_backend.h
    include/lsp.h
    include/module.h
    include/pass.h
    include/repl.h
    include/sage_thread.h
    include/token.h
    include/typecheck.h
    include/value.h
)

# Hardware abstraction sources (Pico only)
set(SAGE_BOARD_SOURCES
    boards/pico_gpio.c
)

set(SAGE_BOARD_HEADERS
    include/pico_gpio.h
)

# Self-hosted Sage sources
set(SAGE_SELF_HOST_SOURCES
    src/sage/token.sage
    src/sage/lexer.sage
    src/sage/ast.sage
    src/sage/parser.sage
    src/sage/bytecode.sage
    src/sage/interpreter.sage
    src/sage/sage.sage
)

# Optional heartbeat implementation
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/c/heartbeat.c")
    list(APPEND SAGE_CORE_SOURCES src/c/heartbeat.c)
    message(STATUS "Including heartbeat.c")
endif()

# ============================================================================
# Include Directories
# ============================================================================

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src/c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/vm
)

# ============================================================================
# Main Executable (Desktop/Linux C build)
# ============================================================================

if(NOT BUILD_PICO AND NOT BUILD_SAGE)
    # Standard desktop executable built from C
    add_executable(sage
        ${SAGE_MAIN_SOURCE}
        ${SAGE_CORE_SOURCES}
        ${SAGE_VM_SOURCES}
    )

    # Link math, pthread, dl, and optional GPU libraries
    target_link_libraries(sage m dl pthread ${CURL_LIBRARIES} ${OPENSSL_LIBRARIES} ${VULKAN_LIBRARIES} ${GLFW_LIBRARIES})

    # LSP server binary (standalone)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/c/lsp_main.c")
        add_executable(sage-lsp
            src/c/lsp_main.c
            ${SAGE_CORE_SOURCES}
            ${SAGE_VM_SOURCES}
        )
        target_link_libraries(sage-lsp m dl pthread ${CURL_LIBRARIES} ${OPENSSL_LIBRARIES} ${VULKAN_LIBRARIES} ${GLFW_LIBRARIES})
        message(STATUS "Building LSP server: sage-lsp")
    endif()

    message(STATUS "Building C executable: sage")
endif()

# ============================================================================
# Self-Hosted Sage Build (Bootstrap)
# ============================================================================

if(BUILD_SAGE AND NOT BUILD_PICO)
    # First build the C host interpreter (needed to bootstrap)
    add_executable(sage
        ${SAGE_MAIN_SOURCE}
        ${SAGE_CORE_SOURCES}
        ${SAGE_VM_SOURCES}
    )
    target_link_libraries(sage m dl pthread ${CURL_LIBRARIES} ${OPENSSL_LIBRARIES} ${VULKAN_LIBRARIES} ${GLFW_LIBRARIES})

    # Custom target: run a .sage file through the self-hosted interpreter
    # Usage: cmake --build build -- sage_boot SAGE_FILE=path/to/file.sage
    add_custom_target(sage_boot
        COMMAND $<TARGET_FILE:sage>
            ${CMAKE_CURRENT_SOURCE_DIR}/src/sage/sage.sage
            ${SAGE_FILE}
        DEPENDS sage
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/src/sage
        COMMENT "Running via self-hosted Sage interpreter"
    )

    # Self-hosted test targets
    add_custom_target(test_selfhost_lexer
        COMMAND $<TARGET_FILE:sage>
            ${CMAKE_CURRENT_SOURCE_DIR}/src/sage/test/test_lexer.sage
        DEPENDS sage
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/src/sage
        COMMENT "Running self-hosted lexer tests"
    )

    add_custom_target(test_selfhost_parser
        COMMAND $<TARGET_FILE:sage>
            ${CMAKE_CURRENT_SOURCE_DIR}/src/sage/test/test_parser.sage
        DEPENDS sage
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/src/sage
        COMMENT "Running self-hosted parser tests"
    )

    add_custom_target(test_selfhost_interpreter
        COMMAND $<TARGET_FILE:sage>
            ${CMAKE_CURRENT_SOURCE_DIR}/src/sage/test/test_interpreter.sage
        DEPENDS sage
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/src/sage
        COMMENT "Running self-hosted interpreter tests"
    )

    add_custom_target(test_selfhost_bootstrap
        COMMAND $<TARGET_FILE:sage>
            ${CMAKE_CURRENT_SOURCE_DIR}/src/sage/test/test_bootstrap.sage
        DEPENDS sage
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/src/sage
        COMMENT "Running bootstrap integration tests"
    )

    # Run all self-hosted tests
    add_custom_target(test_selfhost
        DEPENDS test_selfhost_lexer test_selfhost_parser
                test_selfhost_interpreter test_selfhost_bootstrap
        COMMENT "Running all self-hosted tests"
    )

    message(STATUS "Building self-hosted (Sage bootstrap) mode")
    message(STATUS "  Host binary: sage")
    message(STATUS "  Bootstrap:   src/sage/sage.sage")
    message(STATUS "  Targets:     sage_boot, test_selfhost")
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
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/c/heartbeat.c")
        add_executable(heartbeat_example
            src/c/heartbeat.c
            src/c/sage_thread.c
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
# Test Executables (optional, C tests)
# ============================================================================

if(ENABLE_TESTS AND NOT BUILD_PICO)
    enable_testing()

    # Lexer test
    add_executable(test_lexer
        tests/test_lexer.c
        ${SAGE_CORE_SOURCES}
    )
    target_link_libraries(test_lexer m dl pthread ${CURL_LIBRARIES} ${OPENSSL_LIBRARIES})
    add_test(NAME LexerTest COMMAND test_lexer)

    # Parser test
    add_executable(test_parser
        tests/test_parser.c
        ${SAGE_CORE_SOURCES}
    )
    target_link_libraries(test_parser m dl pthread ${CURL_LIBRARIES} ${OPENSSL_LIBRARIES})
    add_test(NAME ParserTest COMMAND test_parser)

    # GC test
    add_executable(test_gc
        tests/test_gc.c
        ${SAGE_CORE_SOURCES}
    )
    target_link_libraries(test_gc m dl pthread ${CURL_LIBRARIES} ${OPENSSL_LIBRARIES})
    add_test(NAME GCTest COMMAND test_gc)

    message(STATUS "Test executables enabled")
endif()

# ============================================================================
# Custom Targets (Desktop only)
# ============================================================================

if(NOT BUILD_PICO AND NOT BUILD_SAGE)
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

if(NOT BUILD_PICO AND NOT BUILD_SAGE)
    # Install sage executable
    install(TARGETS sage
        RUNTIME DESTINATION bin
    )

    # Install LSP server
    if(TARGET sage-lsp)
        install(TARGETS sage-lsp RUNTIME DESTINATION bin)
    endif()

    # Install standard library modules
    install(DIRECTORY lib/
        DESTINATION share/sage/lib
        FILES_MATCHING PATTERN "*.sage"
    )

    # Install self-hosted sources
    install(DIRECTORY src/sage/
        DESTINATION share/sage/src/sage
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
message(STATUS "Build in Sage:   ${BUILD_SAGE}")
message(STATUS "Debug mode:      ${ENABLE_DEBUG}")
message(STATUS "Tests enabled:   ${ENABLE_TESTS}")
message(STATUS "Source dir:      ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "Binary dir:      ${CMAKE_BINARY_DIR}")

if(BUILD_PICO)
    message(STATUS "")
    message(STATUS "Pico SDK Configuration:")
    message(STATUS "  - Pico SDK path: ${PICO_SDK_PATH}")
    message(STATUS "  - Platform: ${PICO_PLATFORM}")
    message(STATUS "  - Board: ${PICO_BOARD}")
    message(STATUS "  - C Compiler: ${CMAKE_C_COMPILER}")
    message(STATUS "  - ASM Compiler: ${CMAKE_ASM_COMPILER}")
    message(STATUS "  - Output: sage_pico.uf2")
endif()

if(BUILD_SAGE)
    message(STATUS "")
    message(STATUS "Self-Hosted Build:")
    message(STATUS "  - Host binary:  sage (C)")
    message(STATUS "  - Bootstrap:    src/sage/sage.sage")
    message(STATUS "  - Run files:    make sage_boot SAGE_FILE=<file>")
    message(STATUS "  - Run tests:    make test_selfhost")
endif()

message(STATUS "=================================================")
message(STATUS "")
