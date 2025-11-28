# Sage

**A clean, indentation-based systems programming language built in C.**

Sage is a new programming language that combines the readability of Python (indentation blocks, clean syntax) with the low-level power of C. It is currently in the **advanced development phase**, with a fully working interpreter featuring **Object-Oriented Programming**, **Garbage Collection**, and rich data structures.

## 🚀 Features (Implemented)

### Core Language
- **Indentation-based syntax**: No braces `{}` for blocks; just clean, consistent indentation
- **Type System**: Support for **Integers**, **Strings**, **Booleans**, **Nil**, **Arrays**, **Dictionaries**, **Tuples**, **Classes**, and **Instances**
- **Functions**: Define functions with `proc name(args):` with full recursion, closures, and first-class function support
- **Control Flow**: `if`/`else`, `while`, `for` loops, `break`, and `continue`
- **Operators**: Arithmetic (`+`, `-`, `*`, `/`), comparison (`==`, `!=`, `>`, `<`, `>=`, `<=`), logical (`and`, `or`, `not`)

### Object-Oriented Programming 🎉 **NEW**
- **Classes**: `class ClassName:` with full inheritance support
- **Constructors**: `init(self, ...)` method for initialization
- **Methods**: Functions with automatic `self` binding
- **Properties**: Dynamic instance variables via `self.property`
- **Inheritance**: `class Child(Parent):` with method overriding
- **Property Access**: `obj.property` and `obj.property = value`

### Advanced Data Structures
- **Arrays**: Dynamic lists with `push()`, `pop()`, `len()`, and slicing `arr[start:end]`
- **Dictionaries**: Hash maps with `{"key": value}` syntax
- **Tuples**: Immutable sequences `(val1, val2, val3)`
- **Array Slicing**: Pythonic slice syntax for arrays

### Memory Management
- **Garbage Collection**: Automatic mark-and-sweep GC
- **GC Control**: `gc_collect()`, `gc_enable()`, `gc_disable()`
- **Statistics**: `gc_stats()` for memory monitoring
- **Safe**: Prevents use-after-free and memory leaks

### String Operations
- **Methods**: `split()`, `join()`, `replace()`, `upper()`, `lower()`, `strip()`
- **Concatenation**: `"Hello" + " World"`
- **Indexing**: Access individual characters

### Standard Library (30+ Native Functions)
- **Core**: `print()`, `input()`, `clock()`, `tonumber()`, `len()`
- **Arrays**: `push()`, `pop()`, `range()`, `slice()`
- **Strings**: `split()`, `join()`, `replace()`, `upper()`, `lower()`, `strip()`
- **Dictionaries**: `dict_keys()`, `dict_values()`, `dict_has()`, `dict_delete()`
- **GC**: `gc_collect()`, `gc_stats()`, `gc_enable()`, `gc_disable()`

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
make clean && make -j$(nproc)
```
This produces the `sage` executable.

3. Run examples:
```bash
./sage examples/phase6_classes.sage
```

## 📝 Example Code

### Object-Oriented Programming

**`examples/phase6_classes.sage`**

```sage
# Define a class with constructor and methods
class Person:
    proc init(self, name, age):
        self.name = name
        self.age = age
    
    proc greet(self):
        print "Hello, my name is"
        print self.name
        print "I am"
        print self.age
        print "years old"
    
    proc birthday(self):
        self.age = self.age + 1
        print "Happy birthday!"

# Create instances
let alice = Person("Alice", 30)
let bob = Person("Bob", 25)

# Call methods
alice.greet()
alice.birthday()

# Access properties
print alice.name
print alice.age
```

### Inheritance

```sage
# Base class
class Animal:
    proc init(self, name):
        self.name = name
    
    proc speak(self):
        print "Some sound"

# Derived class with method overriding
class Dog(Animal):
    proc init(self, name, breed):
        self.name = name
        self.breed = breed
    
    proc speak(self):
        print "Woof! Woof!"
    
    proc info(self):
        print self.name
        print "is a"
        print self.breed

let dog = Dog("Rex", "Golden Retriever")
dog.speak()  # Prints "Woof! Woof!"
dog.info()
```

### Advanced Data Structures

```sage
# Arrays with methods
let numbers = [1, 2, 3, 4, 5]
push(numbers, 6)
print numbers[0:3]  # [1, 2, 3]
print len(numbers)   # 6

# Dictionaries
let person = {"name": "Alice", "age": "30"}
print person["name"]
person["city"] = "NYC"

let keys = dict_keys(person)
print keys  # ["name", "age", "city"]

# Tuples
let point = (10, 20, 30)
print point[0]  # 10
```

### Memory Management

```sage
# Get GC statistics
let stats = gc_stats()
print stats["bytes_allocated"]
print stats["num_objects"]
print stats["collections"]

