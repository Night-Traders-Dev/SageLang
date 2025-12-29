# The SageLang Programming Language: A Comprehensive Guide

## Executive Summary

**SageLang** is a **Python-inspired, systems-oriented programming language** written in C for the RP2040 microcontroller ecosystem. It is a statically-allocated, tree-walking interpreter that combines familiar Python syntax (indentation-based blocks, dynamic typing) with low-level systems capabilities (garbage collection, exception handling, generators, and module imports). The language is implemented across eight phased development cycles, progressing from core arithmetic and control flow through advanced features like generators, exception handling, and a module system for code reuse. This guide documents the language design, internal architecture, runtime semantics, and practical usage patterns derived from the complete C source implementation.

---

## Part 1: Language Overview and Design Philosophy

### 1.1 Design Goals and Target Use Case

SageLang is designed as an **educational and practical embedded scripting language** that:

- **Bridges Python and C**: Provides Python-like syntax and dynamic typing while running in a minimal C footprint suitable for the RP2040.
- **Supports Systems Programming**: Unlike pure Python, SageLang includes explicit garbage collection control, class-based OOP, and low-level value representation suitable for embedded contexts.
- **Phases Incrementally**: The language grows through discrete, completed phases (1–8), each adding a cohesive feature set without breaking prior functionality.
- **Prioritizes Correctness**: Uses explicit memory management (via mark-and-sweep GC), scoped environments, and exception handling rather than relying on OS-level resource management.

### 1.2 Language Characteristics

| Feature | Details |
|---------|---------|
| **Syntax** | Python-like: indentation-based blocks, `:` terminators, keywords like `let`, `proc`, `class` |
| **Type System** | Dynamically typed; values carry runtime type tags (numbers, strings, bools, arrays, dicts, tuples, classes, generators) |
| **Scoping** | Lexical scoping via nested environments; each block/function/class creates a child environment |
| **Memory** | Mark-and-sweep garbage collection with configurable thresholds and manual `gc_collect()` triggers |
| **OOP** | Class-based inheritance with single parent, methods, instance fields, `self` parameter |
| **Control Flow** | `if/else`, `while`, `for...in`, `break`, `continue`, `return`, `try/catch/finally`, `raise`, `yield`, `defer` |
| **Data Structures** | Arrays (dynamic), dicts (string-keyed), tuples (immutable), slicing, indexing |
| **Functions** | First-class `proc` declarations with closures; native C functions; lambdas via generators |
| **Generators** | Full `yield` support with resumable state; `next()` function to iterate |
| **Exceptions** | `try/catch/finally/raise` with explicit exception objects and message strings |
| **Modules** | `import module`, `import module as alias`, `from module import x, y`, `from module import x as y` |

### 1.3 Execution Model

SageLang operates as a **single-pass, tree-walking interpreter**:

1. **Source Code** → **Lexer** (tokenization with indentation tracking)
2. **Tokens** → **Parser** (recursive descent, builds AST)
3. **AST** → **Interpreter** (evaluates statements and expressions)
4. **Runtime Values** stored in **Heap** managed by **GC**

The interpreter maintains a **global environment** and creates **child environments** for scopes (function calls, blocks, class instances). All computations produce **tagged `Value` objects** that are either stack-allocated (numbers, bools) or heap-allocated (arrays, dicts, strings via malloc).

---

## Part 2: Internal Architecture and Core Modules

### 2.1 Module Dependency Graph

```
main.c
  ├─ lexer.c / lexer.h       [Tokenization, indentation tracking]
  ├─ parser.c / parser.h     [AST construction via recursive descent]
  ├─ interpreter.c / interpreter.h  [Tree-walking evaluation]
  ├─ value.c / value.h       [Runtime value representation]
  ├─ env.c / env.h           [Lexical scoping via linked-list environments]
  ├─ gc.c / gc.h             [Mark-and-sweep garbage collection]
  ├─ ast.c / ast.h           [AST node factory functions]
  ├─ token.h                 [Token type enumeration]
  └─ module.c / module.h     [Module loading, caching, imports]
```

### 2.2 Lexer (lexer.c / lexer.h)

**Responsibility**: Convert source text into a stream of **tokens** while tracking indentation levels (Python-style).

**Key Data Structures**:
- **Token**: `{ TokenType type, const char* start, int length, int line }`
- **Lexer State**: `{ const char* start, current, int line, int at_beginning_of_line }`
- **Indent Stack**: Array tracking nesting depth; generates `TOKEN_INDENT` / `TOKEN_DEDENT` automatically

**Token Types** (from token.h):
- **Keywords**: `let`, `var`, `proc`, `if`, `else`, `while`, `for`, `in`, `return`, `print`, `class`, `self`, `init`, `break`, `continue`, `and`, `or`, `try`, `catch`, `finally`, `raise`, `yield`, `defer`, `match`, `case`, `default`, `import`, `from`, `as`, `true`, `false`, `nil`
- **Operators**: `+`, `-`, `*`, `/`, `=`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `and`, `or`
- **Punctuation**: `(`, `)`, `[`, `]`, `{`, `}`, `:`, `,`, `.`
- **Structural**: `INDENT`, `DEDENT`, `NEWLINE`, `EOF`, `ERROR`

