# Sage Language - Development Roadmap

> **Last Updated**: March 24, 2026
> **Current Phase**: Phase 16 Complete (LLVM GPU + OpenGL)

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

#### Recursion & Execution Safety ✅

- [x] **Interpreter depth limit** - `MAX_RECURSION_DEPTH 1000` with graceful exception on overflow
- [x] **Parser depth limit** - `MAX_PARSER_DEPTH 500` prevents stack overflow from malicious input
- [x] **Iterative lexer** - `scan_token()` converted from recursive to iterative (`for(;;)` loop)
- [x] **Loop iteration limit** - `MAX_LOOP_ITERATIONS 1000000` prevents runaway `while` loops from exhausting the C stack; throws a catchable exception
- [x] **String literal length limit** - `MAX_STRING_LENGTH 4096` in lexer rejects oversized string literals at parse time, preventing buffer-related crashes
- [x] **Null function guards** - Both `VAL_FUNCTION` and `VAL_NATIVE` call paths check for null function pointers before dispatch, returning nil with an error instead of crashing
- [x] **Type-safe accessor macros** - `SAGE_AS_STRING(v)`, `SAGE_AS_NUMBER(v)`, `SAGE_AS_BOOL(v)` return safe defaults (`""`, `0.0`, `0`) for type mismatches instead of undefined behavior

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
- [x] **Interpreter** - `src/sage/interpreter.sage` (~1050 lines), dict-based value representation, tree-walking evaluation
- [x] **Bootstrap entry point** - `src/sage/sage.sage` runs target `.sage` files through the self-hosted pipeline
- [x] **Module imports** - `import X`, `import X as Y`, `from X import a, b` with module caching and multi-path search
- [x] **Bitwise NOT (~)** - Implemented via two's complement identity `~n = -(n+1)`
- [x] **Loop iteration limits** - While loops capped at 1M iterations (matches C interpreter)
- [x] **array_extend builtin** - Append all elements of one array to another

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
| `make benchmark-python` | Run Sage vs Python 3 benchmarks (5 recipes, 10 workloads) |
| `make benchmark-python-md` | Same as above but output as markdown table |
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

### Phase 15: Vulkan Graphics Library
**Status**: ✅ **COMPLETE** (March 18, 2026)

Professional GPU compute and graphics library for SageLang.

#### Architecture
- [x] 3-layer design: C native module (`gpu`) → `lib/vulkan.sage` (builders) → `lib/gpu.sage` (high-level)
- [x] Handle-table resource management (all Vulkan objects stored internally, exposed via integer handles)
- [x] Conditional compilation: `SAGE_HAS_VULKAN` auto-detected via pkg-config
- [x] Graceful stub mode without Vulkan SDK (constants available, functions return errors)

#### C Native Module (`import gpu`)
- [x] Instance creation with validation layer support and debug callback
- [x] Physical device selection (prefers discrete GPU) and logical device creation
- [x] Queue family detection (dedicated compute/transfer queues when available)
- [x] Buffer lifecycle: create, destroy, upload (float arrays), download, auto-map host-visible
- [x] Image support: 1D/2D/3D, 13 formats (RGBA8/16F/32F, depth, etc.), auto image view creation
- [x] Sampler creation with configurable filter and address modes
- [x] SPIR-V shader module loading from file
- [x] Descriptor set layouts, pools, and sets with buffer/image/sampler binding
- [x] Compute pipeline creation (shader + layout → dispatch)
- [x] Graphics pipeline creation (full config: vertex input, rasterization, blend, depth, topology)
- [x] Render pass and framebuffer creation with auto depth detection
- [x] Command pool/buffer lifecycle, recording, and all command types
- [x] Synchronization: fences (signaled/unsignaled), semaphores, wait/reset
- [x] Queue submission: graphics queue and dedicated compute queue
- [x] 100+ Vulkan enum constants exported (buffer usage, memory, formats, stages, topology, blend, etc.)

