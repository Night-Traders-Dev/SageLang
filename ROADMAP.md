# Sage Language - Development Roadmap

> **Last Updated**: March 8, 2026
> **Current Phase**: Phase 8 Complete, Phase 8.5 (Security & Performance Hardening) Complete

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
- [ ] **Standard library modules** - math, io, collections, string, sys

---

### Phase 8.5: Security & Performance Hardening
**Status**: ✅ **COMPLETE** (March 8, 2026)

A cross-cutting audit and hardening pass across the entire codebase.

#### Recursion Safety ✅

- [x] **Interpreter depth limit** - `MAX_RECURSION_DEPTH 1000` with graceful exception on overflow
- [x] **Parser depth limit** - `MAX_PARSER_DEPTH 500` prevents stack overflow from malicious input
- [x] **Iterative lexer** - `scan_token()` converted from recursive to iterative (`for(;;)` loop)

#### Memory Safety ✅

- [x] **Safe allocation wrappers** - `SAGE_ALLOC`/`SAGE_REALLOC` macros abort on OOM (never return NULL)
- [x] **All malloc/realloc replaced** - Every call site across all source files uses safe wrappers
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

- [x] **77 automated tests** across 20 categories
- [x] **Bash test runner** with EXPECT/EXPECT_ERROR pattern matching
- [x] **Full coverage**: variables, arithmetic, comparison, logic, strings, control flow, loops, functions, arrays, dicts, tuples, classes, inheritance, exceptions, generators, modules, closures, builtins, edge cases, GC

---

## 🔮 Future Phases

### Phase 9: Low-Level Programming & System Features
**Status**: 🚧 In Progress

#### Bit Manipulation ✅
- [x] **Bitwise AND** (`&`) - Integer bitwise AND
- [x] **Bitwise OR** (`|`) - Integer bitwise OR
- [x] **Bitwise XOR** (`^`) - Integer bitwise XOR
- [x] **Bitwise NOT** (`~`) - Integer bitwise complement
- [x] **Left Shift** (`<<`) - Shift bits left
- [x] **Right Shift** (`>>`) - Shift bits right
- [x] **Operator precedence** - Correct C-style precedence (shift → comparison → & → ^ → | → logical)
- [x] **Test coverage** - 6 automated tests for bitwise operations

#### Inline Assembly
- [ ] Inline assembly syntax (x86-64)
- [ ] Register allocation for assembly blocks
- [ ] Input/output operand specification
- [ ] Clobber list support
- [ ] Assembly constraint syntax
- [ ] Support for multiple architectures (ARM, RISC-V)

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
- [ ] Struct interop with C

---

### Phase 10: Compiler Development
**Status**: 📋 Planned

#### Code Generation
- [ ] C code generation backend
- [ ] LLVM IR generation backend
- [ ] Direct machine code generation (x86-64)
- [ ] Optimization levels (-O0, -O1, -O2, -O3)
- [ ] Debug information generation

#### Compilation Pipeline
- [ ] Multi-pass compilation
- [ ] Type checking pass
- [ ] Constant folding
- [ ] Dead code elimination
- [ ] Inlining optimization

---

### Phase 11: Concurrency & Parallelism
**Status**: 📋 Planned

#### Threading
- [ ] Thread creation and management
- [ ] Mutex and locks
- [ ] Thread-local storage
- [ ] Atomic operations

#### Async/Await
- [ ] Async function syntax
- [ ] Await expressions
- [ ] Future/Promise types
- [ ] Event loop implementation

---

### Phase 12: Tooling Ecosystem
**Status**: 📋 Planned

#### Developer Tools
- [ ] Language Server Protocol (LSP) implementation
- [ ] Syntax highlighting
- [ ] Code formatter (`sage fmt`)
- [ ] Linter (`sage lint`)
- [ ] Debugger integration
- [ ] Package manager CLI
- [ ] REPL (Read-Eval-Print Loop)

---

### Phase 13: Self-Hosting
**Status**: 📋 Planned (Final Goal)

#### Rewrite Compiler in Sage
- [ ] Port lexer to Sage
- [ ] Port parser to Sage
- [ ] Port interpreter to Sage
- [ ] Bootstrap process
- [ ] Performance optimization

---

## 🎯 Milestone Targets

### Near-Term (Current)

- Begin Phase 9 (Low-level features)
- Prototype inline assembly or FFI
- Build standard library modules (math, io, collections)

### Mid-Term (1-2 months)

- Complete Phase 9 (Low-level features)
- Begin Phase 10 (Compiler development)
- Start C backend code generation

### Long-Term (2-4 months)

- Complete Phase 10 (Full compiler)
- Begin Phase 11 (Concurrency)
- Async/await or threading prototype

### Vision (6-12+ months)

- Fully self-hosted compiler
- Mature ecosystem with package manager
- Production-ready tooling
- Growing community

---

## 📊 Progress Metrics

- **Phases Completed**: 8.5/13 (65%)
- **Test Suite**: 91 automated tests, 23 categories, 100% pass rate
- **Estimated Completion**: 2026-2027 (self-hosting)

---

## 📝 Recent Updates

### March 8, 2026

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

### Current Priorities (Phase 9)

1. **Low-Level Features** - Inline assembly, pointer arithmetic, FFI
2. **Standard Library** - Implement math, io, string, sys modules in Sage
3. **Testing** - Expand test suite for new features
4. **Documentation** - Keep guide and roadmap current

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