**Indentation Handling** (crucial for Python-like syntax):
- Tracks column position at the start of each line.
- Compares current indent to stack top:
  - **Increase**: Push new level, emit `TOKEN_INDENT`.
  - **Decrease**: Pop levels, emit `TOKEN_DEDENT` for each popped level.
  - **Mismatch**: Error if indent doesn't align with a previous level.

**Example**:
```
proc greet(name):
    let msg = "Hello, " + name
    print msg
# Tokens: proc, identifier(greet), (, identifier(name), ), :, newline,
#         indent, let, identifier(msg), =, string, newline,
#         print, identifier(msg), newline,
#         dedent, eof
```

### 2.3 Parser (parser.c)

**Responsibility**: Build an **Abstract Syntax Tree (AST)** from tokens using **recursive descent parsing**.

**Parsing Levels** (operator precedence):
```
expression      → assignment
assignment      → logical_or ("=" assignment)?
logical_or      → logical_and ("or" logical_and)*
logical_and     → equality ("and" equality)*
equality        → comparison (("==" | "!=") comparison)*
comparison      → addition (("<" | ">" | "<=" | ">=") addition)*
addition        → term (("+" | "-") term)*
term            → unary (("*" | "/") unary)*
unary           → ("-" unary) | postfix
postfix         → primary ("[" ... "]" | "." property)*
primary         → NUMBER | STRING | BOOL | NIL | "(" expr ")" | "[" array "]" | "{" dict "}" | IDENTIFIER | CALL
```

**Statement Parsing** (top-down recursive descent):
```
statement   → if_stmt | while_stmt | for_stmt | return_stmt | break | continue | try_stmt | raise_stmt | yield_stmt | print_stmt | expr_stmt
declaration → class_decl | proc_decl | let_decl | statement
```

**Key AST Node Types** (see ast.h/ast.c):
- **Expr** variants: `EXPR_NUMBER`, `EXPR_STRING`, `EXPR_BOOL`, `EXPR_NIL`, `EXPR_VARIABLE`, `EXPR_CALL`, `EXPR_BINARY`, `EXPR_UNARY`, `EXPR_INDEX`, `EXPR_SLICE`, `EXPR_ARRAY`, `EXPR_DICT`, `EXPR_TUPLE`, `EXPR_GET`, `EXPR_SET`
- **Stmt** variants: `STMT_EXPRESSION`, `STMT_LET`, `STMT_PRINT`, `STMT_IF`, `STMT_WHILE`, `STMT_FOR`, `STMT_BLOCK`, `STMT_PROC`, `STMT_CLASS`, `STMT_RETURN`, `STMT_BREAK`, `STMT_CONTINUE`, `STMT_TRY`, `STMT_RAISE`, `STMT_YIELD`, `STMT_DEFER`, `STMT_MATCH`, `STMT_IMPORT`

**Example Parsing**:
```
Input:  let x = 10 + 5
Output: Stmt {
          type: STMT_LET,
          name: Token("x"),
          initializer: Expr {
            type: EXPR_BINARY,
            left: Expr { type: EXPR_NUMBER, value: 10 },
            op: Token(PLUS),
            right: Expr { type: EXPR_NUMBER, value: 5 }
          }
        }
```

### 2.4 Value System (value.h / value.c)

**Responsibility**: Define and manage **runtime value types** and their operations.

**Core Value Type**:
```c
struct Value {
  ValueType type;  // VAL_NUMBER, VAL_STRING, VAL_ARRAY, etc.
  union {
    double number;
    int boolean;
    char* string;
    NativeFn native;
    FunctionValue* function;
    ArrayValue* array;
    DictValue* dict;
    TupleValue* tuple;
    ClassValue* class_val;
    InstanceValue* instance;
    ExceptionValue* exception;
    GeneratorValue* generator;
  } as;
};
```

**Value Types**:

| Type | Storage | Mutable | Use Case |
|------|---------|---------|----------|
| `VAL_NUMBER` | `double` (on stack) | Yes | Integers, floats; `10`, `3.14` |
| `VAL_BOOL` | `int` (on stack) | Yes | Boolean logic; `true`, `false` |
| `VAL_NIL` | N/A | No | Null value; `nil` |
| `VAL_STRING` | `char*` (heap) | No | Text; immutable (assign new to mutate) |
| `VAL_ARRAY` | `ArrayValue*` (dynamic) | Yes | Lists; `[1, 2, 3]`, `push()`, indexing |
| `VAL_DICT` | `DictValue*` (string-keyed) | Yes | Maps; `{"key": value}`, `dict_set()` |
| `VAL_TUPLE` | `TupleValue*` (immutable) | No | Fixed-size sequences; `(1, 2, 3)` |
| `VAL_FUNCTION` | `FunctionValue*` (closure) | No | User-defined procs with captured environment |
| `VAL_NATIVE` | `NativeFn` (C function ptr) | No | Built-in functions like `len()`, `print()` |
| `VAL_CLASS` | `ClassValue*` (metadata) | No | Class definition with methods and parent |
| `VAL_INSTANCE` | `InstanceValue*` (fields dict) | Yes | Object; instance of a class |
| `VAL_EXCEPTION` | `ExceptionValue*` (message) | No | Exception; raised via `raise` |
| `VAL_GENERATOR` | `GeneratorValue*` (resumable) | Yes | Iterable; maintains state across `yield` |

