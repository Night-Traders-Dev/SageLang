# Sage Language - Development Roadmap

> **Last Updated**: November 27, 2025  
> **Current Phase**: Phase 3 (Completed) → Phase 4 (In Progress)

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

#### Basic Interpreter
- [x] Tree-walking interpreter
- [x] Expression evaluation
- [x] Statement execution
- [x] Basic arithmetic operations (+, -, *, /)
- [x] Comparison operators (==, !=, <, >, <=, >=)
- [x] Logical operators (and, or, not)

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

#### Native Functions (Standard Library)
- [x] `print()` - Output to console
- [x] `input()` - Read from stdin
- [x] `clock()` - Get current time
- [x] `tonumber()` - String to number conversion

---

## 🚧 Current Phase

### Phase 4: Memory Management
**Status**: 🚧 In Progress

#### Garbage Collection
- [ ] Mark-and-sweep GC implementation
- [ ] Object allocation tracking
- [ ] Root set management
- [ ] Automatic memory reclamation
- [ ] GC statistics and tuning
- [ ] Incremental GC for better performance

#### Memory Safety
- [ ] Bounds checking for arrays/strings
- [ ] Use-after-free detection
- [ ] Memory leak detection tools
- [ ] Reference counting for shared objects

---

## 🔮 Future Phases

### Phase 5: Advanced Data Structures
**Status**: 📋 Planned

#### Collections
- [ ] Arrays/Lists with dynamic sizing
- [ ] Hash maps/Dictionaries
- [ ] Sets
- [ ] Tuples
- [ ] Array slicing syntax
- [ ] List comprehensions

#### Strings Enhancement
- [ ] String interpolation
- [ ] Multi-line strings
- [ ] Raw strings
- [ ] String methods (split, join, replace, etc.)
- [ ] Unicode support

---

### Phase 6: Object-Oriented Features
**Status**: 📋 Planned

- [ ] Class definitions
- [ ] Instance creation and methods
- [ ] Inheritance
- [ ] Method overriding
- [ ] Constructor methods
- [ ] Private/public members
- [ ] Static methods
- [ ] Interfaces/Traits

---

### Phase 7: Advanced Control Flow
**Status**: 📋 Planned

- [ ] `for` loops (C-style and iterators)
- [ ] `break` and `continue` statements
- [ ] `switch`/`match` expressions
- [ ] Exception handling (`try`/`catch`/`finally`)
- [ ] Defer statements
- [ ] Generator functions (`yield`)

---

### Phase 8: Modules & Package System
**Status**: 📋 Planned

#### Module System
- [ ] `import` statement
- [ ] Module namespace resolution
- [ ] Circular dependency detection
- [ ] Module caching
- [ ] Relative imports

#### Package Manager
- [ ] Package manifest format (sage.toml)
- [ ] Dependency resolution
- [ ] Package repository/registry
- [ ] Semantic versioning support
- [ ] Lock file generation

---

### Phase 9: Low-Level Programming & System Features
**Status**: 📋 Planned ⭐ **NEW**

#### Inline Assembly
- [ ] Inline assembly syntax (x86-64)
- [ ] Register allocation for assembly blocks
- [ ] Input/output operand specification
- [ ] Clobber list support
- [ ] Assembly constraint syntax
- [ ] Support for multiple architectures (ARM, RISC-V)
- [ ] Volatile assembly blocks
- [ ] Assembly macro system

**Example Syntax:**
```sage
proc fast_multiply(a: i64, b: i64) -> i64
    let result: i64
    asm
        "mov rax, {a}"
        "imul {b}"
        "mov {result}, rax"
        : "=r"(result)
        : "r"(a), "r"(b)
        : "rax", "rdx"
    return result
```

#### Pointer Arithmetic & Raw Memory
- [ ] Pointer types (`*T`, `*const T`, `*mut T`)
- [ ] Address-of operator (`&`, `&mut`)
- [ ] Dereference operator (`*`)
- [ ] Pointer arithmetic (+, -, offset)
- [ ] Null pointer handling
- [ ] Unsafe blocks for raw memory operations
- [ ] Memory alignment control
- [ ] Volatile memory access
- [ ] Memory-mapped I/O support

