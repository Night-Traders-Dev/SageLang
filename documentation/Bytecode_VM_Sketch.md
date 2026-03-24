# SageLang Bytecode VM Sketch

This document sketches a bytecode execution backend for SageLang that can live beside the current AST tree-walk interpreter.

> **Implementation status (March 24, 2026):** The VM is functional with hybrid AST fallback. Milestones 1-5 are implemented, Milestone 6 (advanced control flow) uses AST fallback in hybrid mode. Milestone 7 (GPU opcodes) is complete. Break/continue now compile natively. 10 new opcodes added for future native class/import/exception support.

## Goals

- Keep the current front-end: lexer -> parser -> AST.
- Add a second execution backend: AST interpreter or bytecode VM.
- Share the same runtime objects where possible: `Value`, `Env`, GC, modules, native functions.
- Make runtime selection explicit from the CLI so engine integrations can choose the backend at startup.
- Roll out incrementally without breaking the existing AST path.

## Why A Stack VM Fits SageLang

SageLang already has:

- a tree-walk interpreter centered on `interpret(Stmt*, Env*)`
- a dynamic `Value` representation
- lots of expression evaluation that maps naturally to push/pop semantics
- control flow and exceptions that are easier to stage in a stack machine than a register VM

For SageLang, a **stack bytecode VM** is the right first VM:

- simpler to implement than a register VM
- easier to debug and disassemble
- faster than AST walking without requiring a JIT
- a good stepping stone to later native/JIT work

## Runtime Selection

Add a runtime selector in `src/c/main.c`:

```text
sage --runtime ast file.sage
sage --runtime bytecode file.sage
sage --runtime auto file.sage
```

Suggested behavior:

- `ast`: force the current tree-walk interpreter
- `bytecode`: compile AST to bytecode and run the VM
- `auto`: default for the future; initially aliases to `ast` until feature parity is good

Suggested default rollout:

1. land the switch and plumb a runtime enum
2. keep default as `ast`
3. enable `bytecode` behind the flag
4. switch default to `auto` later

Suggested enum:

```c
typedef enum {
    SAGE_RUNTIME_AST,
    SAGE_RUNTIME_BYTECODE,
    SAGE_RUNTIME_AUTO
} SageRuntimeMode;
```

## Proposed Execution Pipeline

Current path:

```text
source -> lexer -> parser -> AST -> interpret(AST, env)
```

Proposed dual path:

```text
source -> lexer -> parser -> AST -> runtime dispatcher
                                      |- AST interpreter
                                      |- bytecode compiler -> VM execute
```

That means the parser stays shared. We do not need a second front-end.

## Proposed Files

Suggested new C files:

- `include/runtime.h`
  Shared runtime mode enum and execution entrypoint.
- `include/bytecode.h`
  Chunk, opcode, constant pool, labels, debug metadata.
- `include/vm.h`
  VM state, frames, stack limits, result type.
- `src/c/runtime.c`
  Dispatch layer that chooses AST or bytecode backend.
- `src/c/bytecode.c`
  AST -> bytecode lowering.
- `src/c/bytecode_debug.c`
  Optional disassembler and instruction dump helpers.
- `src/c/vm.c`
  Bytecode execution loop.

Possible later files:

- `src/c/bytecode_opt.c`
  Peephole or constant-pool cleanup.
- `src/c/vm_builtins.c`
  If builtin dispatch needs separation.

## Shared Runtime Surface

The bytecode VM should reuse:

- `Value`
- `Env`
- GC
- native functions
- module loading
- class and instance objects

That keeps AST mode and bytecode mode behavior close and avoids building a second object model.

## Core VM Structures

### Chunk

One chunk is a linear stream of bytecode plus metadata:

```c
typedef struct {
    uint8_t* code;
    int code_count;
    int code_capacity;

    int* lines;
    int* columns;

    Value* constants;
    int constant_count;
    int constant_capacity;
} Chunk;
```

### Function Bytecode

User procs should lower to bytecode functions:

```c
typedef struct {
    char* name;
    Chunk chunk;
    int arity;
    int local_count;
    int upvalue_count;
} BytecodeFunction;
```

### Call Frame

```c
typedef struct {
    BytecodeFunction* function;
    uint8_t* ip;
    Value* slots;
    Env* env;
} VmFrame;
```

### VM State

```c
typedef struct {
    Value stack[STACK_MAX];
    Value* stack_top;

    VmFrame frames[FRAME_MAX];
    int frame_count;

    Env* globals;
    Value exception;
    int has_exception;
} Vm;
```

Notes:

- `slots` points into the value stack for locals.
- `env` stays available for closures, modules, and compatibility during early rollout.
- later we can reduce `Env` traffic for fast locals and reserve it mostly for closures/modules.

## Initial Opcode Families

Start small and cover the features that already dominate normal scripts.

### Constants and literals

