# CLI Reference

Complete reference for the `sage` command-line interface.

## Top-Level Invocations

| Command | Meaning | Notes |
| ------- | ------- | ----- |
| `sage` | Start the interactive REPL | Same as `sage --repl` |
| `sage --repl` | Start the interactive REPL | Multi-line blocks are supported |
| `sage --help` | Print CLI usage | Shows compiler, tooling, and REPL entry points |
| `sage -c "source"` | Execute a source string | Runs without loading a file |
| `sage <file.sage> [arg ...]` | Run a Sage source file | Extra arguments are available through `sys.args()` |
| `sage <file.sgvm>` | Run a compiled SGVM binary | Runs via integrated MetalVM engine |
| `sage --lsp` | Start the LSP server on stdin/stdout | `sage-lsp` is the standalone companion binary |
| `sage fmt <file>` | Format a file in place | Prints `Formatted: <file>` on success |
| `sage fmt --check <file>` | Check formatting without rewriting | Exit code `1` when formatting is needed |
| `sage lint <file>` | Run the static linter | Exit code `1` when issues are found |
| `sage check <file>` | Type-check annotations | Validates annotations against inferred types |

## Compiler And Codegen Commands

| Command | Output Default | Supported Options |
| ------- | -------------- | ----------------- |
| `sage --compile-to-lily <input.sage>` | `<input>.lily` | `-o <path>` |
| `sage --compile-from-lily <input.lily>` | `<input>.sage` | `-o <path>` |
| `sage --emit-c <input.sage>` | `<input>.c` | `-o <path>`, `-O0`–`-O3`, `-g` |
| `sage --compile <input.sage>` | `<input-without-.sage>` | `-o <path>`, `--cc <compiler>`, `-O0`–`-O3`, `-g` |
| `sage --emit-vm <input.sage>` | `<input>.svm` | `-o <path>`, `-O0`–`-O3`, `-g` |
| `sage --sgvm <input.sage>` | `<input>.sgvm` | `-o <path>`, `-O0`–`-O3`, `-g` |
| `sage --emit-llvm <input.sage>` | `<input>.ll` | `-o <path>`, `-O0`–`-O3`, `-g` |
| `sage --compile-llvm <input.sage>` | `<input-without-.sage>` | `-o <path>`, `-O0`–`-O3`, `-g` |
| `sage --emit-asm <input.sage>` | `<input>.s` | `-o <path>`, `--target <arch[-profile]>`, `-O0`–`-O3`, `-g` |
| `sage --compile-native <input.sage>` | hosted: executable; non-hosted: `.o` | `-o <path>`, `--target <arch[-profile]>`, `-O0`–`-O3`, `-g` |
| `sage --emit-pico-c <input.sage>` | `<input>.pico.c` | `-o <path>` |
| `sage --compile-pico <input.sage>` | `.tmp/<name>` build dir + `<name>.uf2` | `-o <dir>`, `--board <name>`, `--name <program>`, `--sdk <path>`, `--chip <type>` |
| `sage --compile-bare <input.sage>` | `<input-without-.sage>.elf` | `-o <path>`, `--target <arch>`, `-O0`–`-O3`, `-g` |
| `sage --compile-uefi <input.sage>` | `<input-without-.sage>.efi` | `-o <path>`, `--target x86_64\|aarch64`, `-O0`–`-O3`, `-g` |
| `sage --emit-kotlin <input.sage>` | `<input>.kt` | `-o <path>` |
| `sage --compile-android <input.sage>` | Gradle project dir | `--package`, `--app-name`, `--min-sdk` |
| `sage --jit <input.sage> -o <bin>` | `<bin>` executable | JIT self-extracting executable with module bundling |

## Option Semantics

| Option | Applies To | Meaning |
| ------ | ---------- | ------- |
| `-o <path>` | All emit/compile commands | Output file or output directory depending on command |
| `--cc <compiler>` | `--compile` | Overrides the host C compiler; defaults to `cc` |
| `--target <arch[-profile]>` | `--emit-asm`, `--compile-native` | Target architecture/profile. Base arch: `x86-64`, `x86_64`, `aarch64`, `arm64`, `rv64`, `riscv64`, `mips`, `mips32`, `mips74k`. Profile suffixes: `-baremetal`, `-osdev`, `-uefi` |
| `-O0` / `-O1` / `-O2` / `-O3` | C, LLVM, and native codegen | Optimization pass level |
| `-g` | C, LLVM, asm, and native compile/emit | Enables debug information in the generated output |
| `--runtime ast\|bytecode\|jit\|aot` | Run commands | Runtime mode selection |
| `--jit` | Run commands | Enable JIT profiling; if used with `-o`, compiles to a self-extracting executable with bundled module dependencies |
| `--aot` | Run commands | Enable AOT compilation |
| `--verbose` / `-v` | All | Gate internal compiler diagnostic messages |
| `--math-work` | Run commands | Configure math execution modes |
| `--gc:tracing\|arc\|orc` | Run/compile | Garbage collector mode |
| `--board <name>` | `--compile-pico` | Pico board name; defaults to `pico` |
| `--name <program>` | `--compile-pico` | Program name for generated files; defaults to input basename |
| `--sdk <path>` | `--compile-pico` | Pico SDK path; falls back to `PICO_SDK_PATH` |
| `--chip <type>` | `--compile-pico` | Chip type: `rp2040`, `rp2350-arm`, `rp2350-riscv`; defaults to `rp2040` |
| `--package` | `--compile-android` | Application package name |
| `--app-name` | `--compile-android` | Application display name |
| `--min-sdk` | `--compile-android` | Minimum Android SDK level |

### Target profiles

- `hosted` (default, no suffix) — current behavior, executable-oriented flow.
- `-baremetal` / `-osdev` — emits freestanding entry symbol (`sage_entry`) and object-oriented native output.
- `-uefi` — emits `efi_main` entry symbol (freestanding object; full PE/COFF image linking is planned).

## REPL Commands

See [Tooling_Guide.md](Tooling_Guide.md) for the full REPL command table.
