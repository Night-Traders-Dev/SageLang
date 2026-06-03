# Sage Virtual Machine (SGVM) Documentation

## 1. Overview
The Sage Virtual Machine (SGVM) is the portable execution substrate for SageLang, specifically designed for high-performance execution in constrained environments such as SageOS kernels, bootloaders, and embedded systems. It is based on the `MetalVM` engine, a freestanding, minimal bytecode interpreter that requires no OS services, no `libc`, and no dynamic memory allocation.

## 2. Compilation & Execution Pipeline
SageLang source code follows this path to become a portable SGVM artifact:
1. **Source**: Human-readable `.sage` files.
2. **Compiler Frontend**: `sage --emit-vm` parses source into a text-based bytecode format (`.svm`).
3. **Artifact Compilation**: `sgvmc` converts `.svm` into a compact, binary `.sgvm` file.
4. **Verification**: `sgvm` performs mandatory security and safety checks on the binary before execution.
5. **Runtime Execution**: Execution by the `MetalVM` engine.

## 3. Binary Format Specification (.sgvm)
The `.sgvm` format is a compact, big-endian binary representation optimized for fast loading and low memory footprint.

| Section | Size | Description |
| :--- | :--- | :--- |
| **Magic** | 4 bytes | Literal string `SGVM` |
| **Version** | 1 byte | Currently `0x01` |
| **Flags** | 1 byte | Bitmask for features (e.g., debug info, optimization) |
| **Constant Count** | 2 bytes | Number of global constants (big-endian) |
| **Constants** | Variable | Typed global constant pool (see below) |
| **Chunk Count** | 4 bytes | Number of bytecode chunks (big-endian) |
| **Chunks** | Variable | Sequential bytecode segments |

### 3.1 Constants
Each constant in the pool starts with a type byte:
- `0x01` (**MV_NUM**): 8 bytes (IEEE 754 double).
- `0x03` (**MV_STR**): 2 bytes length (big-endian) + UTF-8 bytes.

### 3.2 Chunks
Each chunk consists of:
- **Length**: 4 bytes (big-endian).
- **Bytecode**: Sequential 1-byte opcodes and operands.

## 4. Bytecode Verification
Before execution, SGVM artifacts MUST pass a verification pass that ensures:
- **Opcode Validity**: No unknown or restricted opcodes are present.
- **Control Flow Integrity**: All `OP_JUMP`, `OP_JUMP_IF_FALSE`, and `OP_CALL` targets must point to valid offsets within the bytecode chunk.
- **Constant Safety**: All `OP_CONSTANT` and global variable opcodes must use indices that exist within the global constant pool.
- **Stack Safety**: (Optional/Planned) Static analysis to ensure stack depth does not exceed configured limits.

## 5. Execution Modes
SGVM supports multiple execution strategies within `MetalVM`:
- **Interpreted**: The default mode, executing bytecode instructions directly from memory.
- **Threaded Interpreter (New)**: High-performance dispatching using computed gotos (`&&label` syntax) for desktop and hosted targets. This reduces instruction dispatch overhead by up to 30%.
- **Freestanding**: Compiled with `-ffreestanding -nostdlib`, suitable for bare-metal deployment.

## 6. Toolchain Usage

### 6.1 Compiling to SGVM
Use `sgvmc` to compile Sage source into a binary SGVM artifact. This tool is available both as a C binary and a pure Sage tool.
```bash
./core/sgvmc script.sage artifact.sgvm
# OR via self-hosted Sage
./sage core/src/sage/sgvmc.sage script.sage artifact.sgvm
```

### 6.2 Running SGVM
Use `sgvm` to execute a compiled artifact. It will verify the file before starting execution.
```bash
./core/sgvm artifact.sgvm
# OR via self-hosted Sage
./sage core/src/sage/sgvm.sage artifact.sgvm
```

## 7. MetalVM C API (`metal_vm.h`)
The kernel or host application interacts with SGVM via these primary interfaces:
- `metal_vm_load_binary()`: Parses a `.sgvm` buffer into the VM state.
- `metal_vm_verify()`: Executes the security and integrity check.
- `metal_vm_run()`: Executes all loaded chunks until completion or error.
- `metal_vm_step()`: Executes a single instruction for cooperative multitasking.

## 8. Memory Management
`MetalVM` uses fixed-size static pools for all resources (stack, constants, strings, objects). These limits are configurable at compile-time in `metal_vm.h` to adapt to different hardware constraints. No `malloc` is used.
