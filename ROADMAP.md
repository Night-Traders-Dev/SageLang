# Sage Language - Development Roadmap

> **Last Updated**: November 28, 2025, 9:00 AM EST  
> **Current Phase**: Phase 6 (COMPLETE) ✅ → Phase 8 (Next)

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
- [x] **Comparison operators** - Full support for `>=` and `<=` in parser and interpreter

---

### Phase 7 (Partial): Advanced Control Flow
**Status**: ✅ **PARTIALLY COMPLETE**

- [x] `for` loops with iterators
- [x] **`break` statement** - Exit loops early
- [x] **`continue` statement** - Skip to next iteration
- [ ] `switch`/`match` expressions
- [ ] Exception handling (`try`/`catch`/`finally`)
- [ ] Defer statements
- [ ] Generator functions (`yield`)

---

## 🔮 Future Phases

### Phase 8: Modules & Package System
**Status**: 📋 Planned (NEXT)

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
**Status**: 📋 Planned

#### Inline Assembly
- [ ] Inline assembly syntax (x86-64)
- [ ] Register allocation for assembly blocks
- [ ] Input/output operand specification
- [ ] Clobber list support
- [ ] Assembly constraint syntax
- [ ] Support for multiple architectures (ARM, RISC-V)

#### Pointer Arithmetic & Raw Memory
- [ ] Pointer types (`*T`, `*const T`, `*mut T`)
- [ ] Address-of operator (`&`, `&mut`)
- [ ] Dereference operator (`*`)
- [ ] Pointer arithmetic
- [ ] Memory-mapped I/O support

#### Foreign Function Interface (FFI)
- [ ] C function calling convention
- [ ] External function declarations
- [ ] Dynamic library loading

---

### Phase 10: Compiler Development
**Status**: 📋 Planned

#### Code Generation
- [ ] C code generation backend
- [ ] LLVM IR generation backend
- [ ] Direct machine code generation (x86-64)
- [ ] Optimization levels (-O0, -O1, -O2, -O3)

---

### Phase 11: Concurrency & Parallelism
**Status**: 📋 Planned

#### Threading
- [ ] Thread creation and management
- [ ] Mutex and locks
- [ ] Thread-local storage

#### Async/Await
- [ ] Async function syntax
- [ ] Await expressions
- [ ] Future/Promise types

---

### Phase 12: Tooling Ecosystem
**Status**: 📋 Planned

#### Developer Tools
- [ ] Language Server Protocol (LSP) implementation
- [ ] Syntax highlighting
- [ ] Code formatter (`sage fmt`)
- [ ] Linter (`sage lint`)
- [ ] Debugger integration

---

### Phase 13: Self-Hosting
**Status**: 📋 Planned (Final Goal)

#### Rewrite Compiler in Sage
- [ ] Port lexer to Sage
- [ ] Port parser to Sage
- [ ] Port interpreter to Sage
- [ ] Bootstrap process

---

## 🎯 Milestone Targets

### Near-Term (1-2 months)
- ✅ Complete Phase 4 (Memory Management) **DONE**
- ✅ Complete Phase 5 (Advanced Data Structures) **DONE**
- ✅ Complete Phase 6 (Object-Oriented Features) **DONE**
- Complete Phase 7 (Advanced Control Flow)
- Begin Phase 8 (Modules)

### Mid-Term (3-6 months)
- Complete Phase 8 (Modules & Packages)
- Begin Phase 9 (Low-level features)
- Start compilation to C

### Long-Term (6-12 months)
- Complete Phase 9 (Low-level features)
- Complete Phase 10 (Full compiler)
- Begin Phase 11 (Concurrency)

### Vision (1-2+ years)
- Fully self-hosted compiler
- Mature ecosystem with package manager
- Production-ready tooling
- Growing community

---

## 📊 Progress Metrics

- **Lines of C Code**: ~50,000+ (current implementation)
- **Implemented Features**: 75/200+ planned (37%)
- **Phases Completed**: 6/13 (46%) + Phase 7 (partial)
- **Estimated Completion**: 2026-2027 (self-hosting)

---

## 🤝 Contributing

We welcome contributions at all phases! Here's how you can help:

### Current Priorities
1. **Advanced Control Flow**: Help complete Phase 7 (match, try/catch)
2. **Module System**: Begin Phase 8 implementation
3. **Testing**: Write test cases for Phase 6 OOP features
4. **Documentation**: Improve code comments and guides
5. **Examples**: Create example programs showcasing OOP

### Getting Started
1. Check the current phase status above
2. Pick an unchecked item that interests you
3. Open an issue to discuss your approach
4. Submit a pull request with your implementation

---

## 📞 Contact & Resources

- **Repository**: [github.com/Night-Traders-Dev/SageLang](https://github.com/Night-Traders-Dev/SageLang)
- **License**: MIT
- **Issues**: Use GitHub Issues for bug reports and feature requests
- **Discussions**: Use GitHub Discussions for questions and ideas

---

*This roadmap is a living document and will be updated as the project evolves.*