#### Sage-Level Libraries
- [x] `lib/vulkan.sage`: String-based builder API (`buffer("storage")`, `shader("path", "compute")`)
- [x] One-liner compute pipeline creation, barrier helpers (compute→host, image layout transitions)
- [x] `lib/gpu.sage`: High-level `run_compute()` for fire-and-forget GPU compute
- [x] Ping-pong buffer management for double-buffered compute
- [x] Device info printer

#### Testing
- [x] 104 GPU tests (constants, API availability, flag composition, init/shutdown, buffer CRUD, sync)
- [x] All 1411+ self-hosted tests passing

---

### Phase 16: LLVM GPU Support & OpenGL Backend

**Status**: ✅ **COMPLETE** (March 24, 2026)

LLVM-compiled GPU support for native-speed 3D game engines, plus OpenGL as a second graphics backend.

#### GPU API Layer ✅

- [x] **`include/gpu_api.h`** — Pure C GPU API (~100 functions), no Value/interpreter dependency
- [x] **`src/c/gpu_api.c`** — Vulkan backend implementation with handle-table design
- [x] Backend selection: `SAGE_GPU_BACKEND_VULKAN`, `SAGE_GPU_BACKEND_OPENGL`, `SAGE_GPU_BACKEND_NONE`
- [x] Shared between interpreter (graphics.c), LLVM compiled path (llvm_runtime.c), and bytecode VM (vm.c)

#### LLVM Backend GPU Support ✅

- [x] **Module import tracking** — `import gpu` now tracked instead of silently skipped
- [x] **GPU constant resolution** — ~120 constants (buffer/image/shader/pipeline/input flags) resolved at compile time
- [x] **GPU method call emission** — `llvm_try_emit_gpu_call()` dispatches ~100 `gpu.method()` calls to `sage_rt_gpu_*`
- [x] **IR prologue declarations** — All `sage_rt_gpu_*` functions declared in LLVM IR output
- [x] **LLVM linking** — `clang` links `gpu_api.o` + `-lvulkan -lglfw -lGL` automatically
- [x] **Module variable handling** — `EXPR_VARIABLE("gpu")` returns nil sentinel (no dangling load)

#### LLVM Runtime GPU Bridge ✅

- [x] **103 `sage_rt_gpu_*` wrapper functions** — Bridge SageValue types to sgpu_* C API
- [x] Dict helper functions for complex type conversions (pipeline configs, attachment arrays)
- [x] Array/float marshaling for buffer upload/download, push constants, uniform updates
- [x] `llvm_runtime.c` expanded from 644 to 1808 lines

#### Bytecode VM GPU Opcodes ✅

- [x] **30 hot-path opcodes** — `BC_OP_GPU_POLL_EVENTS` through `BC_OP_GPU_CMD_DISPATCH`
- [x] Direct `sgpu_*` calls bypassing interpreter for frame-loop performance
- [x] Covers: window events, input, command recording, draw calls, sync, compute dispatch

#### OpenGL Backend ✅

- [x] **Makefile auto-detection** — `OPENGL=auto` via pkg-config, `SAGE_HAS_OPENGL` flag
- [x] **`lib/opengl.sage`** — Drop-in Sage-level wrapper (same API, OpenGL init)
- [x] **`sgpu_init_opengl_windowed()`** — GLFW + OpenGL 4.5 core profile context
- [x] **`sgpu_load_shader_glsl()`** — Direct GLSL shader compilation for OpenGL path

#### Testing ✅

- [x] `test_llvm_gpu.sage` — LLVM GPU constant resolution, module tracking, IR emission
- [x] All 1623+ existing tests pass (341 GPU tests unchanged)
- [x] Build compiles clean with Vulkan + GLFW + OpenGL simultaneously

---

### Phase 16b: LLVM/VM/Bytecode Audit & Benchmarks

**Status**: ✅ **COMPLETE** (March 24, 2026)