**Array Operations**:
- `array_push(arr, val)`: Append to dynamic array (resizes if needed).
- `array_get(arr, index)`, `array_set(arr, index, val)`: Access/modify.
- `array_slice(arr, start, end)`: Subarray (negative indices supported).

**Dictionary Operations**:
- `dict_set(dict, key, value)`: Insert/update (string keys only).
- `dict_get(dict, key)`, `dict_has(dict, key)`, `dict_delete(dict, key)`.
- `dict_keys(dict)`, `dict_values(dict)`: Return as arrays.

**String Operations**:
- `string_split(str, delim)`, `string_join(arr, sep)`: Splitting/joining arrays.
- `string_replace(str, old, new)`, `string_upper/lower/strip(str)`: Transformation.

**Class/Instance Operations**:
- `class_create(name, parent)`: Define a class with optional parent.
- `class_add_method(class, name, method_stmt)`: Add methods.
- `instance_create(class_def)`: Create instance with empty field dictionary.
- `instance_set_field()`, `instance_get_field()`: Access instance variables.

### 2.5 Environment and Scoping (env.h / env.c)

**Responsibility**: Implement **lexical scoping** via a chain of nested environments (linked list).

**Environment Structure**:
```c
struct Env {
  EnvNode* head;      // Variables defined in this scope (linked list)
  struct Env* parent; // Enclosing scope
};

struct EnvNode {
  char* name;         // Variable name
  Value value;        // Stored value
  struct EnvNode* next;
};
```

**Scoping Rules**:
- **`env_define(env, name, length, value)`**: Create or update a variable **in the current scope only**. If variable exists in current scope, update it; otherwise, create new.
- **`env_get(env, name, length, value*)`**: Look up a variable, searching current scope then parent chains recursively. Return 1 if found, 0 if not.
- **`env_assign(env, name, length, value)`**: Assign to an **existing** variable by searching up the scope chain. Used for reassigning already-defined variables.

**Example Scoping**:
```
Global: { x: 10, y: 20 }
  Block: { z: 30 } → parent: Global
    Inner: { x: 100 } → parent: Block

In Inner scope:
  - env_get("x") → 100 (found in current scope)
  - env_get("z") → 30 (found in parent Block)
  - env_get("y") → 20 (found in Global via parent chain)
```

### 2.6 Garbage Collector (gc.h / gc.c)

**Responsibility**: Automatically reclaim heap memory using **mark-and-sweep** collection.

**GC Overview**:
- **Mark Phase**: Starting from **root set** (global environment, function registry, call stack), mark all reachable objects.
- **Sweep Phase**: Free all unmarked objects and add them to a free pool.
- **Triggering**: Automatic when object count exceeds threshold (~1000 objects), or manual via `gc_collect()`.

**GC Configuration**:
```c
#define GC_HEAP_SIZE (1024 * 1024)  // 1 MB theoretical heap
#define GC_THRESHOLD 1000           // Collect after 1000 object allocations
```

**GC Header** (prepended to all heap allocations):
```c
struct GCHeader {
  int marked;    // 1 = marked (reachable), 0 = unmarked (candidate for freeing)
  int type;      // Object type (VAL_ARRAY, VAL_DICT, etc.)
  void* next;    // Linked list of all allocated objects
};
```

**Root Set**:
- Global environment (`g_global_env`) and its entire scope chain.
- Function registry (linked list of all defined `proc` declarations).
- Call stack (environments of active function calls).

**GC Statistics** (via `gc_stats()` native function):
```
bytes_allocated: Total heap allocated (cumulative)
num_objects: Current number of live objects
collections: Number of GC runs so far
objects_freed: Objects freed in most recent collection
next_gc: Objects until next collection threshold
```

**Usage**:
```sagelang
# Automatic collection when threshold hit
let arr = [1, 2, 3]  # Allocates array

# Manual trigger
gc_collect()

# Check stats
let stats = gc_stats()
print stats
# Output: {"bytes_allocated": 1024, "num_objects": 5, "collections": 2, ...}

# Control GC
gc_disable()  # Pause automatic collection
gc_enable()   # Resume automatic collection
```

### 2.7 Interpreter (interpreter.c / interpreter.h)

**Responsibility**: **Tree-walking evaluation** of the AST, maintaining runtime state and executing statements/expressions.

**Execution Result** (tracks control flow):
```c
struct ExecResult {
  Value value;           // Return value
  int is_returning;      // `return` statement hit
  int is_breaking;       // `break` statement hit
  int is_continuing;     // `continue` statement hit
  int is_throwing;       // Exception raised
  Value exception_value; // Exception object
  int is_yielding;       // `yield` hit (generators)
  void* next_stmt;       // Resume point for generators
};
```

