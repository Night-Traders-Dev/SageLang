# Sage Language - Development Roadmap

> **Last Updated**: March 9, 2026
> **Current Phase**: Phase 13 Complete (Self-Hosting)

This roadmap outlines the development journey of Sage, from its initial bootstrapping phase to becoming a fully self-hosted systems programming language with low-level capabilities.

---

## ✅ Completed Phases

### Phase 1: Core Language Foundation
**Status**: ✅ Complete

#### Lexer & Tokenization
- [x] Indentation-aware lexer
- [x] Token stream generation
- [x] INDENT/DEDENT token emission
- [x] Comment handling
- [x] String literal parsing
- [x] Number literal parsing
- [x] Identifier recognition
- [x] Operator tokenization

#### Parser & AST Construction
- [x] Recursive descent parser
- [x] AST node definitions (expressions, statements)
- [x] Expression parsing (binary, unary, literals)
- [x] Statement parsing (assignments, control flow)
- [x] Indentation-based block parsing
- [x] Error reporting with line numbers
- [x] **Unary expressions** - Support for `-x` negative numbers

#### Basic Interpreter
- [x] Tree-walking interpreter
- [x] Expression evaluation
- [x] Statement execution
- [x] Basic arithmetic operations (+, -, *, /)
- [x] Comparison operators (==, !=, <, >, <=, >=)
- [x] Logical operators (and, or, not)
- [x] **Unary operators** - Negative numbers in expressions

#### Variables & Scoping
- [x] `let` keyword for variable declarations
- [x] Lexical scoping implementation
- [x] Environment management (scope chains)
- [x] Variable assignment and lookup

#### Control Flow
- [x] `if` / `else` conditionals
- [x] `while` loops
- [x] Block statement execution

---

### Phase 2: Functions & Procedures
**Status**: ✅ Complete

- [x] `proc` keyword for function definitions
- [x] Function parameters
- [x] Function calls
- [x] Return statements
- [x] Recursion support
- [x] Closure support (lexical scoping)
- [x] Function as first-class values

---

### Phase 3: Type System & Standard Library
**Status**: ✅ Complete

#### Type System
- [x] Integer type
- [x] String type
- [x] Boolean type (`true`, `false`)
- [x] Nil type
- [x] Type representation in Value structs
- [x] String concatenation
- [x] **Exception type** - VAL_EXCEPTION with message
- [x] **Generator type** - VAL_GENERATOR with state

#### Native Functions (Standard Library)
- [x] `print()` - Output to console
- [x] `input()` - Read from stdin
- [x] `clock()` - Get current time
- [x] `tonumber()` - String to number conversion
- [x] **`str()`** - Number/bool to string conversion
- [x] **`next()`** - Generator iteration

---

### Phase 4: Memory Management
**Status**: ✅ **COMPLETE** (November 27, 2025)

#### Garbage Collection ✅
- [x] **Mark-and-sweep algorithm** - Automatic memory reclamation
- [x] **Object tracking** - All heap-allocated objects tracked
- [x] **Automatic collection** - Triggers at memory threshold
- [x] **Manual collection** - `gc_collect()` function
- [x] **GC statistics** - `gc_stats()` provides metrics
- [x] **GC control** - `gc_enable()`, `gc_disable()`

#### Memory Safety ✅
- [x] Prevents use-after-free
- [x] Automatic cleanup of unreachable objects
- [x] Leak detection capabilities
- [x] Performance monitoring

#### GC Metrics ✅
- [x] Bytes allocated tracking
- [x] Object count tracking
- [x] Collection cycle counting
- [x] Objects freed tracking
- [x] Threshold management

---

### Phase 5: Advanced Data Structures  
**Status**: ✅ **COMPLETE** (November 27, 2025)

#### Collections ✅
- [x] Arrays/Lists with dynamic sizing
- [x] **Hash maps/Dictionaries** - `{"key": value}` syntax
- [x] **Tuples** - `(val1, val2, val3)` syntax  
- [x] **Array slicing** - `arr[start:end]` syntax
- [x] Dictionary indexing - `dict["key"]`
- [x] Tuple indexing - `tuple[0]`

#### String Enhancement ✅
- [x] **String methods** - `split()`, `join()`, `replace()`, `upper()`, `lower()`, `strip()`
- [x] String concatenation
- [x] String indexing and length