Audit of all three execution backends, fixes for found gaps, and a Python 3 comparison benchmark suite.

#### Bytecode VM Fixes ✅

- [x] **Break/continue in bytecode** — loops with break/continue no longer fall to AST interpreter
  - Loop context stack (MAX_LOOP_DEPTH 64, MAX_BREAK_PATCHES 256)
  - Break patches list patched after loop exit; continue jumps to loop top / increment
  - For-loop break emits stack cleanup (pop index, pop array, pop_env) before jump
- [x] **Compiler initialization** — `memset(&compiler, 0, sizeof(compiler))` prevents uninitialized loop_depth
- [x] **10 new opcodes** — `BC_OP_BREAK`, `BC_OP_CONTINUE`, `BC_OP_LOOP_BACK`, `BC_OP_IMPORT`, `BC_OP_CLASS`, `BC_OP_METHOD`, `BC_OP_INHERIT`, `BC_OP_SETUP_TRY`, `BC_OP_END_TRY`, `BC_OP_RAISE`
- [x] All 10 opcodes handled in VM switch (prevents -Wswitch warnings and runtime crash)

#### Memory Safety Fixes ✅

- [x] **program.c**: 8 `malloc`/`realloc`/`calloc` → `SAGE_ALLOC`/`SAGE_REALLOC` (abort-on-OOM)
- [x] **vm.c**: 2 `malloc` in GPU opcodes → `SAGE_ALLOC` + `count > 0` guard

#### Sage vs Python 3 Benchmark Suite ✅

- [x] 10 paired benchmarks: `benchmarks/01_fibonacci.sage` + `.py` through `benchmarks/10_primes_sieve`
- [x] Benchmark runner: `scripts/benchmark_vs_python.py` — tests 5 recipes (Python 3, Sage AST, Sage VM, Sage C, Sage LLVM)
- [x] Makefile targets: `make benchmark-python`, `make benchmark-python-md`
- [x] Correctness verification: all outputs compared across implementations

#### Verification ✅

- [x] All 144 interpreter tests pass (was 142 before fix)
- [x] All 28 compiler tests pass
- [x] Break/continue verified in while + for loops under `--runtime bytecode`

---

### Phase 16c: ASM Backend Audit & UI Library

**Status**: ✅ **COMPLETE** (March 24, 2026)

Native codegen audit and immediate-mode GPU UI widget library.

#### Native Codegen (ASM) Fixes ✅

- [x] **VINST_BRANCH implemented** for all 3 architectures (x86-64, aarch64, rv64) — was completely missing, blocking all if/while/for
- [x] **Comparison operators** — EQ, NEQ, LT, GT, LTE, GTE emitted for x86-64, aarch64, rv64
- [x] **Arithmetic operators** — MOD, ADD, SUB, MUL, DIV emitted for aarch64 and rv64 (were x86-64 only)
- [x] **Logic operators** — AND, OR, NOT, NEG emitted for x86-64
- [x] **Load/store** — LOAD_STRING, LOAD_BOOL, LOAD_NIL, LOAD_GLOBAL, STORE_GLOBAL, CALL_BUILTIN for x86-64
- [x] Uses `sage_rt_get_bool()` for truthy checks in branch conditions (int return, not SageValue)
- [x] **VM constant pool bounds checks** — `VM_CHECK_CONST` and `VM_CHECK_AST` macros prevent buffer overflow on malformed bytecode

#### GPU UI Widget Library ✅

- [x] **`lib/ui.sage`** — Immediate-mode GPU UI library (~400 lines)
- [x] Widgets: Window (draggable), Panel, Button, Label, Checkbox, Slider, Scrollbar, Menu (dropdown), Text Input, Progress Bar, Separator, Tooltip
- [x] Theming: 20+ configurable colors (bg, hover, active, accent, text, etc.) + sizes (padding, border, font)
- [x] Input: mouse position, click/release tracking, hover/active state per widget
- [x] Draw list accumulation for batched GPU rendering
- [x] Works with both Vulkan and OpenGL via `import gpu`