**Statement Execution** (`interpret(stmt, env)`):
- **`STMT_LET`**: Define variable in current scope; evaluate initializer if present.
- **`STMT_EXPRESSION`**: Evaluate expression for side effects.
- **`STMT_PRINT`**: Evaluate expression and print value.
- **`STMT_IF`**: Evaluate condition; execute then-branch or else-branch.
- **`STMT_WHILE`**: Loop while condition is truthy; respect `break`/`continue`.
- **`STMT_FOR`**: Iterate over array/range; update loop variable in scope.
- **`STMT_BLOCK`**: Create child scope, execute statements in sequence.
- **`STMT_PROC`**: Register function in function registry (not executed).
- **`STMT_CLASS`**: Create class object; register methods.
- **`STMT_RETURN`**: Exit function with value.
- **`STMT_TRY`**: Execute try-block; on exception, search matching catch-clause; always run finally-block.
- **`STMT_RAISE`**: Throw exception (string or exception object).
- **`STMT_YIELD`**: In generators, pause execution and return value; next `next()` call resumes.
- **`STMT_IMPORT`**: Load module; populate current environment with imports.

**Expression Evaluation** (`eval_expr(expr, env)`):
- **Literals**: Numbers, strings, bools, nil returned as-is.
- **Variables**: Look up in environment via `env_get()`.
- **Binary Ops**: Evaluate left, then right (short-circuit for `and`/`or`); apply operator.
  - Arithmetic: `+`, `-`, `*`, `/` on numbers; `+` on strings (concatenation).
  - Comparison: `<`, `>`, `<=`, `>=` on numbers; `==`, `!=` on any type.
  - Logical: `and`, `or` with short-circuit evaluation.
- **Calls**: Look up function (user-defined or native); bind arguments to parameters; execute in new environment; return result.
- **Indexing**: Evaluate array and index; return element or slice if range.
- **Array/Dict/Tuple Construction**: Evaluate elements; construct heap-allocated structure.
- **Property Access**: For instances, look up field in instance's field dict.

**Function Call Mechanics**:
1. Resolve callee to `ProcStmt*` or `NativeFn`.
2. Create **child environment** with current scope as parent.
3. Bind parameters to arguments via `env_define()`.
4. Execute function body statements.
5. On `return`, break with value; otherwise use `nil`.
6. Return to caller with result.

**Generator Execution** (Phase 7):
1. `proc my_gen():` creates a function that yields values.
2. Call `my_gen()` → returns `VAL_GENERATOR` value.
3. Call `next(gen)` → initializes generator environment, runs until first `yield`.
4. Each `next()` resumes from saved `current_stmt`; yields next value or `nil` if exhausted.

**Native Function Registry**:
SageLang provides built-in functions injected into global environment via `init_stdlib(env)`:

| Function | Signature | Purpose |
|----------|-----------|---------|
| `len(arr/str/dict)` | `Value → number` | Get length of collection |
| `push(arr, val)` | `(array, value) → nil` | Append to array |
| `pop(arr)` | `array → value` | Remove and return last element |
| `range(start, end)` | `(number, number) → array` | Generate list `[start, start+1, ..., end-1]` |
| `slice(arr, start, end)` | `(array, number, number) → array` | Extract subarray |
| `split(str, delim)` | `(string, string) → array` | Split string by delimiter |
| `join(arr, sep)` | `(array, string) → string` | Join array elements with separator |
| `replace(str, old, new)` | `(string, string, string) → string` | Replace all occurrences |
| `upper(str)` | `string → string` | Uppercase |
| `lower(str)` | `string → string` | Lowercase |
| `strip(str)` | `string → string` | Trim whitespace |
| `str(val)` | `value → string` | Convert to string |
| `tonumber(str)` | `string → number` | Parse number |
| `input()` | `() → string` | Read line from stdin |
| `clock()` | `() → number` | Elapsed seconds since process start |
| `dict_keys(dict)` | `dict → array` | Get keys as array |
| `dict_values(dict)` | `dict → array` | Get values as array |
| `dict_has(dict, key)` | `(dict, string) → bool` | Check if key exists |
| `dict_delete(dict, key)` | `(dict, string) → nil` | Remove key from dict |
| `gc_collect()` | `() → nil` | Trigger garbage collection |
| `gc_stats()` | `() → dict` | Get GC statistics |
| `gc_enable()`, `gc_disable()` | `() → nil` | Control automatic GC |
| `next(gen)` | `generator → value` | Resume generator, get next yielded value |

### 2.8 Module System (module.h / module.c)

**Responsibility**: Load `.sage` files as reusable modules and manage imports.

**Module Structure**:
```c
struct Module {
  char* name;               // Module identifier (e.g., "math")
  char* path;               // Full filesystem path to .sage file
  Environment* env;         // Module's own environment (exports)
  bool is_loaded;           // Execution complete?
  bool is_loading;          // Currently executing? (cycle detection)
  struct Module* next;      // For linked-list cache
};

struct ModuleCache {
  Module* modules;          // All loaded modules
  char** search_paths;      // Directories to search (., ./lib, ./modules)
  int search_path_count;
};
```

**Module Lifecycle**:
1. **`load_module(cache, "math")`**: Search in `search_paths` for `math.sage` or `math/__init__.sage`; create `Module` struct; add to cache.
2. **`execute_module(module, global_env)`**: Read file; lex/parse/interpret in module's own environment (child of global).
3. **Exports**: Any top-level `proc`, `class`, `let` in module becomes available for import.

**Import Statements** (parsed in `parser.c`, executed in `interpreter.c`):