#### Native Functions Added ✅
- [x] `len()` - Get length of arrays, strings, tuples, dicts
- [x] `push()`, `pop()` - Array manipulation
- [x] `range()` - Generate number sequences
- [x] `slice()` - Array slicing
- [x] `split()`, `join()` - String splitting and joining
- [x] `replace()` - String replacement
- [x] `upper()`, `lower()` - Case conversion
- [x] `strip()` - Whitespace trimming
- [x] `dict_keys()`, `dict_values()` - Dictionary operations
- [x] `dict_has()`, `dict_delete()` - Dictionary manipulation

---

### Phase 6: Object-Oriented Programming
**Status**: ✅ **COMPLETE** (November 28, 2025, 9:00 AM EST)

#### Classes & Objects ✅
- [x] **Class definitions** - `class ClassName:` syntax
- [x] **Instance creation** - Constructor calls `ClassName(args)`
- [x] **Methods** - Functions with `self` parameter
- [x] **Constructor** - `init(self, ...)` method
- [x] **Property access** - `obj.property` syntax
- [x] **Property assignment** - `obj.property = value`
- [x] **Inheritance** - `class Child(Parent):` syntax
- [x] **Method overriding** - Override parent methods
- [x] **Self binding** - Automatic `self` in methods

#### Implementation ✅
- [x] ClassValue and InstanceValue types
- [x] Method storage and lookup
- [x] Inheritance chain traversal
- [x] Property dictionary per instance
- [x] `EXPR_GET` and `EXPR_SET` for properties
- [x] `STMT_CLASS` for class definitions
- [x] **Comparison operators** - Full support for `>=` and `<=`

---

### Phase 7: Advanced Control Flow
**Status**: ✅ **100% COMPLETE** (November 29, 2025)

#### Exception Handling ✅
- [x] **`try:` blocks** - Exception catching context
- [x] **`catch e:` clauses** - Exception binding to variable
- [x] **`finally:` blocks** - Always-execute cleanup code
- [x] **`raise "message"` statements** - Throw exceptions
- [x] **Exception propagation** - Through function call stack
- [x] **Nested try/catch** - Multiple levels of handling
- [x] **Exception re-raising** - Propagate after catching
- [x] **ExceptionValue type** - VAL_EXCEPTION with message
- [x] **ExecResult.is_throwing** - Exception flow flag
- [x] **Full test suite** - 7 comprehensive examples

#### Generators & Lazy Evaluation ✅
- [x] **`yield` keyword** - Suspend function execution
- [x] **Generator state management** - Preserve locals between yields
- [x] **Iterator protocol** - `next(generator)` function
- [x] **Automatic detection** - Functions with `yield` become generators
- [x] **Generator type** - VAL_GENERATOR with closure
- [x] **State preservation** - Resume from last yield point
- [x] **Infinite sequences** - Generators can run forever
- [x] **Memory efficiency** - Lazy evaluation on-demand

#### Loop Control ✅
- [x] **`for` loops** - Iterator-based loops (`for x in array:`)
- [x] **`break` statement** - Exit loops early
- [x] **`continue` statement** - Skip to next iteration

---

## ✅ Recently Completed

### Phase 8: Modules & Package System
**Status**: ✅ **COMPLETE** (March 2026)

#### Module System Implementation ✅

- [x] **`import` statement parsing** - Full syntax support
- [x] **`from X import Y` parsing** - Selective imports with aliases
- [x] **`import X as Y` parsing** - Module aliasing
- [x] **Module AST node** - STMT_IMPORT representation
- [x] **Module loader infrastructure** - File loading and caching
- [x] **Module caching** - Load modules once, reuse everywhere
- [x] **Search path system** - `./`, `./lib/`, `./modules/`
- [x] **Function closures** - FunctionValue stores Env* closure
- [x] **Closure capture** - Functions remember defining environment

#### Module Execution ✅

- [x] **Module parsing** - Lex and parse imported files
- [x] **Module environment creation** - Isolated namespace per module
- [x] **Import statement execution** - import/from/as handling
- [x] **Module execution pipeline** - Complete environment parent chain
- [x] **Symbol export** - Functions visible to importers
- [x] **Symbol resolution** - Correct closure lookup
- [x] **Circular dependency detection** - `is_loading` flag prevents infinite loops
- [x] **Error reporting** - Clear import failure messages
- [x] **VAL_MODULE type** - Module values with dot-access for attributes
- [x] **Path traversal prevention** - Module names validated, `realpath()` containment checks

#### Remaining Module Features (Future)

- [ ] **Relative imports** - `from .sibling import func`
- [ ] **Re-export support** - `from X import *`
- [ ] **Submodules** - Nested module packages

---

### Phase 8.5: Security & Performance Hardening
**Status**: ✅ **COMPLETE** (March 8, 2026)