---

### Phase 16d: GC, Exception & Low-Level Audit

**Status**: ✅ **COMPLETE** (March 24, 2026)

Deep audit and fixes across garbage collection, exception handling, and low-level systems.

#### GC Audit Fixes ✅

- [x] **VAL_CLIB cleanup** — gc_release_object() now frees CLibValue name string (was leaked)
- [x] **VAL_POINTER cleanup** — gc_release_object() frees owned memory when PointerValue.owned=1
- [x] **VAL_THREAD cleanup** — gc_release_object() frees thread handle and data allocations
- [x] **VAL_MUTEX cleanup** — gc_release_object() destroys and frees mutex handle via sage_mutex_destroy()
- [x] **GC marking** — gc_mark_value() now marks VAL_CLIB, VAL_POINTER, VAL_THREAD, VAL_MUTEX (prevents premature collection)
- [x] **env_clear_marks() race** — now holds env_mutex during iteration (was unprotected)
- [x] **print_value() NULL safety** — VAL_INSTANCE and VAL_MODULE check chain for NULL before dereference
- [x] **print_value() dict safety** — VAL_DICT checks entries[i].value != NULL before dereference

#### Exception Handling Fixes ✅

- [x] **finally control flow** — finally block return/break/continue/raise now overrides try/catch result (Python/Java semantics)
- [x] **raise value conversion** — numbers, booleans, nil converted to string messages instead of "Unknown error"
- [x] **Exception GC tracking** — gc_release_object() calls gc_track_external_free() for exception messages (was leaking external tracking)

#### Bitwise, FFI, Raw Memory & Struct Audit Fixes ✅

- [x] **Shift bounds checking** — left/right shift amounts validated 0-63; out-of-range returns 0 instead of UB
- [x] **FFI max argument validation** — ffi_call() now rejects >3 arguments with clear error message (was silent)
- [x] **Negative offset prevention** — mem_read() and mem_write() now reject negative offsets (was casting to huge size_t)

---

## 🔮 Future Directions

### Package Manager

- [ ] CLI for dependency management
- [ ] Package registry
- [ ] Version resolution

### Backend Expansion

- [x] ~~LLVM backend for module/GPU support~~ (Phase 16)
- [ ] Native codegen for module/class/GPU support
- [ ] WebAssembly backend
- [ ] JIT compilation via LLVM ORC

### Ecosystem Growth

- [ ] Mature standard library
- [ ] Production-ready tooling
- [ ] Growing community

---

## 📊 Progress Metrics

- **Phases Completed**: 16/16 + 4 audit phases (100%)
- **Test Suite**: 144 interpreter + 28 compiler + 1623 self-host + 88 JSON tests (1883+ total), 100% pass rate
- **Benchmarks**: 10 paired Sage/Python workloads across 5 execution recipes
- **Backends**: C codegen, LLVM IR (with GPU support), native assembly (x86-64, aarch64, rv64), Vulkan + OpenGL graphics
- **Optimization Passes**: typecheck, constant folding, dead code elimination, function inlining
- **Self-Hosting**: Lexer, parser, and interpreter ported to Sage with full bootstrap
- **GPU**: Vulkan + OpenGL graphics engine (5700-line C + 900-line gpu_api, 17 Sage libraries, 27 shaders, 6 demos, PBR/bloom/shadows/deferred/particles)
- **LLVM GPU**: 103 runtime bridge functions, 30 bytecode VM hot-path opcodes, ~120 compile-time GPU constants

---

## 📝 Recent Updates

### March 24, 2026