#### Bit Manipulation
- [ ] Bitwise operators (&, |, ^, ~, <<, >>)
- [ ] Bit field syntax
- [ ] Packed structs
- [ ] Endianness control
- [ ] Bit rotation operations
- [ ] Population count (popcount)
- [ ] Leading/trailing zero count

#### Foreign Function Interface (FFI)
- [ ] C function calling convention
- [ ] External function declarations
- [ ] Structure layout compatibility
- [ ] Calling convention attributes (`cdecl`, `stdcall`)
- [ ] Dynamic library loading
- [ ] Symbol name mangling control
- [ ] Callback functions from C
- [ ] Type marshalling for FFI

#### System-Level Types
- [ ] Fixed-width integer types (i8, i16, i32, i64, u8, u16, u32, u64)
- [ ] Floating-point types (f32, f64)
- [ ] Size types (usize, isize)
- [ ] Raw byte arrays
- [ ] Union types
- [ ] Opaque types for FFI
- [ ] Function pointer types

#### Memory Management Primitives
- [ ] Manual allocation (`alloc`, `free`)
- [ ] Stack allocation control
- [ ] Custom allocators
- [ ] Memory pool support
- [ ] Arena allocators
- [ ] Memory barriers
- [ ] Atomic operations

---

### Phase 10: Compiler Development
**Status**: 📋 Planned

#### Compilation Pipeline
- [ ] AST optimization passes
- [ ] Intermediate representation (IR) design
- [ ] IR optimization passes
  - [ ] Constant folding
  - [ ] Dead code elimination
  - [ ] Common subexpression elimination
  - [ ] Inlining
- [ ] Type inference engine
- [ ] Static analysis tools

#### Code Generation
- [ ] C code generation backend
- [ ] LLVM IR generation backend
- [ ] Direct machine code generation (x86-64)
- [ ] Optimization levels (-O0, -O1, -O2, -O3)
- [ ] Debug symbol generation
- [ ] Position-independent code (PIC)
- [ ] Link-time optimization (LTO)

#### Compilation Modes
- [ ] Ahead-of-time (AOT) compilation
- [ ] Just-in-time (JIT) compilation
- [ ] Incremental compilation
- [ ] Cross-compilation support
- [ ] Static linking
- [ ] Dynamic linking

---

### Phase 11: Concurrency & Parallelism
**Status**: 📋 Planned

#### Threading
- [ ] Thread creation and management
- [ ] Thread pools
- [ ] Mutex and locks
- [ ] Condition variables
- [ ] Thread-local storage
- [ ] Atomic operations

#### Async/Await
- [ ] Async function syntax
- [ ] Await expressions
- [ ] Future/Promise types
- [ ] Async runtime
- [ ] Event loop

#### Channels & Message Passing
- [ ] Channel creation (bounded/unbounded)
- [ ] Send/receive operations
- [ ] Select statements
- [ ] Actor model support

---

### Phase 12: Tooling Ecosystem
**Status**: 📋 Planned

#### Developer Tools
- [ ] Language Server Protocol (LSP) implementation
- [ ] Syntax highlighting for popular editors
- [ ] Code formatter (`sage fmt`)
- [ ] Linter (`sage lint`)
- [ ] Documentation generator (`sage doc`)
- [ ] REPL (Read-Eval-Print Loop)
- [ ] Debugger (GDB/LLDB integration)

#### Build System
- [ ] Build configuration (sage.toml)
- [ ] Incremental builds
- [ ] Parallel compilation
- [ ] Build caching
- [ ] Cross-platform build support
- [ ] Build scripts

#### Testing Framework
- [ ] Unit testing framework
- [ ] Integration testing support
- [ ] Benchmark framework
- [ ] Code coverage tools
- [ ] Test runner
- [ ] Assertion library

---