A cross-cutting audit and hardening pass across the entire codebase.

#### Recursion Safety ✅

- [x] **Interpreter depth limit** - `MAX_RECURSION_DEPTH 1000` with graceful exception on overflow
- [x] **Parser depth limit** - `MAX_PARSER_DEPTH 500` prevents stack overflow from malicious input
- [x] **Iterative lexer** - `scan_token()` converted from recursive to iterative (`for(;;)` loop)

#### Memory Safety ✅

- [x] **Safe allocation wrappers** - `SAGE_ALLOC`/`SAGE_REALLOC`/`SAGE_STRDUP` macros abort on OOM (never return NULL)
- [x] **All malloc/realloc/strdup replaced** - Every call site across all source files uses safe wrappers
- [x] **GC allocation hardened** - `gc_alloc` aborts on failure instead of returning NULL
- [x] **GC pinning** - `gc_pin()`/`gc_unpin()` prevent collection during multi-step allocations
- [x] **ftell error checks** - File size reads check for -1 return

#### Module Security ✅

- [x] **Module name validation** - Rejects `/`, `\`, `..` in module names
- [x] **Path containment** - `realpath()` verifies resolved paths stay within search directories
- [x] **Symlink-safe** - Resolves real paths before containment checks

#### Dictionary Performance ✅

- [x] **Hash table replacement** - O(1) amortized lookups via open-addressing with FNV-1a hashing
- [x] **Linear probing** - Cache-friendly collision resolution
- [x] **Automatic growth** - Table doubles at 75% load factor
- [x] **Backward-shift deletion** - Maintains probe chain integrity without tombstones
- [x] **GC integration** - Mark and release iterate by capacity with NULL-key guards

#### Environment GC Integration ✅

- [x] **Env marked flag** - O(1) cycle detection replaces O(n^2) linked list tracking
- [x] **env_sweep_unmarked()** - Unreachable environments freed during GC sweep
- [x] **Marks cleared during sweep** - No separate clear pass needed

#### String Performance ✅

- [x] **`size_t` for lengths** - Prevents overflow on large strings
- [x] **O(n) string_join** - Write-pointer approach replaces O(n^2) repeated strcat
- [x] **O(n) string_replace** - Single-pass rewrite replaces O(n^2) memmove approach

#### Test Suite ✅

- [x] **100 automated interpreter tests** across 25 categories + **24 compiler tests**
- [x] **Bash test runner** with EXPECT/EXPECT_ERROR pattern matching
- [x] **Full coverage**: variables, arithmetic, comparison, logic, strings, control flow, loops, functions, arrays, dicts, tuples, classes, inheritance, exceptions, generators, modules, closures, builtins, edge cases, GC

---

### Phase 9: Low-Level Programming & System Features
**Status**: ✅ Complete

#### Bit Manipulation ✅
- [x] **Bitwise AND** (`&`) - Integer bitwise AND
- [x] **Bitwise OR** (`|`) - Integer bitwise OR
- [x] **Bitwise XOR** (`^`) - Integer bitwise XOR
- [x] **Bitwise NOT** (`~`) - Integer bitwise complement
- [x] **Left Shift** (`<<`) - Shift bits left
- [x] **Right Shift** (`>>`) - Shift bits right
- [x] **Operator precedence** - Correct C-style precedence (shift → comparison → & → ^ → | → logical)
- [x] **Test coverage** - 6 automated tests for bitwise operations

#### Inline Assembly ✅
- [x] **`asm_exec(code, ret_type, ...args)`** - Compile and execute assembly on host architecture
- [x] **`asm_compile(code, arch, output)`** - Cross-compile assembly to object file
- [x] **`asm_arch()`** - Detect host architecture
- [x] **x86-64 support** - Native execution with System V ABI calling convention
- [x] **aarch64 support** - Cross-compilation via `aarch64-linux-gnu-as`
- [x] **RISC-V 64 support** - Cross-compilation via `riscv64-linux-gnu-as`
- [x] **Return types** - `"int"`, `"double"`, `"void"` with up to 4 arguments
- [x] **Test coverage** - 5 automated tests for assembly operations

#### Pointer Arithmetic & Raw Memory ✅
- [x] **`mem_alloc(size)`** - Allocate raw memory (zero-initialized, capped at 64MB)
- [x] **`mem_free(ptr)`** - Free allocated memory
- [x] **`mem_read(ptr, offset, type)`** - Read value at ptr+offset (`"byte"`, `"int"`, `"double"`, `"string"`)
- [x] **`mem_write(ptr, offset, type, val)`** - Write value at ptr+offset
- [x] **`mem_size(ptr)`** - Get allocation size
- [x] **`addressof(val)`** - Get memory address of a value (as number)
- [x] **VAL_POINTER type** - New value type for raw memory handles with bounds checking
- [x] **Test coverage** - 5 automated tests for memory operations

#### Foreign Function Interface (FFI) ✅
- [x] **`ffi_open(path)`** - Load shared library via `dlopen()`
- [x] **`ffi_call(lib, name, ret_type, args)`** - Call C function via `dlsym()`
- [x] **`ffi_close(lib)`** - Unload shared library via `dlclose()`
- [x] **`ffi_sym(lib, name)`** - Check if symbol exists
- [x] **Return types**: `"double"`, `"int"`, `"long"`, `"string"`, `"void"`
- [x] **Argument types**: numbers (as double/int/long), strings (as const char*)
- [x] **VAL_CLIB type** - New value type for library handles
- [x] **Test coverage** - 3 automated tests for FFI operations
#### C Struct Interop ✅
- [x] **`struct_def(fields)`** - Define struct layout with C-compatible alignment
- [x] **`struct_new(def)`** - Allocate zeroed struct instance
- [x] **`struct_get(ptr, def, field)`** - Read field value from struct
- [x] **`struct_set(ptr, def, field, val)`** - Write field value to struct
- [x] **`struct_size(def)`** - Get total struct size (with padding)
- [x] **8 C types** - `char`, `byte`, `short`, `int`, `long`, `float`, `double`, `ptr`
- [x] **Proper alignment** - Natural alignment per field, tail padding to max alignment
- [x] **Test coverage** - 4 automated tests for struct operations

---

### Phase 10: Compiler Development
**Status**: ✅ **COMPLETE** (March 2026)

#### Code Generation ✅

- [x] Initial C code generation backend (`sage --emit-c`, `sage --compile`) for scalar control flow and array operations
- [x] For-in loops over arrays (`for x in arr:`)
- [x] Dictionary literals, indexing, `dict_keys`, `dict_values`, `dict_has`, `dict_delete`
- [x] Tuple literals and indexing
- [x] Exception handling (`try`/`catch`/`finally`/`raise`) via `setjmp`/`longjmp`
- [x] Property access (`obj.prop`) compiled as dict key lookup
- [x] String builtins: `split`, `join`, `replace`, `upper`, `lower`, `strip`
- [x] Memory builtins: `mem_alloc`, `mem_free`, `mem_read`, `mem_write`, `mem_size`
- [x] Struct builtins: `struct_def`, `struct_new`, `struct_get`, `struct_set`, `struct_size`
- [x] Additional builtins: `tonumber()`, `clock()`, `input()`, `asm_arch()`
- [x] Classes and objects: class definitions, inheritance, method dispatch, property get/set, constructors
- [x] Module imports: `import`/`from X import Y` with file resolution, inline compilation
- [x] Architecture detection: `asm_arch()` returns host arch at compile time (x86_64, aarch64, rv64)
- [x] LLVM IR generation backend (`sage --emit-llvm`, `sage --compile-llvm`)
- [x] Direct machine code generation (`sage --emit-asm`, `sage --compile-native`) for x86-64, aarch64, rv64
- [x] Optimization levels (`-O0` through `-O3`)
- [x] Debug information generation (`-g` flag)

#### Compilation Pipeline ✅

- [x] Multi-pass compilation (`run_passes()` infrastructure in `src/pass.c`)
- [x] Type checking pass (`src/typecheck.c`, best-effort type inference at `-O1+`)
- [x] Constant folding (`src/constfold.c`, numeric/string/boolean at `-O1+`)
- [x] Dead code elimination (`src/dce.c`, unused lets/procs, unreachable code at `-O2+`)
- [x] Inlining optimization (`src/inline.c`, single-return non-recursive procs at `-O3`)

---

### Phase 11: Concurrency & Parallelism
**Status**: ✅ **COMPLETE** (March 9, 2026)

#### Native Standard Library Modules ✅

- [x] **`math` module** - `sqrt`, `sin`, `cos`, `tan`, `floor`, `ceil`, `abs`, `pow`, `log`, `pi`, `e`
- [x] **`io` module** - `readfile`, `writefile`, `appendfile`, `exists`, `remove`, `rename`
- [x] **`string` module** - `char`, `ord`, `startswith`, `endswith`, `contains`, `repeat`, `reverse`
- [x] **`sys` module** - `args`, `exit`, `platform`, `version`, `env`, `setenv`
- [x] **Native module infrastructure** - `create_native_module()` pre-loads into module cache

#### Threading ✅

- [x] **Thread creation** - `thread.spawn(proc, args...)` via pthreads
- [x] **Thread joining** - `thread.join(t)` waits for completion and returns result
- [x] **Mutex support** - `thread.mutex()`, `thread.lock(m)`, `thread.unlock(m)`
- [x] **Thread sleep** - `thread.sleep(ms)` millisecond delay
- [x] **Thread ID** - `thread.id()` returns current thread identifier
- [x] **GC thread safety** - Mutex-protected garbage collection

#### Async/Await ✅

- [x] **`async proc` syntax** - Parsed as STMT_ASYNC_PROC, sets `is_async` flag
- [x] **`await` expressions** - EXPR_AWAIT joins async thread and returns result
- [x] **Automatic thread spawning** - Calling async proc spawns background thread
- [x] **Result retrieval** - `await` blocks until thread completes, returns value

#### Backend Support ✅

- [x] **LLVM backend** - Dict, tuple, slice, get/set, for-in loops, break/continue
- [x] **Native codegen** - For-in loops, break/continue with loop label stacks
- [x] **All passes updated** - EXPR_AWAIT and STMT_ASYNC_PROC in pass.c, constfold, dce, inline, typecheck

---

### Phase 12: Tooling Ecosystem
**Status**: ✅ **COMPLETE** (March 9, 2026)

#### REPL ✅
- [x] **Interactive REPL** - `sage` (no args) or `sage --repl` launches interactive mode
- [x] **Multi-line block support** - Automatic continuation for indented blocks
- [x] **Error recovery** - Errors displayed without exiting the session
- [x] **Built-in commands** - `:help`, `:quit` for REPL control

#### Code Formatter ✅
- [x] **`sage fmt <file>`** - Format Sage source files in place
- [x] **`sage fmt --check <file>`** - Check formatting without modifying files
- [x] **Consistent style** - Normalizes indentation, spacing, and blank lines

#### Linter ✅
- [x] **`sage lint <file>`** - Static analysis with 13 rules
- [x] **Error rules (E001-E003)** - Syntax and structural errors
- [x] **Warning rules (W001-W005)** - Potential bugs and bad practices
- [x] **Style rules (S001-S005)** - Code style and naming conventions

#### Syntax Highlighting ✅
- [x] **TextMate grammar** - `editors/sage.tmLanguage.json`
- [x] **VSCode extension** - `editors/vscode/` with full language support

#### Language Server Protocol (LSP) ✅
- [x] **`sage --lsp`** - LSP server mode integrated into main binary
- [x] **`sage-lsp` standalone binary** - Dedicated LSP server
- [x] **Diagnostics** - Real-time error reporting
- [x] **Completion** - Keyword and symbol completions
- [x] **Hover** - Type and documentation on hover
- [x] **Formatting** - Format-on-save via LSP

---

### Phase 13: Self-Hosting
**Status**: ✅ **COMPLETE** (March 9, 2026)

#### Self-Hosted Interpreter ✅

- [x] **Token definitions** - `src/sage/token.sage` with token type constants
- [x] **AST definitions** - `src/sage/ast.sage` with dict-based node constructors
- [x] **Lexer** - `src/sage/lexer.sage` (~300 lines), dict-based keyword lookup, indentation-aware tokenization
- [x] **Parser** - `src/sage/parser.sage` (~700 lines), recursive descent with 12 precedence levels
- [x] **Interpreter** - `src/sage/interpreter.sage` (~920 lines), dict-based value representation, tree-walking evaluation
- [x] **Bootstrap entry point** - `src/sage/sage.sage` runs target `.sage` files through the self-hosted pipeline

#### Native Builtins Added ✅

- [x] **`type()`** - Returns value type as string
- [x] **`chr()`** - Number to character conversion
- [x] **`ord()`** - Character to number conversion
- [x] **`startswith()`** - String prefix check
- [x] **`endswith()`** - String suffix check
- [x] **`contains()`** - Substring search
- [x] **`indexof()`** - Find substring position

#### Bootstrap Coverage ✅

- [x] Arithmetic, variables, if/else, while, for loops
- [x] Functions, recursion, closures, nested functions
- [x] Classes, inheritance, method dispatch
- [x] Arrays, dicts, strings, string builtins
- [x] Try/catch, break/continue, boolean ops
- [x] GC disabled for self-hosted code (`gc_disable()`)

#### Test Suites ✅

- [x] `test_lexer.sage` - 12/12 tests passing
- [x] `test_parser.sage` - 130/130 tests passing
- [x] `test_interpreter.sage` - 18/18 tests passing
- [x] `test_bootstrap.sage` - 18/18 tests passing
- [x] Existing tests maintained: 112 interpreter + 28 compiler tests

---

## 🔧 Build System

Sage supports two build modes via both Make and CMake:

### Make Targets

| Target | Description |
| ------ | ----------- |
| `make` | Build `sage` from C sources (default) |
| `make sage-boot FILE=<file>` | Run a `.sage` file through the self-hosted interpreter |
| `make test-selfhost` | Run all 178 self-hosted tests |
| `make test-selfhost-lexer` | Lexer tests (12) |
| `make test-selfhost-parser` | Parser tests (130) |
| `make test-selfhost-interpreter` | Interpreter tests (18) |
| `make test-selfhost-bootstrap` | Bootstrap tests (18) |
| `make test-all` | Run ALL tests (C + self-hosted) |
| `make cmake-sage` | Setup CMake self-hosted build |
| `make cmake-sage-build` | Build and run self-hosted tests via CMake |

### CMake Options

| Option | Description |
| ------ | ----------- |
| (default) | Build `sage` and `sage-lsp` from C |
| `-DBUILD_SAGE=ON` | Self-hosted mode: builds `sage_host`, provides `sage_boot`, `test_selfhost`, and per-suite test targets |
| `-DBUILD_PICO=ON` | Pico embedded build |
| `-DENABLE_DEBUG=ON` | Debug symbols |
| `-DENABLE_TESTS=ON` | C test executables |

Note: `-DBUILD_SAGE=ON` and the default C build are mutually exclusive. With `BUILD_SAGE`, the C host is built as `sage_host` instead of `sage`.

---

### Phase 14: Networking & Data Interchange
**Status**: ✅ **COMPLETE** (March 9, 2026)

#### Native Networking Modules (src/net.c) ✅

- [x] **`socket` module** - Low-level POSIX sockets (create, bind, listen, accept, connect, send, recv, sendto, recvfrom, close, setopt, poll, resolve, nonblock) with AF_INET/AF_INET6, SOCK_STREAM/SOCK_DGRAM/SOCK_RAW constants
- [x] **`tcp` module** - High-level TCP (connect, listen, accept, send, recv, sendall, recvall, recvline, close)
- [x] **`http` module** - HTTP/HTTPS client via libcurl (get, post, put, delete, patch, head, download, escape, unescape) with options for timeout, redirects, SSL verification, custom headers
- [x] **`ssl` module** - OpenSSL TLS/SSL bindings (context, load_cert, wrap, connect, accept, send, recv, shutdown, free, free_context, error, peer_cert, set_verify)
- [x] **Build system** - libcurl and openssl linked via pkg-config in both Make and CMake

#### cJSON Port (lib/json.sage) ✅

- [x] **Complete 1:1 API port** - ~1,050 lines, mirrors Dave Gamble's cJSON
- [x] **Parsing** - `cJSON_Parse`, `cJSON_ParseWithLength`, `cJSON_GetErrorPtr`
- [x] **Printing** - `cJSON_Print` (formatted), `cJSON_PrintUnformatted` (compact)
- [x] **Creation** - 13 functions: Null, True, False, Bool, Number, String, Raw, Array, Object, IntArray, DoubleArray, FloatArray, StringArray
- [x] **Query** - GetArraySize, GetArrayItem, GetObjectItem (case-insensitive), GetObjectItemCaseSensitive, HasObjectItem, GetStringValue, GetNumberValue
- [x] **Type checks** - 10 functions: IsInvalid, IsFalse, IsTrue, IsBool, IsNull, IsNumber, IsString, IsArray, IsObject, IsRaw
- [x] **Modification** - Array insert/detach/delete/replace, Object add/detach/delete/replace (both case-sensitive and insensitive)
- [x] **Utility** - Duplicate, Compare, Minify, Delete, SetValuestring, SetNumberHelper, Version
- [x] **Sage extras** - `cJSON_ToSage` (tree→native), `cJSON_FromSage` (native→tree)
- [x] **Test suite** - 88 tests passing

---

## 🔮 Future Directions

### Package Manager

- [ ] CLI for dependency management
- [ ] Package registry
- [ ] Version resolution

### Backend Expansion

- [ ] LLVM and native backends for class/module/async support
- [ ] WebAssembly backend

### Ecosystem Growth

- [ ] Mature standard library
- [ ] Production-ready tooling
- [ ] Growing community

---

## 📊 Progress Metrics

- **Phases Completed**: 14/14 (100%)
- **Test Suite**: 112 interpreter tests + 28 compiler tests + 178 self-host tests + 88 JSON tests, 100% pass rate
- **Backends**: C codegen, LLVM IR, native assembly (x86-64, aarch64, rv64)
- **Optimization Passes**: typecheck, constant folding, dead code elimination, function inlining
- **Self-Hosting**: Lexer, parser, and interpreter ported to Sage with full bootstrap

---

## 📝 Recent Updates

### March 9, 2026

- **Phase 14 Complete: Networking & Data Interchange**
- Native networking modules: `socket` (15 functions + constants), `tcp` (9 functions), `http` (9 functions via libcurl), `ssl` (13 functions via OpenSSL)
- cJSON port (`lib/json.sage`, ~1,050 lines) — complete 1:1 API with 88 tests
- Sage extras: `cJSON_ToSage` / `cJSON_FromSage` for native value conversion
- Build system updated for libcurl and openssl linking
- Interpreter bugs documented: instance `==` always false, elif chains with 5+ branches
- **Phase 13 Complete: Self-Hosting**
- Self-hosted lexer (`src/sage/lexer.sage`, ~300 lines), parser (`src/sage/parser.sage`, ~700 lines), interpreter (`src/sage/interpreter.sage`, ~920 lines)
- Token definitions (`src/sage/token.sage`) and AST definitions (`src/sage/ast.sage`)
- Bootstrap entry point (`src/sage/sage.sage`) runs `.sage` files through the self-hosted pipeline
- 7 new native builtins: `type()`, `chr()`, `ord()`, `startswith()`, `endswith()`, `contains()`, `indexof()`
- 178 self-host tests: lexer (12), parser (130), interpreter (18), bootstrap (18)
- All existing tests maintained: 112 interpreter + 28 compiler tests
- Run: `cd self_host && ../sage sage.sage <file.sage>`
- **Phase 12 Complete: Tooling Ecosystem**
- REPL: `sage` (no args) or `sage --repl` with multi-line blocks, error recovery, `:help`/`:quit`
- Formatter: `sage fmt <file>` (in-place) and `sage fmt --check <file>` (check only)
- Linter: `sage lint <file>` with 13 rules (E001-E003 errors, W001-W005 warnings, S001-S005 style)
- Syntax highlighting: TextMate grammar (`editors/sage.tmLanguage.json`), VSCode extension (`editors/vscode/`)
- LSP server: `sage --lsp` or standalone `sage-lsp` binary with diagnostics, completion, hover, formatting
- 4 new compiler tests (Tests 25-28) — 112 interpreter + 28 compiler tests total
- **Phase 11 Complete: Concurrency & Parallelism**
- Native standard library modules: `math`, `io`, `string`, `sys` with `create_native_module()` infrastructure
- Thread module: `thread.spawn`, `thread.join`, `thread.mutex`, `thread.lock`, `thread.unlock`, `thread.sleep`, `thread.id`
- Async/await: `async proc` syntax, `await` expressions, automatic thread spawning on async call
- GC thread safety with mutex-protected collection
- LLVM backend expanded: dict, tuple, slice, get/set, for-in loops, break/continue with loop label stacks
- Native codegen expanded: for-in loops, break/continue with loop label stacks
- 12 new interpreter tests (threads, async, stdlib) — 112 total across 28 categories
- **Phase 10 Complete: Compiler Development**
- LLVM IR generation backend (`--emit-llvm`, `--compile-llvm`) with runtime declarations
- Direct machine code generation (`--emit-asm`, `--compile-native`) via VInst IR for x86-64, aarch64, rv64
- Optimization passes: type checking (`-O1+`), constant folding (`-O1+`), dead code elimination (`-O2+`), function inlining (`-O3`)
- Debug information generation (`-g` flag)
- 24 compiler tests, all passing
- **Codebase Audit & Hardening**
- All `malloc`/`realloc`/`strdup` replaced with `SAGE_ALLOC`/`SAGE_REALLOC`/`SAGE_STRDUP` across entire codebase
- Fixed inlining pass: 6 missing expression types in `substitute_expr()` (ARRAY, DICT, TUPLE, SLICE, GET, SET)
- Added explicit warnings for unimplemented features in LLVM and native backends
- Improved lexer error message for bare `!` operator
- Bounds check for native call arguments (max 255)
- Replaced unsafe `strcpy` with `memcpy` in interpreter and value.c

### March 8, 2026 (continued)

- **Phase 10 Progress: Classes, Modules, Architecture Detection**
- Classes/objects compiled to C: class definitions, inheritance, method dispatch via vtable, property get/set, constructors
- Module imports compiled to C: `import`/`from X import Y` with file resolution, inline code emission
- `asm_arch()` builtin: compile-time architecture detection (x86_64, aarch64, rv64)
- 3 new compiler tests (17 total), all passing

### March 8, 2026

- **Phase 10 Progress: C Backend Expansion**
- For-in loops compiled to C (array iteration)
- Dictionary support: literals, indexing, `dict_keys`, `dict_values`, `dict_has`, `dict_delete`
- Tuple support: literals and indexing
- Exception handling: `try`/`catch`/`finally`/`raise` via `setjmp`/`longjmp`
- Property access (`obj.prop`) as dict key lookup
- `tonumber()` builtin in C backend
- String builtins: `split`, `join`, `replace`, `upper`, `lower`, `strip`
- Memory builtins: `mem_alloc`, `mem_free`, `mem_read`, `mem_write`, `mem_size`
- Struct builtins: `struct_def`, `struct_new`, `struct_get`, `struct_set`, `struct_size`
- `clock()` and `input()` builtins (host target only)
- 7 new compiler tests (14 total), all passing
- Fixed Pico codegen test to use `grep` instead of `rg`

- **Phase 9 Complete: Low-Level Programming**
- C struct interop: `struct_def`, `struct_new`, `struct_get`, `struct_set`, `struct_size`
- 4 new automated tests (100 total, 25 categories)
- **Phase 9: Inline Assembly (Multi-Architecture)**
- `asm_exec`, `asm_compile`, `asm_arch` native functions
- x86-64 native execution, aarch64 and rv64 cross-compilation
- 5 automated tests
- **Phase 9: Raw Memory Operations**
- `mem_alloc`, `mem_free`, `mem_read`, `mem_write`, `mem_size`, `addressof` native functions
- New `VAL_POINTER` type with bounds checking and ownership tracking
- 5 new automated tests (91 total, 23 categories)
- **Phase 9: FFI (Foreign Function Interface)**
- `ffi_open`, `ffi_call`, `ffi_close`, `ffi_sym` for C library interop via dlopen/dlsym
- New `VAL_CLIB` type for library handles
- 3 automated tests for FFI operations
- **Phase 9 Started: Bitwise Operators**
- Full set of bitwise operators: `&`, `|`, `^`, `~`, `<<`, `>>`
- Correct C-style operator precedence integrated into parser
- 6 new automated tests
- **Phase 8.5 Complete: Security & Performance Hardening**
- Full codebase audit: recursion limits, OOM safety, GC pinning, path traversal prevention
- Dictionary rewritten as O(1) hash table (FNV-1a, open-addressing, backward-shift delete)
- Environments integrated into GC sweep cycle with O(1) mark flag
- String operations rewritten for O(n) performance with `size_t` lengths
- Comprehensive test suite: 77 tests across 20 categories, all passing
- **Phase 8 Complete: Module System**
- Module execution pipeline fully working (import, from-import, import-as)
- Module path traversal prevention with `realpath()` containment checks
- VAL_MODULE type with dot-access for module attributes

### December 28, 2025

- Phase 8 Progress: 60% - Function closure support added, module infrastructure complete

### November 29, 2025

- Phase 7 Complete (100%) - Generators with yield/next fully working

### November 28, 2025

- Exception handling complete - try/catch/finally/raise fully functional
- Phase 6 Complete - Object-Oriented Programming

---

## 🤝 Contributing

We welcome contributions at all phases! Here's how you can help:

### Current Priorities

1. **Backend Coverage** - Expand LLVM and native backends for class/module/async support
2. **Package Manager** - CLI for dependency management
3. **Self-Hosted Compiler** - Extend self-hosted interpreter to emit C/LLVM/assembly
4. **Ecosystem Growth** - Standard library expansion, community building

### Getting Started
1. Check the current phase status above
2. Pick an unchecked item or known issue
3. Open an issue to discuss your approach
4. Submit a pull request with your implementation

### Development Areas
- **Core Language**: Parser, interpreter, type system
- **Module System**: Import resolution, standard library
- **Tooling**: Build system, testing framework
- **Documentation**: Guides, examples, API docs
- **Testing**: Unit tests, integration tests

---

## 📞 Contact & Resources

- **Repository**: [github.com/Night-Traders-Dev/SageLang](https://github.com/Night-Traders-Dev/SageLang)
- **License**: MIT
- **Issues**: Use GitHub Issues for bug reports and feature requests
- **Discussions**: Use GitHub Discussions for questions and ideas

---

*This roadmap is a living document and will be updated as the project evolves.*
