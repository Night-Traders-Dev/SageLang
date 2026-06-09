# SageLang — Core

Everything needed to build the language lives here.

## Build

```sh
# From core/
make              # build sage binary (output: ./sage)
make debug        # debug build
make clean        # clean build artifacts
make install      # install to /usr/local/bin (use sudo)
make uninstall    # remove install

# Preferred: from repo root (delegates here automatically)
make
sudo make install
```

## Key Make Targets

| Target                | Description                               |
|-----------------------|-------------------------------------------|
| `make`                | Build `./sage` from C                     |
| `make debug`          | Debug build (-g -O0)                      |
| `make test`           | Run compiler backend tests                |
| `make test-selfhost`  | Run self-hosted interpreter tests         |
| `make test-all`       | Both                                      |
| `make sage-boot FILE=x.sage` | Run via self-hosted interpreter   |
| `make install`        | Install to PREFIX (default /usr/local)    |
| `make cmake`          | Set up CMake build                        |
| `make menuconfig`     | Kernel-style feature config (kconfiglib)  |

## Structure

```
core/
├── src/
│   ├── c/          ← C implementation (lexer, parser, interpreter, JIT, LLVM backend…)
│   ├── sage/       ← self-hosted Sage implementation
│   ├── vm/         ← bytecode VM (C)
│   ├── user/       ← user-facing shell
│   └── docker/     ← Docker build helpers
├── include/        ← C headers
├── lib/            ← Sage standard library (.sage files)
├── examples/       ← example .sage programs
├── models/         ← ML models, training, chatbot
├── docs/           ← language book, API docs
├── documentation/  ← guides (Android, Baremetal, Blockchain…)
├── boards/         ← embedded board support (RP2040)
├── scripts/        ← build tooling, chart generators, benchmark runners
├── SageChain/      ← blockchain sub-project
├── SageFetch/      ← package fetch sub-project
├── sageos_build/   ← SageOS build artifacts
├── build_os/       ← OS build helpers
├── build_x86_64/   ← x86_64 bare metal
├── assets/         ← images, pipeline diagrams
├── editors/        ← editor integrations
├── data/           ← runtime data (wallets, chains)
└── output/         ← compiled output (aarch64, x86…)
```

## Backends

- **Interpreter** — default; runs .sage directly
- **Bytecode VM** — `--runtime bytecode`
- **C backend** — `--compile file.sage -o out` (via GCC)
- **LLVM backend** — `--compile-llvm file.sage -o out` (requires clang)
- **Native ASM** — `--emit-asm file.sage -o out.s`
- **Kotlin** — `--compile-kotlin`
- **Pico/RP2040** — `--emit-pico-c`
- **Bare metal** — `--compile-bare`