```sagelang
# Import entire module (unaliased)
import math
# → Available as: math (currently placeholder; future: module.sin(), etc.)

# Import module with alias
import math as m
# → Available as: m

# Import specific items
from math import sin, cos
# → sin and cos directly available in scope

# Import specific items with aliases
from math import sin as sine, cos as cosine
# → sine, cosine available in scope

# Star import (all exports)
from math import *
# → All module exports available directly
```

**Search Path Resolution**:
1. Try `{search_path}/module_name.sage`.
2. Try `{search_path}/module_name/__init__.sage`.
3. If not found in any search path, error.

**Default Search Paths**:
```
- "."           (current directory)
- "./lib"       (local lib subdirectory)
- "./modules"   (local modules subdirectory)
```

**Import Processing**:
- `import_all(env, "math")`: Load module, define module name in env.
- `import_from(env, "math", items[], count)`: Load module, look up items, define in env.
- `import_as(env, "math", "m")`: Load module, define alias in env.

**Circular Dependency Detection**: `is_loading` flag prevents infinite loops during module execution.

---

## Part 3: Language Features by Phase

### Phase 1–3: Core Language (Arithmetic, Variables, Control Flow)

**Implemented**: Basic arithmetic, variable declaration, conditionals, loops, functions.

**Example**:
```sagelang
let x = 10
let y = 20
print x + y  # Output: 30

if x > 5:
    print "x is greater than 5"
else:
    print "x is not greater than 5"

proc add(a, b):
    return a + b

print add(3, 4)  # Output: 7
```

### Phase 4: Garbage Collection

**Added**: Mark-and-sweep GC automatically manages heap.

**Example**:
```sagelang
let arr = [1, 2, 3, 4, 5]
print len(arr)          # 5

# GC runs automatically when threshold hit
gc_collect()            # Force collection
let stats = gc_stats()
print stats["collections"]  # Number of GC runs
```

### Phase 5–6: Data Structures and OOP

**Phase 5**: Arrays, dicts, tuples, slicing, indexing.

```sagelang
let arr = [1, 2, 3, 4, 5]
print arr[0]            # 1
print arr[1:3]          # [2, 3]
arr[0] = 10
print arr               # [10, 2, 3, 4, 5]

let dict = {"name": "Alice", "age": 30}
print dict["name"]      # "Alice"
dict["age"] = 31

let tuple = (1, 2, 3)
print tuple             # (1, 2, 3)  # Immutable
```

**Phase 6**: Classes, inheritance, instance methods.

```sagelang
class Animal:
    proc init(name):
        self.name = name
        self.age = 0
    
    proc birthday():
        self.age = self.age + 1
    
    proc speak():
        print self.name + " makes a sound"

class Dog(Animal):
    proc speak():
        print self.name + " barks"

let dog = Dog("Buddy")
print dog.name           # "Buddy"
dog.birthday()
print dog.age            # 1
dog.speak()              # "Buddy barks"
```

### Phase 7: Advanced Control Flow, Exceptions, Generators

**Exceptions**:
```sagelang
proc divide(a, b):
    if b == 0:
        raise "Division by zero"
    return a / b

try:
    print divide(10, 0)
catch e:
    print "Caught error: " + e
finally:
    print "Cleanup done"
```

**Generators**:
```sagelang
proc count_up(n):
    let i = 0
    while i < n:
        yield i
        i = i + 1

let gen = count_up(3)
print next(gen)         # 0
print next(gen)         # 1
print next(gen)         # 2
print next(gen)         # nil (exhausted)
```

**Deferred Code** (Phase 7 addition):
```sagelang
# defer not fully implemented but reserved for cleanup
# Conceptually: defer expr → execute expr at function exit
```

**Pattern Matching** (Phase 7 addition; reserved):
```sagelang
# match/case syntax parsed but not fully evaluated
# Conceptually: match expr over case patterns
```

### Phase 8: Modules

```sagelang
# math.sage
proc sin(x):
    # Approximate sine
    return x  # Stub

proc cos(x):
    return 1  # Stub

# main.sage
import math as m
print m.sin(0)  # Calls math.sin in module's namespace

# Or:
from math import sin, cos
print sin(0)
print cos(0)
```

---

## Part 4: Writing SageLang Programs

### 4.1 Basic Syntax Patterns

**Variables and Types**:
```sagelang
let x = 42                      # Number
let s = "Hello, World"          # String
let b = true                    # Boolean
let arr = [1, 2, 3]             # Array
let dict = {"a": 1, "b": 2}     # Dictionary
let tup = (1, "two", 3)         # Tuple (immutable)
let n = nil                     # Nil (null)
```

**Operators**:
```sagelang
# Arithmetic
print 10 + 5           # 15
print 10 - 5           # 5
print 10 * 5           # 50
print 10 / 2           # 5
print -5               # -5

# Comparison
print 5 == 5           # true
print 5 != 3           # true
print 5 > 3            # true
print 5 < 10           # true

# Logical
print true and false   # false
print true or false    # true
```

**String Operations**:
```sagelang
let a = "Hello"
let b = "World"
print a + " " + b              # "Hello World"

let words = "a,b,c".split(",")
print words                     # ["a", "b", "c"]

let joined = ["x", "y"].join("-")
print joined                    # "x-y"

print "hello".upper()          # "HELLO"
print "HELLO".lower()          # "hello"
```

