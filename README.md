# Sage

**A clean, indentation-based systems programming language built in C.**

Sage is a new programming language that combines the readability of Python (indentation blocks, clean syntax) with the low-level aspirations of C. It is currently in the **bootstrapping phase**, with a fully working interpreter written in C.

## 🚀 Features (Implemented)

- **Indentation-based syntax**: No braces `{}` for blocks; just clean, consistent indentation.
- **Type System**: Support for **Integers**, **Strings**, **Booleans**, and **Nil**.
- **Functions**:
  - Define functions with `proc name(args):`.
  - Full support for recursion and lexical scoping.
- **Native Standard Library**:
  - Built-in functions like `print`, `input`, `clock`, and `tonumber`.
- **Variables**: Lexically scoped variables using `let`.
- **Control Flow**:
  - `if` / `else` conditionals.
  - `while` loops.
- **Arithmetic & Logic**: Standard operators (`+`, `-`, `*`, `/`), string concatenation, and comparisons (`==`, `!=`, `>`, `<`).

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

./sage examples/guess.sage

```

## 📄 Example Code

**`examples/guess.sage`**

```


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

## 🗺 Roadmap

- [x] **Phase 1: Core Logic** (Lexer, Parser, Interpreter, Variables, Loops)
- [x] **Phase 2: Functions** (`proc` definitions, calls, recursion)
- [x] **Phase 3: Types** (Strings, Booleans, Native Functions)
- [ ] **Phase 4: Memory Management** (Garbage Collection)
- [ ] **Phase 5: Compilation** (Codegen to C or LLVM IR)
- [ ] **Phase 6: Self-Hosting** (Re-writing the Sage compiler in Sage)

## 📂 Project Structure

```

sage/
├── include/        \# Header files (AST, Lexer, Parser, Env, Value)
├── src/            \# C implementation
│   ├── main.c      \# Entry point \& file reading
│   ├── lexer.c     \# Tokenization \& Indentation handling
│   ├── parser.c    \# Recursive descent parser
│   ├── ast.c       \# AST node constructors
│   ├── env.c       \# Environment (scope) management
│   ├── value.c     \# Type system \& Object representation
│   └── interpreter.c \# Tree-walking evaluator
├── examples/       \# Example .sage scripts
└── Makefile        \# Build script

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