### Phase 13: Self-Hosting
**Status**: 📋 Planned (Final Goal)

#### Rewrite Compiler in Sage
- [ ] Port lexer to Sage
- [ ] Port parser to Sage
- [ ] Port AST to Sage
- [ ] Port interpreter to Sage
- [ ] Port code generator to Sage
- [ ] Bootstrap process refinement
- [ ] Performance optimization of self-hosted compiler

#### Documentation
- [ ] Language specification document
- [ ] Standard library reference
- [ ] Compiler internals guide
- [ ] Contribution guidelines
- [ ] Tutorial series
- [ ] Example programs repository

---

## 🎯 Milestone Targets

### Near-Term (3-6 months)
- Complete Phase 4 (Garbage Collection)
- Begin Phase 5 (Arrays and basic collections)
- Implement basic `for` loops
- Add more standard library functions

### Mid-Term (6-12 months)
- Complete Phase 5 and 6 (Data structures + OOP)
- Begin Phase 7 (Advanced control flow)
- Start module system design
- Basic compilation to C

### Long-Term (1-2 years)
- Complete Phase 9 (Low-level features + inline assembly)
- Complete Phase 10 (Full compiler with LLVM backend)
- Begin Phase 11 (Concurrency)
- Start self-hosting efforts

### Vision (2+ years)
- Fully self-hosted compiler
- Mature ecosystem with package manager
- Production-ready tooling
- Growing community and library ecosystem
- Systems programming use cases (OS development, embedded, drivers)

---

## 🔬 Research & Exploration

These are experimental features under consideration:

- [ ] **Compile-time execution**: Meta-programming capabilities
- [ ] **Algebraic effects**: Modern effect system
- [ ] **Linear types**: Resource management and ownership
- [ ] **Dependent types**: Advanced type safety
- [ ] **WebAssembly target**: Browser and edge deployment
- [ ] **GPU compute**: CUDA/OpenCL integration
- [ ] **Formal verification**: Proof-carrying code
- [ ] **Hot code reloading**: Development ergonomics

---

## 🤝 Contributing

We welcome contributions at all phases! Here's how you can help:

### Current Priorities
1. **Memory Management**: Help implement the mark-and-sweep GC
2. **Standard Library**: Add more native functions
3. **Testing**: Write test cases for existing features
4. **Documentation**: Improve code comments and guides
5. **Low-Level Features**: Design proposals for inline assembly syntax

### Getting Started
1. Check the current phase status above
2. Pick an unchecked item that interests you
3. Open an issue to discuss your approach
4. Submit a pull request with your implementation

### Areas of Interest
- **Compiler Enthusiasts**: Phases 10, 13
- **Systems Programmers**: Phase 9 (inline assembly, FFI, low-level)
- **Language Designers**: Phases 6, 7, 11
- **Tooling Developers**: Phase 12
- **Library Authors**: Phase 5, 8

---

## 📊 Progress Metrics

- **Lines of C Code**: ~37,000+ (current implementation)
- **Implemented Features**: 28/200+ planned
- **Test Coverage**: TBD
- **Phases Completed**: 3/13
- **Estimated Completion**: 2027-2028 (self-hosting)

---

## 📜 Version History

- **v0.1.0** (Phase 1-3): Basic interpreter with functions and types
- **v0.2.0** (Phase 4): Planned - Garbage collection
- **v0.3.0** (Phase 5-7): Planned - Advanced features
- **v0.4.0** (Phase 9): Planned - Low-level and inline assembly
- **v0.5.0** (Phase 10): Planned - Compilation to C/LLVM
- **v1.0.0** (Phase 13): Planned - Self-hosted compiler

---

## 📞 Contact & Resources

- **Repository**: [github.com/Night-Traders-Dev/SageLang](https://github.com/Night-Traders-Dev/SageLang)
- **License**: MIT
- **Issues**: Use GitHub Issues for bug reports and feature requests
- **Discussions**: Use GitHub Discussions for questions and ideas

---

*This roadmap is a living document and will be updated as the project evolves.*