**Arrays**:
```sagelang
let arr = [10, 20, 30, 40, 50]
print len(arr)                 # 5
print arr[0]                   # 10
arr[0] = 100
print arr[0]                   # 100
push(arr, 60)
print len(arr)                 # 6

# Slicing
print arr[1:3]                 # [20, 30]
print arr[2:]                  # [30, 40, 50, 60] (from index 2 to end)
print arr[:2]                  # [100, 20] (from start to index 2)
```

**Dictionaries**:
```sagelang
let dict = {"name": "Alice", "age": 30}
print dict["name"]             # "Alice"
dict["age"] = 31
print dict_has(dict, "name")   # true
print dict_keys(dict)          # ["name", "age"]
print dict_values(dict)        # ["Alice", 31]

dict_delete(dict, "age")
print dict_has(dict, "age")    # false
```

### 4.2 Control Flow Patterns

**Conditionals**:
```sagelang
let x = 15

if x < 10:
    print "small"
else:
    print "large"

# Nested conditions
if x > 10:
    if x > 20:
        print "very large"
    else:
        print "medium"
else:
    print "small"
```

**Loops**:
```sagelang
# While loop
let i = 0
while i < 5:
    print i
    i = i + 1

# For loop over array
let arr = [10, 20, 30]
for item in arr:
    print item

# For loop over range
for i in range(0, 5):
    print i

# Break and continue
for i in range(0, 10):
    if i == 3:
        continue
    if i == 7:
        break
    print i
```

### 4.3 Functions and Closures

**Function Definition and Call**:
```sagelang
proc greet(name):
    print "Hello, " + name

greet("Alice")

proc add(a, b):
    return a + b

let result = add(5, 3)
print result                   # 8
```

**Closures** (captured environment):
```sagelang
proc make_multiplier(factor):
    proc multiply(x):
        return x * factor     # Captures 'factor' from enclosing scope
    return multiply

let times3 = make_multiplier(3)
let times5 = make_multiplier(5)

print times3(10)              # 30
print times5(10)              # 50
```

### 4.4 Classes and Objects

**Class Definition**:
```sagelang
class Point:
    proc init(x, y):
        self.x = x
        self.y = y
    
    proc distance_from_origin():
        # Simplified (no sqrt)
        return self.x * self.x + self.y * self.y

let p = Point(3, 4)
print p.x                      # 3
print p.y                      # 4
print p.distance_from_origin() # 25
```

**Inheritance**:
```sagelang
class Vehicle:
    proc init(wheels):
        self.wheels = wheels
    
    proc describe():
        print "Vehicle with " + str(self.wheels) + " wheels"

class Car(Vehicle):
    proc init(wheels, doors):
        self.wheels = wheels
        self.doors = doors
    
    proc describe():
        print "Car with " + str(self.wheels) + " wheels and " + str(self.doors) + " doors"

let car = Car(4, 4)
car.describe()                 # "Car with 4 wheels and 4 doors"
```

### 4.5 Exception Handling

**Try-Catch-Finally**:
```sagelang
proc safe_divide(a, b):
    if b == 0:
        raise "Zero denominator"
    return a / b

try:
    let result = safe_divide(10, 0)
catch error:
    print "Error: " + error
finally:
    print "Done"

# Output:
# Error: Zero denominator
# Done
```

### 4.6 Generators

**Simple Generator**:
```sagelang
proc fibonacci(n):
    let a = 0
    let b = 1
    let count = 0
    while count < n:
        yield a
        let temp = a + b
        a = b
        b = temp
        count = count + 1

let gen = fibonacci(5)
print next(gen)                # 0
print next(gen)                # 1
print next(gen)                # 1
print next(gen)                # 2
print next(gen)                # 3
print next(gen)                # nil
```

### 4.7 Modules

**math.sage**:
```sagelang
let PI = 3.14159

proc square(x):
    return x * x

proc cube(x):
    return x * x * x

proc factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)
```

**main.sage**:
```sagelang
import math as m

print m.PI                     # 3.14159
print m.square(5)              # 25
print m.cube(3)                # 27
print m.factorial(5)           # 120

# Or:
from math import PI, square, cube
print PI
print square(5)
print cube(3)
```

---

## Part 5: Implementation Details and Runtime Behavior

### 5.1 Memory Layout and Object Representation

**Stack vs. Heap**:
- **Stack-allocated** (cheap, temporary): `Value` struct for numbers, bools, nil, function pointers.
- **Heap-allocated** (managed by GC): Arrays, dicts, tuples, strings, classes, instances, exceptions, generators.

**Value Encoding** (union-based):
```c
Value v;
v.type = VAL_NUMBER;
v.as.number = 42.5;        // Efficient packing; only one field used per type

// Or:
v.type = VAL_ARRAY;
v.as.array = malloc(...);  // Pointer to ArrayValue struct
```

**Implications**:
- Numbers and bools are always "cheap" to copy (no allocation).
- Strings are immutable; reassignment creates new allocation (handled by parser/interpreter).
- Arrays/dicts are mutable and passed by reference (modifications visible across scopes).

### 5.2 Call Stack and Environments

