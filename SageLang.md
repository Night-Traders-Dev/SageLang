# SageLang Reference

> **Version:** 3.8.7 | **Spec Version:** 2.0 | **License:** MIT  
> **Implementation:** Written in C (C11), self-hosted (Sage compiler written in Sage)  
> **Repository:** https://github.com/Night-Traders-Dev/SageLang

SageLang (also called "Sage") is an indentation-based systems programming language combining Python-like readability with C-like performance. It features 10 execution backends, 3 GC modes, full Vulkan+OpenGL graphics, built-in blockchain, ML, LLM, OS dev, networking, and agent AI frameworks.

---

## Table of Contents

1. [Syntax & Semantics](#1-syntax--semantics)
2. [Type System](#2-type-system)
3. [Keywords & Operators](#3-keywords--operators)
4. [Built-in Functions](#4-built-in-functions)
5. [Standard Library](#5-standard-library)
6. [Module System](#6-module-system)
7. [Compiler Pipeline](#7-compiler-pipeline)
8. [Execution Backends](#8-execution-backends)
9. [Memory Management](#9-memory-management)
10. [Tools & Developer Experience](#10-tools--developer-experience)
11. [Metaprogramming & Generics](#11-metaprogramming--generics)
12. [Concurrency](#12-concurrency)
13. [FFI & Low-Level Programming](#13-ffi--low-level-programming)
14. [CLI Reference](#14-cli-reference)

---

## 1. Syntax & Semantics

Sage uses **indentation-based** blocks (like Python). Indentation must be consistent (spaces or tabs, but not mixed). Colons introduce blocks. Newlines terminate simple statements.

### 1.1 Comments

```sage
# Single-line comment
## Doc comment (stored on the following function, retrievable via doc(fn))
```

### 1.2 Variables

```sage
let x = 42               # Immutable binding (reassignment not allowed)
let x: Int = 42          # With type annotation
let x = "Hello"
let y = true
let z = nil
```

`let` creates an immutable variable. There is no `var`/`mut` — all `let` bindings are immutable by design.

### 1.3 Literals

```sage
42                       # Integer (stored as double internally)
3.14                     # Float
"hello"                  # String (UTF-8)
true / false             # Boolean
nil                      # Null value
0xFF                     # Hex
0o755                    # Octal
0b1010                   # Binary
```

### 1.4 Arithmetic Operators

```sage
+   -   *   /   %       # Arithmetic
==  !=  >   <   >=  <=  # Comparison
and or not               # Logical
&   |   ^   ~   <<  >>  # Bitwise
-                        # Unary negate
```

### 1.5 Strings

```sage
let s = "Hello"
let t = "World"
print s + t               # Concatenation: "HelloWorld"
print s[0]                # Character access: "H"
print s[1:4]              # Slice: "ell" (no built-in, use slice())
print len(s)              # Length: 5
```

String escape sequences: `\n`, `\t`, `\r`, `\\`, `\"`, `\xHH`

### 1.6 Control Flow

```sage
# if/else
if age >= 18:
    print "Adult"
else:
    print "Minor"

# while loop
let i = 0
while i < 5:
    print i
    i = i + 1

# for loop (iterates over arrays)
let fruits = ["apple", "banana", "cherry"]
for fruit in fruits:
    print fruit

# for with range() helper
for i in range(10):
    print i

# break and continue
for i in range(10):
    if i == 3:
        continue
    if i == 7:
        break
```

### 1.7 Functions (Procedures)

```sage
# Basic function
proc greet(name):
    print "Hello, " + name

# With return value
proc add(x, y):
    return x + y

# With type annotations
proc multiply(a: Int, b: Int) -> Int:
    return a * b

# Default parameters
proc connect(host, port=8080):
    print "Connecting to " + host + ":" + str(port)

# Generic function
proc identity[T](x: T) -> T:
    return x
```

Functions are defined with `proc` (short for "procedure"). Functions are first-class values (closures are supported).

### 1.8 Arrays

```sage
let arr = [1, 2, 3, 4, 5]
push(arr, 6)                       # Append
pop(arr)                           # Remove last
print arr[0]                       # Index: 1
print arr[1:3]                     # Slice: [2, 3]
print len(arr)                     # Length
array_reverse(arr)
array_contains(arr, 3)            # true/false
```

### 1.9 Dictionaries

```sage
let d = {"name": "Alice", "age": 30}
print d["name"]                    # Access
d["city"] = "NYC"                  # Set
dict_has(d, "age")                # true
dict_keys(d)                      # ["name", "age", "city"]
dict_values(d)                    # ["Alice", 30, "NYC"]
dict_delete(d, "age")
```

### 1.10 Tuples

```sage
let t = (10, 20, 30)
print t[0]                         # 10
# Tuples are immutable - cannot be modified after creation
```

### 1.11 Classes & Inheritance

```sage
class Animal:
    proc init(self, name):
        self.name = name

    proc speak(self):
        print self.name + " makes a sound"

class Dog(Animal):
    proc init(self, name, breed):
        super.init(name)           # Call parent constructor
        self.breed = breed

    proc speak(self):              # Override
        print self.name + " says Woof!"

let dog = Dog("Rex", "Golden")
dog.speak()                        # "Rex says Woof!"
```

Key OOP features:
- `self` is the instance reference (must be the first parameter of every method)
- `init` is the constructor
- `super.method()` calls parent methods (auto-self with `super.init()`)
- `__str__` dunder for custom print output
- `__eq__` dunder for custom equality
- The `->` operator is an alias for `.`

### 1.12 Exception Handling

```sage
try:
    let result = divide(10, 0)
catch e:
    print "Error: " + e
finally:
    print "Cleanup always runs"

# Raise with any value
raise "Something went wrong"
raise 42
raise nil
```

- `try`/`catch`/`finally` blocks
- Exception propagation through call stack
- `finally` control flow (return/break/continue/raise) overrides try/catch result
- Nested try/catch supported

### 1.13 Generators

```sage
proc count_up_to(n):
    let i = 0
    while i < n:
        yield i
        i = i + 1

let gen = count_up_to(3)
print next(gen)           # 0
print next(gen)           # 1
print next(gen)           # 2
```

### 1.14 Match/Case

```sage
match value:
    case 1:
        print "one"
    case 2:
        print "two"
    case X if condition:   # With guard
        print "guarded"
    default:
        print "other"
```

### 1.15 Defer

```sage
proc process_file(name):
    let f = open(name)
    defer close(f)          # Executes on scope exit
    # ... work with f ...
```

### 1.16 Async/Await

```sage
async proc compute(x):
    return x * x

let future = compute(42)
print await future          # 1764
```

Async procs spawn work on a new thread. `await` joins the thread and returns the result.

### 1.17 Structs, Enums, Traits

```sage
# Struct (value type with named fields)
struct Point:
    x: Int
    y: Int

# Enum (tagged variant type)
enum Color:
    Red
    Green
    Blue

# Trait (interface contract)
trait Drawable:
    proc draw(self)
```

### 1.18 Unsafe Blocks

```sage
unsafe:
    # Low-level operations allowed here
    mem_write(ptr, value)
```

### 1.19 Import System

```sage
import math                      # import module
import math as m                 # import with alias
from math import sqrt, pi        # selective import
from math import sqrt as sq      # import with alias
import os.fat                    # dotted path import
from os.fat import parse_boot_sector
```

---

## 2. Type System

### 2.1 Runtime Value Types

All values are tagged unions (`Value` in C). The runtime type determines behavior.

| Type | Description | Example |
|------|-------------|---------|
| `Number` | Double-precision float | `42`, `3.14` |
| `Bool` | Boolean | `true`, `false` |
| `Nil` | Null value | `nil` |
| `String` | UTF-8 string | `"hello"` |
| `Function` | User-defined closure | `proc(x): return x` |
| `Native` | C-backed built-in function | `print`, `len` |
| `Array` | Dynamic growable array | `[1, 2, 3]` |
| `Dict` | Hash map (open-addressing) | `{"a": 1}` |
| `Tuple` | Immutable fixed-size sequence | `(1, 2, 3)` |
| `Class` | Class definition | `class Foo:` |
| `Instance` | Object instance | `Foo()` |
| `Module` | Module reference | `import math` |
| `Exception` | Exception value | `raise "err"` |
| `Generator` | Generator (yield state) | `gen = f()` |
| `CLib` | FFI library handle | `ffi_open()` |
| `Pointer` | Raw memory pointer | `mem_alloc()` |
| `Thread` | Thread handle | `thread.spawn()` |
| `Mutex` | Mutex handle | `thread.mutex()` |
| `Bytes` | Binary-safe byte buffer | `bytes()` |

### 2.2 Type Annotations (v2.0+)

```sage
let x: Int = 42
let name: String = "Alice"
let items: Array[Int] = [1, 2, 3]
let lookup: Dict[String, Int] = {"a": 1}

proc add(a: Int, b: Int) -> Int:
    return a + b

# Optional type (T?)
let maybe: String? = nil
```

Type annotations are **validated at runtime** by the type checker but do not affect execution semantics. The type checker (`sage check file.sage`) reports mismatches.

### 2.3 Structural Equality vs Identity

- `==` uses structural equality for arrays and dicts (same elements)
- Class instances use reference equality by default, or custom `__eq__` dunder

---

## 3. Keywords & Operators

### 3.1 Keywords (54 total)

Full list from `token.h`:

```
let      var      proc     if       else
while    for      return   print
and      or       not      in       break    continue
class    self     init     super
match    case     default
try      catch    finally  raise
defer    yield
async    await
struct   enum     trait
unsafe   end
import   from     as
comptime macro    quote    unquote
true     false    nil
```

**Soft keywords** (v3.8.7+): `match`, `init`, `enum`, `struct`, `trait` — can be used as variable names in expressions and assignments.

### 3.2 Operators (Precedence Table)

The parser uses 12 precedence levels (from lowest to highest):

| Precedence | Operators | Associativity |
|------------|-----------|---------------|
| 1 | `or` | Left |
| 2 | `and` | Left |
| 3 | `==` `!=` | Left |
| 4 | `<` `>` `<=` `>=` `in` | Left |
| 5 | `\|` (bitwise OR) | Left |
| 6 | `^` (bitwise XOR) | Left |
| 7 | `&` (bitwise AND) | Left |
| 8 | `<<` `>>` | Left |
| 9 | `+` `-` | Left |
| 10 | `*` `/` `%` | Left |
| 11 | Unary `-` `~` `not` | Right |
| 12 | `.` `->` `[]` `()` | Left |

---

## 4. Built-in Functions

These are registered as native C functions and are available without any import.

### I/O & Conversion

| Function | Signature | Description |
|----------|-----------|-------------|
| `print` | `print(value)` | Print value to stdout |
| `input` | `input() -> String` | Read line from stdin |
| `clock` | `clock() -> Number` | Wall-clock time in seconds |
| `tonumber` | `tonumber(s) -> Number` | Convert string to number |
| `str` | `str(v) -> String` | Convert value to string |
| `type` | `type(v) -> String` | Get runtime type name |
| `chr` | `chr(n) -> String` | Int to character |
| `ord` | `ord(s) -> Number` | Character to int |

### Collections

| Function | Signature | Description |
|----------|-----------|-------------|
| `len` | `len(v) -> Number` | Length of array, string, dict, bytes |
| `push` | `push(arr, val)` | Append to array |
| `pop` | `pop(arr) -> Value` | Remove and return last element |
| `range` | `range(end)` / `range(start, end, step?)` | Create array range |
| `slice` | `slice(arr, start, end) -> Array` | Slice array |
| `array_reverse` | `array_reverse(arr)` | Reverse in place |
| `array_contains` | `array_contains(arr, val) -> Bool` | Check membership |
| `array_index_of` | `array_index_of(arr, val) -> Number` | Find index |
| `array_min` | `array_min(arr) -> Number` | Minimum value |
| `array_max` | `array_max(arr) -> Number` | Maximum value |
| `array_sum` | `array_sum(arr) -> Number` | Sum of values |
| `array_product` | `array_product(arr) -> Number` | Product of values |
| `array_extend` | `array_extend(arr1, arr2)` | Extend array |
| `array_repeat` | `array_repeat(arr, n) -> Array` | Repeat array |
| `dict_keys` | `dict_keys(d) -> Array` | Get all keys |
| `dict_values` | `dict_values(d) -> Array` | Get all values |
| `dict_has` | `dict_has(d, key) -> Bool` | Check key exists |
| `dict_delete` | `dict_delete(d, key)` | Remove key |

### String

| Function | Signature | Description |
|----------|-----------|-------------|
| `split` | `split(s, delim) -> Array` | Split string |
| `join` | `join(arr, sep) -> String` | Join array |
| `replace` | `replace(s, old, new) -> String` | Replace substring |
| `upper` | `upper(s) -> String` | Uppercase |
| `lower` | `lower(s) -> String` | Lowercase |
| `strip` | `strip(s) -> String` | Trim whitespace |
| `startswith` | `startswith(s, prefix) -> Bool` | Check prefix |
| `endswith` | `endswith(s, suffix) -> Bool` | Check suffix |
| `contains` | `contains(s, sub) -> Bool` | Check substring |
| `indexof` | `indexof(s, sub) -> Number` | Find substring index |
| `string_count` | `string_count(s, sub) -> Number` | Count occurrences |
| `string_repeat` | `string_repeat(s, n) -> String` | Repeat string |

### GC Control

| Function | Description |
|----------|-------------|
| `gc_collect()` | Trigger garbage collection |
| `gc_stats() -> Dict` | Get GC statistics |
| `gc_collections() -> Number` | Collection count |
| `gc_enable()` | Enable GC |
| `gc_disable()` | Disable GC |
| `gc_mode() -> String` | Get current GC mode |
| `gc_set_arc()` | Switch to ARC mode |
| `gc_set_orc()` | Switch to ORC mode |

### Memory & FFI

| Function | Description |
|----------|-------------|
| `mem_alloc(size) -> Pointer` | Allocate raw memory |
| `mem_free(ptr)` | Free raw memory |
| `mem_read(ptr, offset) -> Number` | Read byte at offset |
| `mem_write(ptr, offset, value)` | Write byte at offset |
| `mem_size(ptr) -> Number` | Get allocation size |
| `addressof(v) -> Number` | Get memory address |
| `sizeof(type_name) -> Number` | Get type size |
| `ptr_add(ptr, n) -> Pointer` | Pointer arithmetic |
| `ptr_to_int(ptr) -> Number` | Convert pointer to int |
| `ffi_open(name) -> CLib` | Open shared library |
| `ffi_close(lib)` | Close library |
| `ffi_call(lib, name, arg1?, arg2?, arg3?)` | Call C function |
| `ffi_sym(lib, name) -> Pointer` | Get symbol address |
| `ffi_sym_addr(lib, name)` | Get symbol address (alt) |

### Bytes

| Function | Description |
|----------|-------------|
| `bytes(data?, length?) -> Bytes` | Create byte buffer |
| `bytes_len(b) -> Number` | Get length |
| `bytes_get(b, i) -> Number` | Get byte at index |
| `bytes_set(b, i, val)` | Set byte at index |
| `bytes_to_string(b) -> String` | Convert to string |
| `bytes_slice(b, start, end) -> Bytes` | Slice bytes |
| `bytes_push(b, byte)` | Append byte |

### Struct Interop

| Function | Description |
|----------|-------------|
| `struct_def(fields) -> StructType` | Define struct layout |
| `struct_new(type, ...) -> Pointer` | Create struct instance |
| `struct_get(ptr, field) -> Value` | Read field |
| `struct_set(ptr, field, val)` | Write field |
| `struct_size(type) -> Number` | Get struct size |

### Assembly

| Function | Description |
|----------|-------------|
| `asm_exec(code)` | Execute assembly string |
| `asm_compile(code) -> Bytes` | Compile assembly to machine code |
| `asm_arch() -> String` | Get current architecture |

### Crypto & Misc

| Function | Description |
|----------|-------------|
| `hash(v) -> Number` | FNV-1a hash of string/number/bytes |
| `sha256(data) -> String` | SHA-256 hex digest |
| `doc(fn) -> String` | Get doc comment from function |
| `doc()` | Get module-level doc comment |
| `next(gen) -> Value` | Get next value from generator |

### Path

| Function | Description |
|----------|-------------|
| `path_join(a, b) -> String` | Join path components |
| `path_dirname(p) -> String` | Get directory name |
| `path_basename(p) -> String` | Get file name |
| `path_ext(p) -> String` | Get file extension |
| `path_exists(p) -> Bool` | Check path exists |
| `path_is_dir(p) -> Bool` | Check if directory |
| `path_is_file(p) -> Bool` | Check if file |

### Concurrency

| Function | Description |
|----------|-------------|
| `cpu_count() -> Number` | Total logical CPUs |
| `cpu_physical_cores() -> Number` | Physical core count |
| `cpu_has_hyperthreading() -> Bool` | HT detection |
| `thread_set_affinity(core_id)` | Pin thread to core |
| `thread_get_core() -> Number` | Current core |

### VM

| Function | Description |
|----------|-------------|
| `vm_gas_limit_set(limit)` | Set VM gas limit |
| `vm_gas_used_get() -> Number` | Get gas used |
| `vm_gas_limit_get() -> Number` | Get gas limit |

---

## 5. Standard Library

### 5.1 Native C Modules

Loaded via `import module_name` or `from module_name import func`.

**math** — 25+ math functions:
```sage
import math
math.sqrt(16)    # 4.0
math.sin(0)      # 0.0
math.cos(0)      # 1.0
math.tan(0)      # 0.0
math.pow(2, 10)  # 1024.0
math.log(100)    # 4.605...
math.floor(3.7)  # 3.0
math.ceil(3.2)   # 4.0
math.round(3.5)  # 4.0
math.abs(-5)     # 5.0
math.pi          # 3.14159...
math.e           # 2.71828...
math.inf         # Infinity
math.tau         # 6.28318...
```

**io** — File operations:
```sage
import io
io.readfile("path.txt")       # Read entire file
io.writefile("path.txt", s)   # Write string
io.appendfile("path.txt", s)  # Append string
io.exists("path")             # Check existence
io.remove("path")             # Delete file
io.isdir("path")              # Check if directory
io.filesize("path")           # File size in bytes
io.readbytes("path.img")      # Read as bytes
```

**string** — String utilities:
```sage
import string
string.find(s, sub)           # Find substring position
string.rfind(s, sub)          # Reverse find
string.startswith(s, pre)     # Check prefix
string.endswith(s, suf)       # Check suffix
string.contains(s, sub)       # Check contains
string.char_at(s, i)          # Character at index
string.repeat(s, n)           # Repeat string
string.count(s, sub)          # Count occurrences
string.substr(s, start, len)  # Substring
string.reverse(s)             # Reverse string
```

**sys** — System info:
```sage
import sys
sys.args()                    # Command line arguments (array)
sys.exit(code)                # Exit with code
sys.getenv("PATH")            # Get environment variable
sys.clock()                   # CPU time in seconds
sys.sleep(ms)                 # Sleep in milliseconds
sys.version()                 # Sage version string
sys.platform()                # Platform name
```

**thread** — Threading primitives:
```sage
import thread
thread.spawn(proc_ref, args?) # Spawn thread
thread.join(thread_handle)    # Join thread
thread.mutex()                # Create mutex
thread.lock(mutex)            # Lock mutex
thread.unlock(mutex)          # Unlock mutex
thread.sleep(ms)              # Sleep current thread
thread.id()                   # Current thread ID
```

**socket** — Low-level POSIX sockets:
```sage
import socket
socket.create(domain, type, protocol)
socket.bind(fd, addr, port)
socket.listen(fd, backlog)
socket.accept(fd)
socket.connect(fd, addr, port)
socket.send(fd, data)
socket.recv(fd, size)
socket.sendto(fd, data, addr, port)
socket.recvfrom(fd, size)
socket.close(fd)
socket.setopt(fd, level, opt, val)
socket.poll(fds, timeout)
socket.resolve(hostname)
socket.nonblock(fd)
# Constants: AF_INET, AF_INET6, SOCK_STREAM, SOCK_DGRAM, SOCK_RAW, IPPROTO_TCP, IPPROTO_UDP
```

**tcp** — High-level TCP:
```sage
import tcp
tcp.connect(host, port)
tcp.listen(port)
tcp.accept(server)
tcp.send(conn, data)
tcp.recv(conn, size)
tcp.sendall(conn, data)
tcp.recvall(conn, size)
tcp.recvline(conn)
tcp.close(conn)
```

**http** — HTTP client (via libcurl):
```sage
import http
http.get(url, options?)        # Returns {status, body, headers}
http.post(url, data, options?)
http.put(url, data, options?)
http.delete(url, options?)
http.patch(url, data, options?)
http.head(url, options?)
http.download(url, filepath)
```

**ssl** — OpenSSL bindings:
```sage
import ssl
ssl.context()
ssl.load_cert(ctx, cert_path, key_path)
ssl.wrap(ctx, socket_fd)
ssl.connect(ssl_handle, host, port)
ssl.accept(ssl_handle)
ssl.send(ssl_handle, data)
ssl.recv(ssl_handle, size)
ssl.shutdown(ssl_handle)
ssl.free(ssl_handle)
ssl.free_context(ctx)
ssl.error()
ssl.peer_cert(ssl_handle)
ssl.set_verify(ctx, mode)
```

### 5.2 Pure Sage Standard Library (`lib/std/`)

```sage
import std.regex               # Regular expression engine
import std.datetime            # Date/time creation, formatting
import std.log                 # Structured logging (TRACE-FATAL)
import std.argparse            # CLI argument parser
import std.compress            # RLE, LZ77 compression
import std.process             # Process utilities
import std.unicode             # UTF-8 encoding/decoding
import std.fmt                 # String formatting, hex/bin/oct, tables
import std.testing             # Test suite runner with assertions
import std.enum                # Enumerations, Result/Option types
import std.trait               # Interface/trait system
import std.signal              # Event bus (pub-sub)
import std.db                  # In-memory database (tables, CRUD, joins)
import std.channel             # Go-style buffered channels
import std.threadpool          # Work queue, parallel map
import std.atomic              # Atomic integers, flags, spin locks
import std.rwlock              # Read-write locks
import std.condvar             # Condition variables, barriers
import std.debug               # Value inspection, trace logging
import std.profiler            # Hierarchical profiling
import std.docgen              # Documentation extraction
import std.build               # Project config, dependency declaration
import std.interop             # FFI helpers, struct pack/unpack
```

### 5.3 General Utility Libraries (`lib/`)

```sage
import math                    # pow_int, factorial, gcd, lcm, sqrt helpers
import arrays as arr           # map, filter, reduce, unique, zip, chunk, flatten
import strings                 # contains, padding, repeat helpers
import dicts                   # query helpers, fallback reads
import iter                    # count, range_step, enumerate, cycle, take
import stats                   # mean, variance, stddev, normalization
import assert                  # Test assertions
import utils                   # default_if_nil, swap, head, last
import json                    # cJSON port — parse, print, query, modify
import perf                    # Performance optimization primitives
```

### 5.4 Networking Libraries (`lib/net/`)

```sage
import net.url                 # URL parsing/building, percent-encoding
import net.headers             # HTTP header parsing/building
import net.request             # HTTP request builder
import net.server              # TCP/HTTP server framework
import net.websocket           # WebSocket frame building (RFC 6455)
import net.mime                # MIME type lookup (80+ types)
import net.dns                 # DNS wire-format message parsing
import net.ip                  # IPv4 validation, CIDR subnets
```

### 5.5 Cryptography (`lib/crypto/`)

```sage
import crypto.hash            # SHA-256, SHA-1, CRC-32
import crypto.hmac            # HMAC (RFC 2104)
import crypto.encoding        # Base64, hex encoding/decoding
import crypto.cipher          # XOR, RC4, CBC/CTR mode helpers
import crypto.rand            # xoshiro256** PRNG, UUID v4, Fisher-Yates
import crypto.password        # PBKDF2-HMAC, password hashing/verification
```

### 5.6 Machine Learning (`lib/ml/`)

```sage
import ml.tensor              # N-dimensional tensors with shape tracking
import ml.nn                  # Neural network layers (Linear, ReLU, Sigmoid, etc.)
import ml.optim               # SGD, Adam, learning rate schedulers
import ml.loss                # MSE, cross-entropy, Huber, KL divergence
import ml.data                # Dataset/DataLoader, batching, normalization
import ml.debug               # Weight stats, gradient checking
import ml.viz                 # SVG chart generation
import ml.monitor             # Live training monitor
import ml.gpu_accel           # GPU-accelerated ML ops with CPU fallback
import ml.npu                 # NPU backend (Qualcomm, Exynos, NNAPI, ARM NEON)
```

### 5.7 GPU Graphics (`lib/graphics/`)

```sage
import graphics.math3d        # Vectors, matrices, quaternions, camera
import graphics.mesh          # Procedural mesh generation, OBJ loading
import graphics.renderer      # Frame loop, resource management
import graphics.camera        # Camera controllers
import graphics.scene         # Scene graph
import graphics.material      # Shader+texture binding
import graphics.pbr           # Cook-Torrance PBR materials
import graphics.postprocess   # HDR, bloom, tonemapping
import graphics.shadows       # Cascade shadow maps
import graphics.deferred      # G-buffer, SSAO, SSR
import graphics.taa           # Temporal anti-aliasing
import graphics.gltf          # glTF 2.0 loading
import graphics.asset_cache   # Texture/mesh caching
import graphics.frame_graph   # Render graph
import graphics.debug_ui     # Debug overlay
import graphics.ui            # Immediate-mode GPU UI
```

### 5.8 LLM / Neural Networks (`lib/llm/`)

```sage
import llm.config             # Model configurations (tiny to Llama-13B)
import llm.tokenizer          # Character, word, BPE tokenizers
import llm.embedding          # Token/RoPE positional embeddings
import llm.attention          # Multi-head self-attention, KV cache
import llm.transformer        # Transformer blocks, full model assembly
import llm.generate           # Greedy, top-k/p, beam search generation
import llm.train              # Training loops, LR schedules
import llm.agent              # Agentic LLM framework
import llm.prompt             # Chat formatting (ChatML, Llama, Alpaca)
import llm.lora               # LoRA fine-tuning adapters
import llm.quantize           # Int8/int4 weight quantization
import llm.engram             # Persistent neural memory
import llm.rag                # Retrieval-augmented generation
import llm.dpo                # Direct Preference Optimization
import llm.gguf               # GGUF export for Ollama/llama.cpp
import llm.gguf_import        # Import GGUF models
import llm.turboquant         # 3-bit KV cache quantization (ICLR 2026)
import llm.autoresearch       # Autonomous research agent
import llm.evolve             # Self-evolving neural architectures
```

### 5.9 OS Development (`lib/os/`)

44+ modules for bare-metal, UEFI, bootloader, kernel, and filesystem development:

```sage
import os.fat                 # FAT8/12/16/32 boot sector parser
import os.fat_dir             # FAT directory traversal
import os.elf                 # ELF32/64 header parsing
import os.mbr                 # MBR partition table
import os.gpt                 # GPT header parsing
import os.pe                  # PE/COFF header parsing
import os.pci                 # PCI config space
import os.uefi                # UEFI/EFI memory map, config tables
import os.acpi                # ACPI table parsers (MADT, FADT, HPET, MCFG)
import os.paging              # x86-64 page table entries
import os.idt                 # x86-64 interrupt descriptor table
import os.serial              # UART/COM port configuration
import os.dtb                 # Flattened Device Tree parser
import os.alloc               # Bump, free-list, bitmap allocators
import os.vfs                 # Virtual filesystem abstraction
import os.ext                 # ext2/3/4 filesystem
import os.btrfs               # Btrfs superblock, chunk tree
import os.f2fs                # F2FS superblock, segment info
import os.boot.start          # Boot assembly generation (x86_64, aarch64, riscv64)
import os.boot.multiboot      # Multiboot2 header generation
import os.boot.gdt            # x86_64 GDT descriptor construction
import os.boot.linker         # Linker script generation
import os.kernel.kmain        # Kernel entry point scaffolding
import os.kernel.console      # VGA text-mode console
import os.kernel.keyboard     # PS/2 keyboard driver
import os.kernel.timer        # PIT timer, IRQ0 handler
import os.kernel.syscall      # SYSCALL/SYSRET dispatch
import os.kernel.pmm          # Physical memory manager
import os.kernel.vmm          # Virtual memory manager
import os.image.diskimg       # Bootable disk image builder (.img)
import os.image.iso           # ISO 9660 image creation
import os.qemu                # QEMU VM launcher (3 architectures)
```

### 5.10 Blockchain (`lib/blockchain/`)

```sage
import blockchain.blockchain  # Main ledger, mempool, consensus
import blockchain.wallet      # HD address generation, signing
import blockchain.consensus   # Pluggable PoW and PoA
import blockchain.contract    # Smart contract management
import blockchain.std.nft     # SNFT-721 NFT standard
import blockchain.rpc         # JSON-RPC 2.0 API
import blockchain.net         # P2P networking
```

### 5.11 Agent AI Framework (`lib/agent/`)

```sage
import agent.core             # ReAct agent loop
import agent.tools            # Pre-built tools (file, code, search)
import agent.planner          # Task decomposition with DAG
import agent.router           # Multi-agent orchestrator
import agent.supervisor       # Supervisor-Worker control plane
import agent.critic           # Verification loops
import agent.schema           # Typed tool interfaces
import agent.trace            # SFT trace recording
import agent.grammar          # Grammar-constrained decoding
import agent.sandbox          # Sandboxed Sage code execution
import agent.tot              # Tree of Thoughts with MCTS
import agent.semantic_router  # Fast command dispatch
```

### 5.12 CUDA (`lib/cuda/`)

```sage
import cuda.device            # GPU device descriptors, architecture detection
import cuda.memory            # GPU memory allocation, host/device transfers
import cuda.kernel            # Kernel definition, 1D/2D/3D launch
import cuda.stream            # CUDA streams, events, timing
```

### 5.13 Discord Bot (`lib/discord/`)

```sage
import discord.gateway        # Gateway API (WebSocket)
import discord.rest           # REST API
```

### 5.14 Android (`lib/android/`)

```sage
import android.app            # Application framework
import android.ui             # UI components
```

---

## 6. Module System

### 6.1 Import Syntax

```sage
import math                          # Load module, access via math.sqrt()
import math as m                     # Alias
from math import sqrt, pi            # Selective import
from math import sqrt as sq          # Aliased selective import
import os.fat                        # Dotted path (directory-based)
import os.fat as fat_module          # Aliased dotted
from os.fat import parse_boot_sector # Selective from submodule
```

### 6.2 Module Resolution

Module search order:
1. `./filename.sage` (relative to current file)
2. `lib/module_name.sage`, `lib/path/to/module.sage` (standard library)
3. Paths in environment variable `SAGE_LIB_PATH`

Directory packages use `__init__.sage` as the module entry point.

### 6.3 Export Behavior

- Top-level `let` bindings and `proc` definitions are exported
- There is no explicit `export` keyword — all top-level names are visible to importers
- Module caching: modules are loaded only once per session

---

## 7. Compiler Pipeline

The compiler pipeline has multiple phases applicable at different optimization levels.

### 7.1 Phases

```
Source Code
    ↓
[1] Lexer (lexer.c)              — Indentation-aware tokenizer
    ↓
[2] Parser (parser.c)            — Recursive descent, 12 precedence levels
    ↓
[3] Optimization Passes (based on -O level):
    ├── -O1: Constant Folding (constfold.c)   — Pre-computes constant expressions
    ├── -O2: Dead Code Elimination (dce.c)    — Removes unreachable code, unused bindings
    └── -O3: Function Inlining (inline.c)     — Inlines small non-recursive procs
    ↓
[4] Type Checker (typecheck.c)   — Validates type annotations (run at -O1+)
    ↓
[5] Code Generation (one of):
    ├── AST Interpreter          — Direct tree-walking execution
    ├── Bytecode Compiler        — Compiles to stack-based bytecode
    ├── C Backend                — Generates standalone C source
    ├── LLVM IR Backend          — Generates .ll LLVM IR
    ├── Native Assembly          — Direct machine code (x86-64, aarch64, rv64, mips)
    ├── JIT Compiler             — Profiling + native code generation
    ├── AOT Compiler             — Type-specialized ahead-of-time compilation
    └── Kotlin Backend           — Android/Kotlin transpilation
```

### 7.2 Lexer Details

- Indentation-aware: tracks INDENT/DEDENT tokens
- Bracket-aware: `{}`, `[]`, `()` suppress INDENT/DEDENT inside expressions
- Keyword recognition via hash table
- Max identifier length: 1024 chars
- Max string literal length: 4096 chars
- Token types: 54 defined
- Doc comments (`##`) stored as TOKEN_DOC_COMMENT

### 7.3 Parser Details

- Recursive descent parser
- 12 precedence levels for operators
- Error recovery for REPL mode
- Recursion depth limit: 100,000
- AST nodes:
  - **Expressions** (18 types): NUMBER, STRING, BOOL, NIL, BINARY, VARIABLE, CALL, ARRAY, INDEX, DICT, TUPLE, SLICE, GET, SET, INDEX_SET, AWAIT, SUPER, COMPTIME
  - **Statements** (22 types): PRINT, EXPRESSION, LET, IF, BLOCK, WHILE, PROC, FOR, RETURN, BREAK, CONTINUE, CLASS, MATCH, DEFER, TRY, RAISE, YIELD, IMPORT, ASYNC_PROC, STRUCT, ENUM, TRAIT, COMPTIME, MACRO_DEF

### 7.4 Optimization Passes

**Constant Folding** (-O1):
- `2 + 3` → `5`
- `"a" + "b"` → `"ab"`
- `true and false` → `false`
- Constant condition elimination (dead branch removal for constant if-conditions)
- 64KB string concat limit, infinity/NaN guards

**Dead Code Elimination** (-O2):
- Removes unreachable code after `return`/`break`/`continue`
- Removes unused `let` bindings
- Removes uncalled `proc` definitions

**Function Inlining** (-O3):
- Inlines small non-recursive procs with single return statement
- Heuristics: small body, non-recursive

---

## 8. Execution Backends

Sage has 10 execution backends:

| Backend | Command | Description |
|---------|---------|-------------|
| **AST Interpreter** | `sage file.sage` | Tree-walking interpreter |
| **Bytecode VM** | `sage --runtime bytecode file.sage` | Stack-based virtual machine |
| **C Codegen** | `sage --compile file.sage -o bin` | Generates C, compiles with `cc -O2` |
| **LLVM IR** | `sage --compile-llvm file.sage -o bin` | LLVM IR + runtime library |
| **Native ASM** | `sage --emit-asm file.sage` | x86-64/aarch64/rv64/mips assembly |
| **JIT** | `sage --jit file.sage` | Profiling + type feedback + x86-64 native |
| **AOT** | `sage --aot file.sage -o bin` | Type-specialized ahead-of-time compilation |
| **JIT+AOT** | `sage --aot --jit file.sage -o bin` | Profile-guided AOT |
| **SageMetal** | `make metal-vm` | Freestanding VM for bare-metal |
| **Kotlin/Android** | `sage --emit-kotlin file.sage` | Kotlin transpilation |

### 8.1 Target Architectures (Native ASM)

- `x86-64` / `x86_64` (profiles: `-baremetal`, `-osdev`, `-uefi`)
- `aarch64` / `arm64`
- `rv64` / `riscv64`
- `mips` / `mips32` / `mips74k`

### 8.2 Special Compile Targets

- `--compile-pico`: RP2040/RP2350 (ARM/RISC-V via Pico SDK) → `.uf2`
- `--compile-bare`: Freestanding ELF with bare-metal runtime
- `--compile-uefi`: UEFI PE/COFF images

---

## 9. Memory Management

### 9.1 Three GC Modes

**Tracing GC** (default): Concurrent tri-color mark-sweep with SATB write barriers
- 4-phase: Root scan (STW, ~50-200μs) → Concurrent mark → Remark (STW, ~20-50μs) → Concurrent sweep
- Objects allocated during marking are born black
- Sub-millisecond STW pauses

**ARC Mode** (`--gc:arc` or `gc_set_arc()`): Deterministic Nim-style reference counting with cycle detection

**ORC Mode** (`--gc:orc` or `gc_set_orc()`): Optimized reference counting with Lins' trial deletion cycle collector

### 9.2 GC Control Functions

```sage
gc_collect()                    # Force collection
gc_enable() / gc_disable()     # Toggle GC
gc_stats() -> Dict             # Get stats (bytes_allocated, num_objects, collections, etc.)
gc_mode() -> String            # "tracing" / "arc" / "orc"
gc_set_arc() / gc_set_orc()   # Switch mode
```

### 9.3 Security Hardening

- Recursion depth limit: 1,000,000 (statements), inline for expressions (zero overhead)
- While loop limit: 1,000,000 iterations per loop
- Loop nesting limit: 1,024 levels
- String literal limit: 4,096 chars
- Identifier limit: 1,024 chars
- OOM-safe allocation (abort on OOM)
- Print depth limit for circular reference protection

---

## 10. Tools & Developer Experience

### 10.1 REPL

Start with `sage` (no args) or `sage --repl`.

| Command | Description |
|---------|-------------|
| `:help` | Print help |
| `:quit` / `:exit` / Ctrl-D | Exit |
| `:reset` | Reset session |
| `:clear` | Clear screen |
| `:history [n]` | Show history |
| `:vars [prefix]` | List bindings |
| `:type <expr>` | Show runtime type |
| `:ast <code>` | Show parsed AST |
| `:env` | Show scope chain |
| `:modules` | List loaded modules |
| `:emit-c <code>` | Show C backend output |
| `:emit-llvm <code>` | Show LLVM IR output |
| `:stats` | GC stats, stack depth |
| `:time <expr>` | Time expression |
| `:bench <n> <expr>` | Benchmark (min/avg/max) |
| `:load <file>` | Execute file in session |
| `:pwd` / `:cd <dir>` | Directory |
| `:gc` | Run GC + stats |
| `:runtime [mode]` | Show/switch runtime |

### 10.2 Formatter

```bash
sage fmt file.sage              # Format in place
sage fmt --check file.sage      # Check without modifying
```

### 10.3 Linter

```bash
sage lint file.sage             # Static analysis
```

Rules: E001-E003 (errors), W001-W005 (warnings), S001-S005 (style).

### 10.4 LSP Server

```bash
sage --lsp                      # Start LSP on stdin/stdout
sage-lsp                        # Standalone binary
```

Features: diagnostics, completion, hover (including docstrings), formatting.

### 10.5 Editor Support

- TextMate grammar: `editors/sage.tmLanguage.json`
- VSCode extension: `editors/vscode/`

### 10.6 Syntax Highlighting (TextMate)

Scopes:
- `keyword.control.sage` — if, else, while, for, return, break, continue
- `keyword.declaration.sage` — let, proc, class, struct, enum, trait
- `keyword.other.sage` — import, from, as, match, case, default, defer
- `keyword.operator.sage` — and, or, not, in
- `constant.language.sage` — true, false, nil
- `entity.name.function.sage` — function/proc names
- `entity.name.type.sage` — class/struct names
- `string.quoted.double.sage` — string literals
- `comment.line.number-sign.sage` — comments

---

## 11. Metaprogramming & Generics

### 11.1 Compile-Time Execution

```sage
# Compile-time block
comptime:
    let result = expensive_computation()
    # result is baked into the binary

# Compile-time expression
let x = comptime(factorial(10))
```

### 11.2 Pragmas / Decorators

```sage
@inline                # Suggest inlining
@packed                # Packed struct layout
@section(".text")     # Place in specific section
@align("16")          # Alignment requirement
@deprecated           # Mark as deprecated
@noreturn             # Function does not return
```

### 11.3 Generics (v3.7+)

```sage
proc identity[T](x: T) -> T:
    return x

struct Pair[A, B]:
    first: A
    second: B
```

Generics use monomorphization in compiled backends.

### 11.4 Macros (v3.7+)

```sage
macro name(params):
    quote:
        # Template with unquote() for substitutions
```

---

## 12. Concurrency

### 12.1 Threads

```sage
import thread
let t = thread.spawn(my_proc, args)
thread.join(t)
```

### 12.2 Async/Await

```sage
async proc compute(x):
    return x * x

let future = compute(42)
print await future              # 1764
```

### 12.3 Synchronization Primitives

**Native (C-level):**
```sage
import thread
let m = thread.mutex()
thread.lock(m)
# critical section
thread.unlock(m)
```

**From std library:**
```sage
import std.atomic               # atomic_new, load, store, add, cas, exchange
import std.channel              # Go-style buffered channels
import std.threadpool           # Task submission, parallel map
import std.rwlock               # Read-write locks
import std.condvar              # Condition variables, barriers
```

### 12.4 Atomics (C-level `__atomic` builtins)

```sage
atomic_new(init)
atomic_load(a)
atomic_store(a, v)
atomic_add(a, v)
atomic_cas(a, exp, des)
atomic_exchange(a, v)
```

### 12.5 POSIX Semaphores

```sage
sem_new(permits)
sem_wait(s)
sem_post(s)
sem_trywait(s)
```

---

## 13. FFI & Low-Level Programming

### 13.1 FFI — Calling C Libraries

```sage
let lib = ffi_open("libm.so")
let result = ffi_call(lib, "sqrt", 16.0)
ffi_close(lib)
```

Max 3 arguments to `ffi_call`.

### 13.2 Raw Memory

```sage
let ptr = mem_alloc(1024)       # Allocate 1024 bytes
mem_write(ptr, 0, 0xFF)        # Write byte at offset 0
let val = mem_read(ptr, 0)     # Read byte at offset 0
mem_free(ptr)                   # Free memory
print addressof(my_var)         # Get address of variable
```

### 13.3 Inline Assembly

```sage
asm_exec("mov rax, 42; ret")    # Execute assembly string directly
let code = asm_compile("mov rax, 42; ret")  # Compile to machine code
asm_arch()                       # Get architecture name
```

### 13.4 C Struct Interop

```sage
let Point = struct_def({"x": "f64", "y": "f64"})
let p = struct_new(Point, 3.0, 4.0)
print struct_get(p, "x")        # 3.0
struct_set(p, "y", 5.0)
```

### 13.5 Unsafe Blocks

```sage
unsafe:
    mem_write(ptr, 0, value)
```

---

## 14. CLI Reference

### 14.1 Running Sage

| Command | Description |
|---------|-------------|
| `sage` | Start REPL |
| `sage <file.sage> [args]` | Run file |
| `sage -c "source"` | Run source string |
| `sage --repl` | Start REPL |

### 14.2 Compilation & Codegen

| Command | Description |
|---------|-------------|
| `sage --emit-c <file> -o <path>` | Emit C source |
| `sage --compile <file> -o <bin>` | Compile via C to executable |
| `sage --emit-llvm <file>` | Emit LLVM IR |
| `sage --compile-llvm <file> -o <bin>` | Compile via LLVM |
| `sage --emit-asm <file> --target <arch>` | Emit assembly |
| `sage --compile-native <file> --target <arch>` | Compile native assembly |
| `sage --emit-vm <file>` | Emit bytecode |
| `sage --sgvm <file>` | Emit SGVM binary |
| `sage --emit-kotlin <file>` | Emit Kotlin/Android source |
| `sage --jit <file>` | Run with JIT |
| `sage --aot <file> -o <bin>` | Ahead-of-time compile |
| `sage --compile-pico <file>` | Compile for Raspberry Pi Pico |
| `sage --compile-bare <file>` | Freestanding ELF |
| `sage --compile-uefi <file>` | UEFI PE/COFF image |

### 14.3 Optimization Flags

| Flag | Effect |
|------|--------|
| `-O0` | No optimization |
| `-O1` | Constant folding + type checking |
| `-O2` | + Dead code elimination |
| `-O3` | + Function inlining |
| `-g` | Emit debug info |

### 14.4 Runtime Modes

```bash
sage --runtime ast <file>        # AST interpreter (default)
sage --runtime bytecode <file>   # Bytecode VM
```

### 14.5 GC Modes

```bash
sage --gc:arc <file>             # ARC reference counting
sage --gc:orc <file>             # ORC optimized ref counting
```

### 14.6 Tooling

| Command | Description |
|---------|-------------|
| `sage fmt <file>` | Format code |
| `sage fmt --check <file>` | Check formatting |
| `sage lint <file>` | Lint code |
| `sage check <file>` | Type check |
| `sage --lsp` | Start LSP server |

---

## Grammar (Formal)

The language grammar in informal form. The actual parser is recursive descent with lookahead.

```
program        = statement*
statement      = print_stmt | let_stmt | if_stmt | while_stmt | for_stmt
               | proc_stmt | return_stmt | break_stmt | continue_stmt
               | class_stmt | struct_stmt | enum_stmt | trait_stmt
               | match_stmt | defer_stmt | try_stmt | raise_stmt
               | yield_stmt | import_stmt | async_proc_stmt
               | comptime_stmt | macro_def_stmt
               | expression_stmt | block_stmt

block          = NEWLINE INDENT statement+ DEDENT

print_stmt     = "print" expression
let_stmt       = "let" IDENTIFIER (":" type_annotation)? "=" expression
if_stmt        = "if" expression ":" block ("else" ":" block)?
while_stmt     = "while" expression ":" block
for_stmt       = "for" IDENTIFIER "in" expression ":" block
proc_stmt      = "proc" IDENTIFIER "(" param_list ")" ("->" type_annotation)? ":" block
return_stmt    = "return" expression?
class_stmt     = "class" IDENTIFIER ("(" IDENTIFIER ")")? ":" block
struct_stmt    = "struct" IDENTIFIER ":" field_list
enum_stmt      = "enum" IDENTIFIER ":" variant_list
trait_stmt     = "trait" IDENTIFIER ":" method_list
match_stmt     = "match" expression ":" (case_clause)* (default_clause)?
defer_stmt     = "defer" statement
try_stmt       = "try" ":" block catch_clause* finally_clause?
raise_stmt     = "raise" expression
yield_stmt     = "yield" expression?
import_stmt    = "import" dotted_name ("as" IDENTIFIER)?
               | "from" dotted_name "import" IDENTIFIER ("," IDENTIFIER)*
async_proc_stmt = "async" proc_stmt

expression     = binary_op (all operators with precedence)
               | unary_op expression
               | primary

primary        = NUMBER | STRING | BOOL | NIL | IDENTIFIER
               | array_literal | dict_literal | tuple_literal
               | "(" expression ")"
               | primary "(" args ")"           # call
               | primary "[" expression "]"     # index
               | primary "[" expression ":" expression "]"  # slice
               | primary "." IDENTIFIER         # property get
               | primary "->" IDENTIFIER        # arrow (alias for .)
               | "await" expression
               | "super" "." IDENTIFIER "(" args ")"
               | "comptime" "(" expression ")"

type_annotation = IDENTIFIER ("[" type_annotation ("," type_annotation)* "]")? ("?")?
```

---

This document was generated from the SageLang repository at https://github.com/Night-Traders-Dev/SageLang. All features, keywords, types, and functions are verified against the actual source code (headers `token.h`, `ast.h`, `value.h`, `bytecode.h`, and implementations in `core/src/c/`).
