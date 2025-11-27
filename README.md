# Sage

**A clean, indentation-based systems programming language built in C.**

Sage is a new programming language that combines the readability of Python (indentation blocks, clean syntax) with the low-level power of C. It is currently in the **bootstrapping phase**, with a fully working interpreter written in C.

## 🚀 Features (Implemented)

- **Indentation-based syntax**: No braces `{}` for blocks; just clean, consistent indentation.
- **Type System**: Support for **Integers**, **Strings**, **Booleans**, and **Nil**.
- **Functions**:
  - Define functions with `proc name(args):`.
  - Full support for recursion and lexical scoping.
  - First-class functions and closures.
- **Native Standard Library**:
  - Built-in functions like `print`, `input`, `clock`, and `tonumber`.
- **Variables**: Lexically scoped variables using `let`.
- **Control Flow**:
  - `if` / `else` conditionals.
  - `while` loops.
- **Arithmetic & Logic**: Standard operators (`+`, `-`, `*`, `/`), string concatenation, and comparisons (`==`, `!=`, `>`, `<`, `>=`, `<=`).

## 🛠 Building Sage

Sage has zero dependencies and builds with standard GCC/Clang.

### Prerequisites
- A C compiler (`gcc` or `clang`)
- `make`

### Build Steps
1. Clone the repository:
```bash
git clone https://github.com/Night-Traders-Dev/SageLang.git
cd SageLang
```

2. Compile:
```bash
make
```
This produces the `sage` executable.

3. Run examples:
```bash
./sage examples/guess.sage
```

## 📄 Example Code

**`examples/guess.sage`**

```sage
# A simple number guessing game

let target = 42
let running = true

print "Guess a number between 0 and 100!"

while running
    let guess_str = input()
    let guess = tonumber(guess_str)
    
    if guess == target
        print "Correct! You win!"
        let running = false
    else
        if guess < target
            print "Too low!"
        else
            print "Too high!"
```

## 🗺 Roadmap (Summary)

- [x] **Phase 1: Core Logic** (Lexer, Parser, Interpreter, Variables, Loops)
- [x] **Phase 2: Functions** (`proc` definitions, calls, recursion)
- [x] **Phase 3: Types** (Strings, Booleans, Native Functions)
- [ ] **Phase 4: Memory Management** (Garbage Collection) 🚧 *In Progress*
- [ ] **Phase 5: Advanced Data Structures** (Arrays, Maps, Sets, Tuples)
- [ ] **Phase 6: Type Annotations & Advanced Types** ⭐ *NEW*
  - Explicit type annotations (`let x: i32 = 5`)
  - Type inference
  - Generic types
  - Algebraic data types
  - Pattern matching
- [ ] **Phase 7: Object-Oriented Features** (Classes, Inheritance, Interfaces)
- [ ] **Phase 8: Modules & Package System** (Imports, Package Manager)
- [ ] **Phase 9: Low-Level Programming** ⭐ *NEW*
  - Inline assembly (x86-64, ARM, RISC-V)
  - Pointer arithmetic and raw memory access
  - FFI (Foreign Function Interface)
  - Bit manipulation
  - System-level types
- [ ] **Phase 10: Compiler Development** (C/LLVM IR codegen)
- [ ] **Phase 11: Concurrency** (Threads, Async/Await, Channels)
- [ ] **Phase 12: Tooling** (LSP, Formatter, Debugger, REPL)
- [ ] **Phase 13: Self-Hosting** (Rewrite compiler in Sage)

**📋 For a detailed breakdown of all planned features, see [ROADMAP.md](ROADMAP.md)**

## 🎯 Vision

Sage aims to be a **systems programming language** that:
- Maintains clean, readable syntax (like Python)
- Provides low-level control (like C/Rust)
- Supports modern type systems with inference
- Enables inline assembly for performance-critical code
- Compiles to native code via C or LLVM
- Eventually becomes self-hosted

### Future Capabilities

**Type System:**
```sage
# Explicit type annotations
proc add(a: i32, b: i32) -> i32
    return a + b

# Generic functions
proc swap<T>(a: T, b: T) -> (T, T)
    return (b, a)

# Pattern matching
match value
    case 0:
        print "Zero"
    case n if n > 0:
        print "Positive"
    case _:
        print "Negative"
```

**Low-Level Programming:**
```sage
# Inline assembly
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

# Pointer operations
proc write_memory(ptr: *mut u8, value: u8)
    unsafe
        *ptr = value
```

## 📂 Project Structure

```
sage/
├── include/          # Header files (AST, Lexer, Parser, Env, Value)
├── src/              # C implementation
│   ├── main.c        # Entry point & file reading
│   ├── lexer.c       # Tokenization & Indentation handling
│   ├── parser.c      # Recursive descent parser
│   ├── ast.c         # AST node constructors
│   ├── env.c         # Environment (scope) management
│   ├── value.c       # Type system & Object representation
│   └── interpreter.c # Tree-walking evaluator
├── examples/         # Example .sage scripts
├── ROADMAP.md        # Detailed development roadmap
├── Makefile          # Build script
└── README.md         # This file
```

## 🤝 Contributing

Sage is an educational project aimed at understanding compiler construction and language design. Contributions are welcome!

### Current Focus Areas
1. **Memory Management**: Implementing garbage collection
2. **Type System**: Designing type annotation syntax
3. **Standard Library**: Adding more native functions
4. **Testing**: Writing test cases for existing features
5. **Documentation**: Improving code comments and guides

### How to Contribute
1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Guidelines
- Follow the existing code style
- Add comments for complex logic
- Update documentation for new features
- Write example code demonstrating new features
- Check the [ROADMAP.md](ROADMAP.md) for planned features

## 📊 Project Stats

- **Language**: C
- **Lines of Code**: ~37,000+
- **Status**: Bootstrapping Phase (Phases 1-3 Complete)
- **License**: MIT
- **Current Version**: v0.1.0

## 🔗 Resources

- **Repository**: [github.com/Night-Traders-Dev/SageLang](https://github.com/Night-Traders-Dev/SageLang)
- **Detailed Roadmap**: [ROADMAP.md](ROADMAP.md)
- **Issues**: [GitHub Issues](https://github.com/Night-Traders-Dev/SageLang/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Night-Traders-Dev/SageLang/discussions)

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.

---

**Built with ❤️ for systems programming enthusiasts**