**On Function Call**:
1. **Create child environment**: `new_env = env_create(current_env)`.
2. **Bind parameters**: `env_define(new_env, param_name, param_value)`.
3. **Execute body**: `interpret(body, new_env)`.
4. **Return**: Pop environment, return to caller.

**Nested Example**:
```
Global: { x: 10 }
  └─ call add(3, 4)
      └─ Local: { a: 3, b: 4 } (parent: Global)
         └─ return a + b (7)
```

### 5.3 Exception Propagation

**Raise Mechanism**:
- `raise "message"` or `raise exception_obj` → Sets `is_throwing = 1` in `ExecResult`.
- All statements/expressions check `is_throwing` and propagate up.
- First matching `catch` clause executes; if none, exception exits function.

**Finally Guarantee**:
- `finally` block always runs, even if exception or return.
- Implemented by checking `is_throwing` / `is_returning` after try/catch, executing finally, then re-raising if needed.

### 5.4 Generator State Management

**Creation**:
- `proc gen_func(): yield 1; yield 2` parses as normal proc.
- **Call** returns `VAL_GENERATOR` with:
  - `body`: Pointer to function body (Stmt*).
  - `closure`: Captured environment at call time.
  - `is_started`: 0 initially.
  - `is_exhausted`: 0 initially.
  - `current_stmt`: NULL (set on first `next()`).

**Resumption**:
- **First `next()`**: Initialize `gen_env` as child of closure, run body until first `yield`.
- **Subsequent `next()`**: Resume from `current_stmt` (set by prior yield), run until next `yield` or end.
- **Yield execution**: Save `current_stmt = stmt->next`, return yielded value with `is_yielding = 1`.

**Example Trace**:
```
gen = my_gen()                    # Create generator, is_started=0
next(gen)                          # Initialize gen_env, run to first yield
                                   # Yield 10; current_stmt = stmt after yield
next(gen)                          # Resume from current_stmt, run to next yield
                                   # Yield 20; current_stmt = stmt after yield
next(gen)                          # Resume, reach end, is_exhausted=1
                                   # Return nil
```

### 5.5 Operator Precedence and Associativity

**Precedence** (lowest to highest):
1. Assignment (`=`)
2. Logical OR (`or`)
3. Logical AND (`and`)
4. Equality (`==`, `!=`)
5. Comparison (`<`, `>`, `<=`, `>=`)
6. Addition/Subtraction (`+`, `-`)
7. Multiplication/Division (`*`, `/`)
8. Unary (`-`)
9. Postfix (indexing, slicing, property access)
10. Primary (literals, variables, parens, function calls)

**Associativity**:
- **Left**: Most binary operators (`+`, `-`, `*`, `/`, `==`, `!=`, `<`, `>`, etc.).
- **Right**: Assignment (`=`), unary (`-`).

### 5.6 Type Coercion and Truthiness

**Truthiness** (for `if`/`while` conditions):
- **Falsy**: `nil`, `false`.
- **Truthy**: Everything else (0 is truthy, empty arrays are truthy, etc.).

**Type Coercion**:
- **Addition**: If both are numbers, add; if either is string, concatenate; else nil.
- **Comparison**: Numbers compared numerically; strings compared lexically; different types are unequal.
- **String conversion**: `str()` native function converts any value to string.

---

## Part 6: Compilation and Execution

### 6.1 Building the Interpreter

**Files to Compile** (typical GCC):
```bash
gcc -o sagelang \
  src/lexer.c \
  src/parser.c \
  src/interpreter.c \
  src/ast.c \
  src/value.c \
  src/env.c \
  src/gc.c \
  src/module.c \
  src/main.c \
  -lm
```

**Execution**:
```bash
./sagelang program.sage
```

### 6.2 Main Entry Point (main.c)

**Initialization**:
```c
int main(int argc, const char* argv[]) {
  gc_init();                    // Initialize garbage collector
  init_module_system();         // Initialize module cache
  
  if (argc == 2) {
    char* source = read_file(argv[1]);
    run(source);                // Lex, parse, interpret
    free(source);
  }
  
  gc_shutdown();
  return 0;
}
```

### 6.3 Program Execution Flow

1. **Read source** from file.
2. **Initialize lexer** with source string.
3. **Initialize parser** (advance to first token).
4. **Create global environment** and initialize stdlib.
5. **Parse declarations** (statements and function definitions).
6. **Interpret each statement** in global environment.
7. **Return** at EOF.

---

## Part 7: Advanced Topics and Internals

### 7.1 Memory Leaks and GC Limitations

**Known Limitations**:
- **String interning**: Strings are not interned; identical strings create separate allocations.
- **Circular references**: GC does not detect cycles (e.g., array containing instance containing array). Use weak references (not implemented) or manual cleanup.
- **Manual `malloc`**: Some internal allocations (e.g., AST nodes, Token data) use `malloc` without GC tracking. Only heap-allocated Values are GC'd.

**Practical Tips**:
- Call `gc_collect()` periodically in long-running loops to prevent heap explosion.
- Avoid creating large temporary structures in loops.
- Reuse arrays/dicts by modifying in-place rather than creating new ones.

### 7.2 Performance Characteristics