- **Self-Hosted Interpreter Audit & Improvements**
- Module imports implemented: `import X`, `import X as Y`, `from X import a, b` with caching and multi-path search
- Bitwise NOT (~) implemented via two's complement identity
- Loop iteration limit (1M) added to prevent infinite loops
- array_extend builtin added
- Self-hosted interpreter now ~70% feature-complete vs C (up from ~60%)
- **Phase 16d: GC, Exception & Low-Level Audit**
- GC: cleanup for VAL_CLIB (frees name), VAL_POINTER (frees owned memory), VAL_THREAD (frees handle+data), VAL_MUTEX (destroys+frees)
- GC: marking for all 4 missing types prevents premature collection/use-after-free
- GC: env_clear_marks() now mutex-protected; print_value() NULL-safe for instance/module/dict
- Exceptions: finally block control flow overrides try/catch (return/break/continue/raise propagated)
- Exceptions: raise with non-string values (numbers, booleans, nil) now converts to message string
- Exceptions: gc_track_external_free() on exception message deallocation (was leaking tracking)
- **Phase 16c: ASM Backend Audit & UI Library**
- VINST_BRANCH for all 3 architectures; 15+ VInst operations; VM bounds checks; lib/ui.sage
- **Phase 16b: LLVM/VM/Bytecode Audit & Benchmarks**
- Bytecode VM: break/continue now compile natively (loop context stack with patch lists)
- 10 new bytecode opcodes: BREAK, CONTINUE, LOOP_BACK, IMPORT, CLASS, METHOD, INHERIT, SETUP_TRY, END_TRY, RAISE
- Memory safety: 10 malloc/realloc/calloc → SAGE_ALLOC/SAGE_REALLOC in vm.c + program.c
- Fixed uninitialized loop_depth causing "Loop nesting depth exceeded" errors
- All 144 interpreter + 28 compiler tests pass (was 142 before fix)
- Python 3 benchmark suite: 10 paired workloads (fibonacci, loops, strings, arrays, dicts, classes, nested loops, exceptions, closures, primes)
- Benchmark runner: `scripts/benchmark_vs_python.py` tests 5 recipes; `make benchmark-python`
- **Phase 16 Complete: LLVM GPU Support & OpenGL Backend**
- Pure C GPU API layer (`gpu_api.h/gpu_api.c`) — backend-agnostic, no interpreter dependency
- LLVM backend now handles `import gpu` with full module tracking, constant resolution (~120 constants), and method call dispatch (~100 GPU functions)
- 103 `sage_rt_gpu_*` bridge functions added to LLVM runtime (644 → 1808 lines)
- 30 bytecode VM GPU hot-path opcodes for frame-loop performance (poll_events, key_pressed, cmd_draw, submit, etc.)
- OpenGL 4.5 backend: `SAGE_HAS_OPENGL` auto-detected, `lib/opengl.sage` drop-in wrapper, GLSL shader support
- LLVM compilation links Vulkan + GLFW + OpenGL automatically via clang
- `test_llvm_gpu.sage` test suite added; all 1623+ self-hosted tests passing

### March 18, 2026

- **Phase 15 Complete: Vulkan Graphics Library**
- 3-layer GPU library: C native `gpu` module + `lib/vulkan.sage` builders + `lib/gpu.sage` high-level
- Handle-table Vulkan backend (~2600 lines C) with conditional compilation
- Full resource lifecycle: buffers, images, samplers, shaders, descriptors, pipelines, commands, sync
- Compute and graphics pipeline support with 100+ constants
- Sage-level ergonomic API: string-based builders, one-liner compute dispatch, ping-pong buffers
- 104 new GPU tests; 1411+ self-hosted tests passing
- Also ported: diagnostic.sage (53 tests), gc.sage (45 tests), heartbeat.sage (44 tests)

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

1. **GPU/Graphics** - Windowing (GLFW integration), swapchain support, shader hot-reload
2. **Backend Coverage** - Expand LLVM and native backends for class/module/async support
3. **Package Manager** - CLI for dependency management
4. **Self-Hosted Compiler** - Extend self-hosted interpreter to emit C/LLVM/assembly
5. **Ecosystem Growth** - Standard library expansion, community building

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
