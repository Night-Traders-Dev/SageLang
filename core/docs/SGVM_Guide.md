# Sage Virtual Machine (SGVM) Documentation

## 1. Overview
The Sage Virtual Machine (SGVM) is the portable execution substrate for SageLang, specifically designed for high-performance execution in constrained environments such as SageOS kernels, bootloaders, and embedded systems. It is based on the `MetalVM` engine, a freestanding, minimal bytecode interpreter that requires no OS services, no `libc`, and no dynamic memory allocation.

## 2. Compilation & Execution Pipeline
SageLang source code follows this path to become a portable SGVM artifact:
1. **Source**: Human-readable `.sage` files.
2. **Compiler Frontend**: `sage --sgvm` parses source directly into a binary `.sgvm` artifact. (Alternatively, `sage --emit-vm` emits text-based `.svm`).
3. **Verification**: `sage` (or `sgvm`) performs mandatory security and safety checks on the binary before execution.
4. **Runtime Execution**: Execution by the `MetalVM` engine integrated into `sage`.

## 3. Binary Format Specification (.sgvm 2.0)
The `.sgvm` 2.0 format is a compact representation optimized for fast loading and low memory footprint. It uses little-endian for header fields and big-endian for bytecode operands.

| Section | Size | Description |
| :--- | :--- | :--- |
| **Magic** | 4 bytes | Literal string `SGVM` |
| **Version** | 1 byte | Currently `0x02` |
| **Constants** | Variable | Global constant pool (LE count + entries) |
| **Main Code** | Variable | System entry point (LE length + bytecode) |
| **Functions** | Variable | Function table (LE count + entries) |

### 3.1 Constants
The constant pool starts with a 2-byte count (LE). Each constant starts with a type byte:
- `0x01` (**MV_NUM**): 8 bytes (IEEE 754 double).
- `0x03` (**MV_STR**): 2 bytes length (LE) + UTF-8 bytes.

### 3.2 Functions
The function pool starts with a 2-byte count (LE). Each function consists of:
- **Param Count**: 2 bytes (LE).
- **Param Hashes**: 4 bytes (LE) per parameter (FNV-1a).
- **Constants**: Sub-pool for function-local constants.
- **Code**: 4-byte length (LE) + raw bytecode.

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
Use `sage --sgvm` to compile Sage source into a binary SGVM artifact.
```bash
./core/sage --sgvm script.sage -o artifact.sgvm
```
Alternatively, you can use the standalone `sgvmc` tool:
```bash
./core/sgvmc script.sage artifact.sgvm
```

### 6.2 Running SGVM
Use the `sage` command directly to execute a compiled artifact. It will verify the file before starting execution.
```bash
./core/sage artifact.sgvm
```
Or use the standalone `sgvm` engine:
```bash
./core/sgvm artifact.sgvm
```

## 7. MetalVM C API (`metal_vm.h`)
The kernel or host application interacts with SGVM via these primary interfaces:
- `metal_vm_load_binary()`: Parses a `.sgvm` buffer into the VM state.
- `metal_vm_verify()`: Executes the security and integrity check.
- `metal_vm_run()`: Executes all loaded chunks until completion or error.
- `metal_vm_step()`: Executes a single instruction for cooperative multitasking.

## 8. Memory Management
`MetalVM` uses fixed-size static pools for all resources (stack, constants, strings, objects). These limits are configurable at compile-time in `metal_vm.h` to adapt to different hardware constraints. No `malloc` is used.
