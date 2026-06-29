# Build Guide

SageLang's desktop build links against `libm`, `pthread`, `dl`, `libcurl`, and
OpenSSL. Four build paths are supported: desktop C build, self-hosted bootstrap
flow, Pico/RP2040 build, and the SageMake unified build system.

## Prerequisites

- A C compiler such as `gcc`, `clang`, or `cc`
- `make` and/or `cmake`
- Desktop libraries and headers for `libcurl` and OpenSSL
- For Pico builds: a valid `PICO_SDK_PATH`

## Build from C (Default)

```bash
git clone https://github.com/Night-Traders-Dev/SageLang.git
cd SageLang
make clean && make -j$(nproc)
```

This produces `./sage` and `./sage-lsp`.

```bash
./sage examples/exceptions.sage
./sage examples/generators.sage
./sage examples/phase6_classes.sage
```

## Self-Hosted Build (Sage-on-Sage)

The self-hosted flow builds the C `sage` executable first, then uses it to
execute the Sage bootstrap sources under `src/sage/`:

```bash
make sage-boot FILE=examples/hello.sage
make test-selfhost
make test-all
```

See [Self_Hosting_Guide.md](Self_Hosting_Guide.md) for the full list of
self-hosted test targets.

## CMake Build

```bash
# Default: build sage and sage-lsp from C
cmake -B build && cmake --build build

# Self-hosted mode: build sage, then run self-hosted targets
cmake -B build -DBUILD_SAGE=ON && cmake --build build
cmake --build build --target test_selfhost

# Pico/RP2040 build
cmake -B build_pico -DBUILD_PICO=ON -DPICO_BOARD=pico
cmake --build build_pico
```

When `BUILD_SAGE=ON`, the executable target is still `sage`; the build adds
custom bootstrap targets such as `sage_boot` and `test_selfhost`.

Convenience Make targets for CMake:

```bash
make cmake                 # Configure a desktop CMake build
make cmake-build           # Build the desktop CMake tree
make cmake-sage            # Setup CMake self-hosted build
make cmake-sage-build      # Build and run self-hosted tests via CMake
make cmake-pico            # Setup a Pico CMake build
```

## SageMake Build

SageMake is the unified build system that auto-detects your platform, GPU, NPU,
and compiler backends.

```bash
./sagemake info              # Show detected environment (GPU, NPU, SIMD, compiler)
./sagemake build             # Build sage interpreter
./sagemake chatbot --llvm    # Compile chatbot via LLVM
./sagemake chatbot --c       # Compile via C backend
./sagemake chatbot --native  # Compile via native asm
./sagemake train 200000 0.001  # Build trainer + train
./sagemake all               # Build everything
./sagemake --minimal build   # Core only (no optional deps)
```

## LLM / Training Targets

```bash
make train-c                  # Build C trainer (auto-detects cuBLAS GPU + ARM NEON)
make train-sage               # Train via Sage interpreter
make chatbot-c                # Compile chatbot via C backend
make chatbot-llvm             # Compile chatbot via LLVM backend
make chatbot-native           # Compile chatbot via native asm backend
make sl-tq-chat               # Compile SL-TQ-LLM generative chatbot
make all-models               # Build all model variants
make benchmark-python         # Sage vs Python 3 benchmarks (10 workloads, 5 recipes)
make benchmark-python-md      # Same, markdown table output
```

See [LLM_Guide.md](LLM_Guide.md) and [ML_CUDA_Guide.md](ML_CUDA_Guide.md) for
model and training details.

## Build Parameters

### Make Variables

| Variable | Default | Effect |
| -------- | ------- | ------ |
| `CC` | `gcc` | C compiler used for `make` builds |
| `CFLAGS` | `-std=c11 -Wall -Wextra -Wpedantic -O2 -D_POSIX_C_SOURCE=200809L` | Base compile flags for the desktop build |
| `LDFLAGS` | `-lm -lpthread -ldl -lcurl -lssl -lcrypto` | Desktop link flags; `-lvulkan` added when Vulkan SDK detected; `-lGL` added when OpenGL detected; switches to `-lm` when `PICO_BUILD` is set |
| `VULKAN` | `auto` | `auto` detects via pkg-config, `1` forces Vulkan, `0` disables |
| `OPENGL` | `auto` | `auto` detects via pkg-config, `1` forces OpenGL, `0` disables |
| `DEBUG` | `0` | `DEBUG=1` adds `-g -O0 -DDEBUG` |
| `PREFIX` | `/usr/local` | Install prefix for `make install` |
| `FILE` | unset | Required by `make sage-boot FILE=<path>` |
| `PICO_BUILD` | unset | Internal Make switch that changes link flags for non-desktop builds |

### CMake Cache Variables And Environment Inputs

| Parameter | Default | Effect |
| --------- | ------- | ------ |
| `BUILD_PICO` | `OFF` | Enables the Pico/RP2040 build and imports `pico_sdk_import.cmake` before `project()` |
| `BUILD_SAGE` | `OFF` | Enables bootstrap/self-hosted build targets such as `sage_boot` and `test_selfhost` |
| `ENABLE_DEBUG` | `OFF` | Adds `-g -O0 -DDEBUG` |
| `ENABLE_TESTS` | `OFF` | Builds optional C test executables and enables `ctest` targets |
| `CMAKE_BUILD_TYPE` | generator default | Standard CMake build type summary field |
| `CMAKE_C_COMPILER` | toolchain default | Chooses the C compiler shown in the config summary |
| `CMAKE_INSTALL_PREFIX` | CMake default | Install destination for `cmake --install` |
| `PICO_SDK_PATH` | unset | Required for Pico builds unless your environment already exports it |
| `PICO_BOARD` | `pico` | Pico board name used by Pico SDK builds |
| `SAGE_FILE` | unset | Input file consumed by the `sage_boot` custom target in self-hosted builds |

## Compiling the SageGPT Chatbot to a Native Binary

```bash
# LLVM backend (recommended — links GPU/runtime support)
sage --compile-llvm models/chatbots/sagellm_chatbot.sage -o sagellm_chat
./sagellm_chat

# C backend (also works)
sage --compile models/chatbots/sagellm_chatbot.sage -o sagellm_chat
./sagellm_chat
```