# Manual garbage collection
gc_collect()

# Disable GC for performance-critical section
gc_disable()
# ... intensive computation ...
gc_enable()
```

## 🗺 Roadmap (Summary)

- [x] **Phase 1: Core Logic** (Lexer, Parser, Interpreter, Variables, Loops)
- [x] **Phase 2: Functions** (`proc` definitions, calls, recursion, closures)
- [x] **Phase 3: Types & Stdlib** (Strings, Booleans, Native Functions)
- [x] **Phase 4: Memory Management** (Mark-and-Sweep Garbage Collection)
- [x] **Phase 5: Advanced Data Structures** (Arrays, Dictionaries, Tuples, Slicing)
- [x] **Phase 6: Object-Oriented Programming** (Classes, Inheritance, Methods) ✅ **COMPLETE**
- [x] **Phase 7: Control Flow** (Partial: `break`, `continue`) 🔄
- [ ] **Phase 8: Modules & Packages** (Imports, Package Manager) 📋 **NEXT**
- [ ] **Phase 9: Low-Level Programming** ⭐ *Planned*
  - Inline assembly (x86-64, ARM, RISC-V)
  - Pointer arithmetic and raw memory access
  - FFI (Foreign Function Interface)
  - Bit manipulation
- [ ] **Phase 10: Compiler Development** (C/LLVM IR codegen)
- [ ] **Phase 11: Concurrency** (Threads, Async/Await)
- [ ] **Phase 12: Tooling** (LSP, Formatter, Debugger, REPL)
- [ ] **Phase 13: Self-Hosting** (Rewrite compiler in Sage)

**📝 For a detailed breakdown of all planned features, see [ROADMAP.md](ROADMAP.md)**

## 🎯 Vision

Sage aims to be a **systems programming language** that:
- Maintains clean, readable syntax (like Python)
- Provides low-level control (like C/Rust)
- Supports modern OOP with classes and inheritance
- Enables inline assembly for performance-critical code
- Compiles to native code via C or LLVM
- Eventually becomes self-hosted

### Future Capabilities

**Module System:**
```sage
# Import modules
import math
import io from std

# Use imported functions
let result = math.sqrt(16)
io.write_file("output.txt", "Hello")
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

## 📊 Project Stats

- **Language**: C
- **Lines of Code**: ~50,000+
- **Phases Completed**: 6/13 (46%)
- **Status**: Advanced Development (OOP Complete)
- **License**: MIT
- **Current Version**: v0.6.0

## 💾 Project Structure

```
sage/
├── include/          # Header files
│   ├── ast.h         # AST nodes (classes, methods, properties)
│   ├── lexer.h       # Tokenization
│   ├── parser.h      # Syntax analysis
│   ├── env.h         # Scope management
│   ├── value.h       # Type system (classes, instances)
│   ├── gc.h          # Garbage collection
│   └── interpreter.h # Evaluator
├── src/              # C implementation
│   ├── main.c        # Entry point
│   ├── lexer.c       # Tokenizer (class, self, init keywords)
│   ├── parser.c      # Parser (class definitions, property access)
│   ├── ast.c         # AST constructors
│   ├── env.c         # Environment
│   ├── value.c       # Values (ClassValue, InstanceValue)
│   ├── gc.c          # Mark-and-sweep GC
│   └── interpreter.c # Evaluator (class instantiation, methods)
├── examples/         # Example programs
│   ├── phase6_classes.sage  # OOP demonstration
│   ├── phase5_data.sage     # Data structures
│   └── phase4_gc_demo.sage  # GC examples
├── ROADMAP.md        # Detailed development roadmap
├── Makefile          # Build script
└── README.md         # This file
```

## 🤝 Contributing

Sage is an educational project aimed at understanding compiler construction and language design. Contributions are welcome!

### Current Focus Areas
1. **Module System**: Phase 8 implementation (imports, packages)
2. **Complete Control Flow**: `switch`/`match`, exception handling
3. **Testing**: Write test cases for OOP features
4. **Standard Library**: Adding more native functions
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

## 🔗 Resources

- **Repository**: [github.com/Night-Traders-Dev/SageLang](https://github.com/Night-Traders-Dev/SageLang)
- **Detailed Roadmap**: [ROADMAP.md](ROADMAP.md)
- **Issues**: [GitHub Issues](https://github.com/Night-Traders-Dev/SageLang/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Night-Traders-Dev/SageLang/discussions)

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.

---

**Built with ❤️ for systems programming enthusiasts**

**Recent Milestones:**
- ✅ November 27, 2025: Phase 6 Complete - Object-Oriented Programming
- ✅ November 27, 2025: Phase 5 Complete - Advanced Data Structures
- ✅ November 27, 2025: Phase 4 Complete - Garbage Collection