- `OP_NIL`
- `OP_TRUE`
- `OP_FALSE`
- `OP_CONST`
- `OP_CONST_LONG`

### Stack movement

- `OP_POP`
- `OP_DUP`

### Locals and globals

- `OP_GET_LOCAL`
- `OP_SET_LOCAL`
- `OP_GET_GLOBAL`
- `OP_DEFINE_GLOBAL`
- `OP_SET_GLOBAL`

### Arithmetic and comparisons

- `OP_ADD`
- `OP_SUB`
- `OP_MUL`
- `OP_DIV`
- `OP_MOD`
- `OP_NEG`
- `OP_EQ`
- `OP_NEQ`
- `OP_LT`
- `OP_LTE`
- `OP_GT`
- `OP_GTE`

### Bitwise ops

- `OP_BIT_AND`
- `OP_BIT_OR`
- `OP_BIT_XOR`
- `OP_BIT_NOT`
- `OP_SHL`
- `OP_SHR`

### Control flow

- `OP_JUMP`
- `OP_JUMP_IF_FALSE`
- `OP_LOOP`

### Calls and returns

- `OP_CALL`
- `OP_RETURN`

### Aggregates

- `OP_ARRAY`
- `OP_TUPLE`
- `OP_DICT`
- `OP_GET_INDEX`
- `OP_SET_INDEX`

### Objects

- `OP_GET_PROPERTY`
- `OP_SET_PROPERTY`
- `OP_CLASS`
- `OP_METHOD`
- `OP_INHERIT`

### Exceptions and generators

These can come after the base VM works:

- `OP_SETUP_TRY`
- `OP_END_TRY`
- `OP_THROW`
- `OP_YIELD`
- `OP_AWAIT`

## Lowering Model

The bytecode compiler should walk the AST once and emit instructions.

Example:

```sage
let x = (2 + 3) * 4
print x
```

Could lower roughly to:

```text
CONST 2
CONST 3
ADD
CONST 4
MUL
DEFINE_GLOBAL "x"
GET_GLOBAL "x"
PRINT
```

For an `if`:

```sage
if cond:
    print 1
else:
    print 2
```

Lowering sketch:

```text
... emit cond ...
JUMP_IF_FALSE else_label
... then branch ...
JUMP end_label
else_label:
... else branch ...
end_label:
```

## Local Variable Strategy

For the first VM version:

- globals stay in `Env`
- locals live in frame slots on the VM stack
- closures can still consult `Env` until we add true upvalue capture

That gives immediate speedups because:

- local loads/stores avoid hash lookups
- the VM avoids recursive AST dispatch

## Functions and Closures

Recommended rollout:

### Stage 1

- compile top-level code and simple procs
- locals are stack slots
- globals and module names remain `Env` backed

### Stage 2

- add closures with explicit upvalue descriptors
- support captured locals with heap-lifted closed-over slots

Suggested closure objects:

```c
typedef struct {
    BytecodeFunction* function;
    Upvalue** upvalues;
    int upvalue_count;
} BytecodeClosure;
```

## Modules

Keep module loading logic shared.

Suggested model:

- parser builds module AST as today
- runtime mode decides whether that module executes via AST or bytecode
- imported module exports still land in module envs exactly as they do now

This keeps module semantics stable across backends.

## Exceptions

Do not start with full exception bytecode on day one if it slows the project down.

A practical path:

1. base VM without `try/catch/finally`
2. add a handler stack to the VM
3. lower `try` blocks to handler setup/teardown instructions
4. reuse the current `Value` exception object model

Suggested VM handler record:

```c
typedef struct {
    int frame_index;
    uint8_t* catch_ip;
    uint8_t* finally_ip;
    Value* stack_base;
} VmHandler;
```

## Generators and Async

These are advanced enough that they should be a later milestone.

Generators likely need:

- resumable bytecode frames
- saved instruction pointer
- saved stack window

Async likely stays built on the existing thread/future runtime first, with VM frames wrapped the same way AST execution is wrapped now.

## GC Integration

The VM must participate in root marking.

Additional roots beyond the AST interpreter:

- VM value stack
- active call frames
- closures and upvalues
- exception handler stack
- current exception value

Add a `gc_mark_vm_roots(Vm* vm)` hook and call it from the GC root walk when bytecode mode is active.

## Debuggability

The VM should be easy to inspect from the start.

Recommended tools:

- `sage --disassemble file.sage`
- `sage --runtime bytecode --trace-vm file.sage`
- bytecode instructions carrying source line and column info

These features will make parity debugging much easier than comparing behavior blindly.

## Runtime Dispatcher Sketch

Suggested public entrypoint:

```c
typedef struct {
    Value value;
    int ok;
} RuntimeResult;

RuntimeResult sage_execute(Stmt* program, Env* env, SageRuntimeMode mode);
```

Dispatch idea:

- if mode is `AST`, call the current `interpret()`
- if mode is `BYTECODE`, call `compile_to_bytecode()` then `vm_execute()`
- if mode is `AUTO`, initially route to AST until bytecode coverage is ready

## Recommended Milestones

### Milestone 1: Scaffolding

- add `--runtime ast|bytecode|auto`
- add runtime dispatcher
- keep `bytecode` mode returning a friendly "not implemented yet" error initially

### Milestone 2: Expression VM

- literals
- arithmetic
- variables
- print
- `if`
- `while`
- `for` over simple `range`

This is enough to benchmark against the tree-walk interpreter quickly.

### Milestone 3: Functions

- proc declarations
- calls
- returns
- locals
- globals

### Milestone 4: Aggregates

- arrays
- dicts
- tuples
- indexing and assignment

### Milestone 5: Objects

- classes
- instances
- property access
- methods
- inheritance

### Milestone 6: Advanced Control Flow (Partial)

- [x] break/continue — compile natively with loop context stack and break patch lists
- [ ] exceptions — `BC_OP_SETUP_TRY`, `BC_OP_END_TRY`, `BC_OP_RAISE` opcodes defined, handler stack needed in VM
- [ ] generators — resumable bytecode frames needed
- [ ] async/await — thread integration needed
- [ ] modules — `BC_OP_IMPORT` opcode defined, module loader integration needed
- [ ] classes — `BC_OP_CLASS`, `BC_OP_METHOD`, `BC_OP_INHERIT` opcodes defined, VM dispatch needed

Note: all unimplemented features work via AST fallback in hybrid mode (`--runtime bytecode` or `--runtime auto`). Only strict compiled VM artifacts (`.sagebc` files) require native opcode support.

### Milestone 7: GPU Hot-Path Opcodes (Implemented)

30 dedicated GPU opcodes have been added to `src/vm/bytecode.h` and handled in `src/vm/vm.c`. These bypass the interpreter's native function dispatch for frame-loop performance:

- **Window/Input**: `BC_OP_GPU_POLL_EVENTS`, `BC_OP_GPU_WINDOW_SHOULD_CLOSE`, `BC_OP_GPU_GET_TIME`, `BC_OP_GPU_KEY_PRESSED`, `BC_OP_GPU_KEY_DOWN`, `BC_OP_GPU_MOUSE_POS`, `BC_OP_GPU_MOUSE_DELTA`, `BC_OP_GPU_UPDATE_INPUT`
- **Commands**: `BC_OP_GPU_BEGIN_COMMANDS`, `BC_OP_GPU_END_COMMANDS`, `BC_OP_GPU_CMD_BEGIN_RP`, `BC_OP_GPU_CMD_END_RP`, `BC_OP_GPU_CMD_DRAW`, `BC_OP_GPU_CMD_DRAW_IDX`, `BC_OP_GPU_CMD_BIND_GP`, `BC_OP_GPU_CMD_BIND_DS`, `BC_OP_GPU_CMD_SET_VP`, `BC_OP_GPU_CMD_SET_SC`, `BC_OP_GPU_CMD_BIND_VB`, `BC_OP_GPU_CMD_BIND_IB`, `BC_OP_GPU_CMD_DISPATCH`, `BC_OP_GPU_CMD_PUSH_CONST`
- **Sync/Present**: `BC_OP_GPU_SUBMIT_SYNC`, `BC_OP_GPU_ACQUIRE_IMG`, `BC_OP_GPU_PRESENT`, `BC_OP_GPU_WAIT_FENCE`, `BC_OP_GPU_RESET_FENCE`, `BC_OP_GPU_UPDATE_UNIFORM`

All opcodes call the `sgpu_*` functions from `gpu_api.h` directly, avoiding `Value` marshaling overhead. Stack operands are popped, converted to C types inline, and results pushed back as `Value`.

## Compatibility Strategy

Do not force full parity on the first bytecode commit.

Instead:

- keep AST mode as the trusted backend
- add feature guards in bytecode mode
- if the bytecode compiler sees an unsupported AST node, produce a clear error naming the feature

Example:

```text
bytecode runtime does not yet support 'yield' statements; rerun with --runtime ast
```

That gives us a usable staged rollout.

## Recommended First Implementation Slice

The first working bytecode slice should support:

- numbers, strings, bools, nil
- local/global variables
- arithmetic and comparison
- bitwise ops
- `print`
- `if` / `while`
- simple procs without closures

That slice is small enough to land and already useful for game-engine scripting benchmarks.

## What This Buys SageLang

Compared to the current AST tree walk, a bytecode VM should give SageLang:

- lower per-node dispatch cost
- faster locals and control flow
- a more stable engine embedding story for interpreted mode
- a clean platform for later JIT/native experiments

The current AST interpreter stays valuable for:

- reference behavior
- debugging
- feature bring-up
- fallback while bytecode reaches parity
