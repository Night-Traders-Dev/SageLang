# Sage

**A clean, indentation-based systems programming language built in C.**

Sage is a new programming language that combines the readability of Python (indentation blocks, clean syntax) with the low-level aspirations of C. It is currently in the **bootstrapping phase**, with a working interpreter written in C, supporting variables, control flow, and blocks.

## 🚀 Features (Implemented)

- **Indentation-based syntax**: No braces `{}` for blocks; just clean, consistent indentation.
- **Interpreter**: A tree-walking interpreter written in standard C.
- **Variables & Environment**: Lexically scoped variables using `let`.
- **Control Flow**:
  - `if` / `else` conditionals.
  - `while` loops.
- **Arithmetic**: Standard operators (`+`, `-`, `*`, `/`) with precedence.
- **Comparisons**: `>`, `<`, equality logic.
- **File Execution**: Runs `.sage` source files directly.

## 🛠 Building Sage

Sage has zero dependencies and builds with standard GCC/Clang.

### Prerequisites
- A C compiler (`gcc` or `clang`)
- `make`

### Build Steps
1. Clone the repository:
   ```
   git clone https://github.com/Night-Traders-Dev/SageLang.git
   cd SageLang
   ```

2. Compile:
   ```
   make
   ```
   This produces the `sage` executable.

3. Run tests:
   ```
   ./sage examples/test.sage
   ```

## 📄 Example Code

**examples/test.sage**

```
let x = 3
while x > 0
    print x
    let x = x - 1

if x < 5
    print 0
else
    print 999
```

**Output:**
```
3
2
1
0
```

## 🗺 Roadmap

- [x] **Phase 1: Core Logic** (Lexer, Parser, Interpreter, Variables, Loops)
- [ ] **Phase 2: Functions** (`proc` definitions, calls, stack frames)
- [ ] **Phase 3: Types** (Static typing `x: int`, structs)
- [ ] **Phase 4: Compilation** (Codegen to C or LLVM IR)
- [ ] **Phase 5: Self-Hosting** (Re-writing the Sage compiler in Sage)

## 📂 Project Structure

```
sage/
├── include/        # Header files (AST, Lexer, Parser, Env)
├── src/            # C implementation
│   ├── main.c      # Entry point & file reading
│   ├── lexer.c     # Tokenization & Indentation handling
│   ├── parser.c    # Recursive descent parser
│   ├── ast.c       # AST node constructors
│   ├── env.c       # Environment (scope) management
│   └── interpreter.c # Tree-walking evaluator
├── examples/       # Example .sage scripts
└── Makefile        # Build script
```

## 🤝 Contributing

Sage is an educational project aimed at understanding compiler construction. Contributions are welcome!

1. Fork the project.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.