**Interpreter Overhead**:
- **Tree-walking**: No bytecode compilation; each node is interpreted individually. Slower than bytecode VM but simpler.
- **Nested scopes**: Linear search up parent chain; O(depth) for variable lookup.
- **GC pauses**: Mark-and-sweep can pause execution during collection; threshold of ~1000 objects may be too small for many applications.

**Optimization Opportunities** (not implemented):
- Bytecode compilation and VM execution.
- Variable lookup caching (memoization).
- Generational GC (mark only young objects frequently).
- JIT compilation for hot paths.

### 7.3 Extending SageLang with Native Functions

**Adding a Native Function**:
```c
// In interpreter.c, add:
static Value my_function(int argCount, Value* args) {
  if (argCount != 2) return val_nil();
  if (!IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
  double result = AS_NUMBER(args[0]) + AS_NUMBER(args[1]) * 2;
  return val_number(result);
}

// In init_stdlib(), add:
env_define(env, "my_func", 7, val_native(my_function));
```

**Usage from SageLang**:
```sagelang
print my_func(3, 4)  # 3 + 4*2 = 11
```

### 7.4 Debugging and Introspection

**Print Value**:
```c
void print_value(Value v);  // In value.c
```

**GC Stats**:
```sagelang
let stats = gc_stats()
print stats  # {"bytes_allocated": ..., "num_objects": ..., ...}
```

**Tracing Execution** (manual):
- Add `printf()` statements to interpreter.c before/after statement/expression evaluation.
- Mark garbage objects: Modify `gc_sweep()` to not free unmarked objects, inspect them.

---

## Part 8: Future Directions and Design Notes

### 8.1 Planned Features (Incomplete Implementations)

**Pattern Matching** (`match`/`case`):
- Parsed but not evaluated.
- Intended: `match value { case 1: ..., case 2: ..., default: ... }`.

**Defer Statements**:
- Parsed but not executed.
- Intended: Cleanup code that always runs at function exit (like `finally` but auto-triggered).

**Standard Library Modules**:
- Stubs in module.c; not fully implemented.
- Intended: `math`, `io`, `string`, `sys`, `json`, etc.

**Multiple Inheritance / Traits**:
- Currently single-parent inheritance only.

**Operator Overloading**:
- No support for custom `__add__()`, etc.

**Type Annotations**:
- Not supported; fully dynamic typing.

### 8.2 Design Decisions and Rationale

**Why Indentation-Based Syntax?**
- Python familiarity for embedded systems developers.
- Reduces bracket clutter in embedded/IoT code.
- Lexer complexity worth the syntactic clarity.

**Why Mark-and-Sweep Over Reference Counting?**
- Simpler to implement; no cycle detection overhead.
- Acceptable for embedded contexts where pause is tolerable.
- Future: Generational GC for better pause times.

**Why Tree-Walking Interpreter?**
- Rapid prototyping and debugging.
- Minimal complexity; easy to extend.
- Suitable for small programs; not for performance-critical workloads.

**Why Classes Over Functions-as-Objects?**
- Explicit OOP model matches C++ style (familiar to embedded developers).
- Clearer semantics for `self` and method dispatch.

---

## Conclusion

**SageLang** is a comprehensive, well-structured scripting language for embedded systems. Its design combines the approachability of Python with the low-level control needed on microcontrollers. The phased development approach (Phases 1–8) demonstrates a thoughtful progression from core features to advanced topics, each phase fully implemented and integrated.

**Key Takeaways**:
- **Lexer + Parser + Interpreter** pipeline is modular and extensible.
- **Value system** supports dynamic typing with heap-allocated complex objects and GC.
- **Scoped environments** enable closures and lexical scoping.
- **Exception handling** and **generators** provide modern control flow.
- **Module system** enables code reuse and abstraction.
- **Mark-and-sweep GC** manages memory automatically.

For developers working with the RP2040 or other microcontrollers, SageLang offers a practical balance between ease of use and systems-level control, making it ideal for prototyping, education, and low-resource embedded scripting tasks.

---

## Appendix: Quick Reference

### Keywords
```
let var proc if else while for in return print
and or break continue class self init
try catch finally raise yield defer
match case default import from as
true false nil
```

### Built-in Functions
```
len(x) push(arr, val) pop(arr) range(a, b)
split(str, delim) join(arr, sep) replace(s, old, new)
upper(s) lower(s) strip(s) slice(arr, a, b)
str(x) tonumber(s) input() clock()
dict_keys(d) dict_values(d) dict_has(d, k) dict_delete(d, k)
gc_collect() gc_stats() gc_enable() gc_disable()
next(gen)
```

### Operators
```
Arithmetic:    + - * /
Comparison:    == != < > <= >=
Logical:       and or
Assignment:    =
Indexing:      arr[i]
Slicing:       arr[a:b]
Property:      obj.field
Call:          func(args)
```

### Example Programs

**Hello World**:
```sagelang
print "Hello, World"
```

**Factorial**:
```sagelang
proc factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

print factorial(5)  # 120
```

**Fibonacci**:
```sagelang
proc fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

for i in range(0, 10):
    print fib(i)
```

**Object-Oriented**:
```sagelang
class Rectangle:
    proc init(width, height):
        self.width = width
        self.height = height
    
    proc area():
        return self.width * self.height

let rect = Rectangle(5, 3)
print rect.area()  # 15
```

