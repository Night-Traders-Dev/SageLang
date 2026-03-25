---
title: "The Sage Programming Language"
subtitle: "A Complete Guide to Systems Programming with Sage"
author: "SageLang Project"
date: "March 2026"
version: "v1.3.0"
documentclass: report
geometry: "margin=1in"
fontsize: 11pt
toc: true
toc-depth: 3
numbersections: true
highlight-style: tango
header-includes:
  - \usepackage{fancyhdr}
  - \pagestyle{fancy}
  - \fancyhead[L]{The Sage Programming Language}
  - \fancyhead[R]{\thepage}
  - \fancyfoot[C]{v1.3.0}
  - \usepackage{titling}
  - \pretitle{\begin{center}\Huge\bfseries}
  - \posttitle{\par\end{center}\vskip 0.5em}
  - \preauthor{\begin{center}\large}
  - \postauthor{\end{center}}
  - \predate{\begin{center}\large}
  - \postdate{\end{center}}
---

\newpage

# Introduction

Sage is a clean, indentation-based systems programming language built in C. It combines the readability of Python with the performance of compiled languages, offering multiple compilation backends (C, LLVM IR, and native assembly), a Vulkan/OpenGL graphics engine, machine learning libraries, Linux kernel development tools, and a self-hosted compiler written in Sage itself.

## Key Features

- **Python-like syntax** with indentation-based blocks
- **Multiple backends**: C codegen, LLVM IR, native x86-64/aarch64/rv64 assembly
- **Self-hosted compiler** written in Sage
- **Vulkan + OpenGL** graphics engine with PBR, shadows, bloom, deferred rendering
- **Machine learning** with backpropagation, TurboQuant, self-evolving models
- **Linux kernel development** libraries (syscalls, drivers, modules, cgroups, namespaces)
- **Bare-metal OS development** with Multiboot2, GDT, IDT, PMM, VMM
- **QEMU integration** for virtualized testing
- **269+ interpreter tests**, 1567+ self-hosted tests

## Quick Start

```bash
# Build from source
git clone https://github.com/Night-Traders-Dev/SageLang.git
cd SageLang
make

# Run a program
./sage hello.sage

# Interactive REPL
./sage
```

A minimal Sage program:

```python
print "Hello, World!"
```

\newpage

# Language Fundamentals

## Variables and Types

Sage supports `let` for variable declaration and `var` for mutable variables.

```python
# Immutable binding
let name = "Alice"
let age = 30
let pi = 3.14159
let active = true
let nothing = nil

# Mutable variable
var counter = 0
counter = counter + 1
```

### Built-in Types

| Type | Example | Description |
|------|---------|-------------|
| Number | `42`, `3.14` | Integer or floating-point |
| String | `"hello"` | UTF-8 text |
| Boolean | `true`, `false` | Logical values |
| Nil | `nil` | Absence of value |
| Array | `[1, 2, 3]` | Ordered collection |
| Dict | `{"a": 1}` | Key-value mapping |
| Tuple | `(1, "x")` | Immutable pair |

### Type Checking

```python
print type(42)        # "number"
print type("hello")   # "string"
print type(true)      # "bool"
print type(nil)       # "nil"
print type([1, 2])    # "array"
print type({"a": 1})  # "dict"
```

### Type Conversion

```python
print str(42)          # "42"
print tonumber("123")  # 123
print tonumber("3.14") # 3.14
print chr(65)          # "A"
print ord("A")         # 65
```

## Arithmetic

```python
print 5 + 2     # 7
print 5 - 2     # 3
print 5 * 2     # 10
print 5 / 2     # 2.5
print 5 % 2     # 1
print -5        # -5

# Operator precedence follows standard math rules
print 2 + 3 * 4       # 14 (not 20)
print (2 + 3) * 4     # 20
```

### Bitwise Operators

```python
print 5 & 3    # 1  (AND)
print 5 | 3    # 7  (OR)
print 5 ^ 3    # 6  (XOR)
print ~5       # -6 (NOT)
print 1 << 4   # 16 (left shift)
print 16 >> 2  # 4  (right shift)
```

## Comparison and Logic

```python
# Comparison
print 1 == 1     # true
print 1 != 2     # true
print 1 < 2      # true
print 2 > 1      # true
print 1 <= 1     # true
print 1 >= 1     # true

# Logical operators
print true and false   # false
print true or false    # true
print not true         # false
```

> **Important:** In Sage, `0` is **truthy**. Only `false` and `nil` are falsy.

## Strings

Sage strings do not support escape sequences. Use `chr()` for special characters.

```python
# Concatenation
let greeting = "Hello" + " " + "World"

# String functions
print len("hello")                    # 5
print upper("hello")                  # "HELLO"
print lower("HELLO")                  # "hello"
print strip("  hello  ")             # "hello"
print replace("hello", "l", "r")     # "herro"

# Split and join
let parts = split("a,b,c", ",")
print parts[0]                        # "a"
print join(parts, "-")                # "a-b-c"

# Character access
let s = "hello"
print s[0]                            # "h"
print s[4]                            # "o"

# Special characters via chr()
let newline = chr(10)
let tab = chr(9)
let quote = chr(34)

# String searching
print startswith("hello", "hel")      # true
print endswith("hello", "llo")        # true
print contains("hello world", "world") # true
print indexof("hello", "ll")          # 2
```

\newpage

# Control Flow

## If / Elif / Else

```python
let x = 42

if x > 100:
    print "big"
elif x > 10:
    print "medium"
else:
    print "small"
```

## While Loops

```python
var i = 0
while i < 5:
    print i
    i = i + 1
```

## For Loops

```python
# Iterate over arrays
let fruits = ["apple", "banana", "cherry"]
for fruit in fruits:
    print fruit

# Range-based for loop
for i in range(5):
    print i    # 0, 1, 2, 3, 4

# Range with start
for i in range(2, 5):
    print i    # 2, 3, 4
```

## Break and Continue

```python
# Break exits the loop
var i = 0
while true:
    if i == 5:
        break
    print i
    i = i + 1

# Continue skips to next iteration
for x in range(10):
    if x % 2 == 0:
        continue
    print x    # 1, 3, 5, 7, 9
```

## Match / Case

```python
let color = "red"
match color:
    case "red":
        print "Stop"
    case "yellow":
        print "Caution"
    case "green":
        print "Go"
```

\newpage

# Functions

## Basic Functions

```python
proc greet(name):
    print "Hello, " + name + "!"

greet("Alice")    # Hello, Alice!
```

## Return Values

```python
proc add(a, b):
    return a + b

let result = add(3, 4)
print result    # 7
```

## Recursion

```python
proc factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

print factorial(5)    # 120

proc fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

print fibonacci(10)   # 55
```

## Closures

Functions capture their lexical scope, enabling closures.

```python
proc make_adder(n):
    proc add(x):
        return x + n
    return add

let add5 = make_adder(5)
print add5(10)    # 15
print add5(20)    # 25
```

### Stateful Closures

```python
proc make_counter():
    var count = 0
    proc increment():
        count = count + 1
        return count
    return increment

let counter = make_counter()
print counter()    # 1
print counter()    # 2
print counter()    # 3
```

\newpage

# Data Structures

## Arrays

```python
let nums = [1, 2, 3, 4, 5]
print nums[0]          # 1
print len(nums)        # 5

# Push and pop
push(nums, 6)
print len(nums)        # 6
pop(nums)

# Slicing
let sub = slice(nums, 1, 3)
print sub              # [2, 3]

# Nested arrays
let matrix = [[1, 2], [3, 4], [5, 6]]
print matrix[1][0]     # 3

# Iteration
var total = 0
for n in nums:
    total = total + n
print total            # 15
```

## Dictionaries

```python
let person = {"name": "Alice", "age": 30}
print person["name"]       # "Alice"

# Check keys
print dict_has(person, "name")     # true
print dict_has(person, "email")    # false

# Get keys and values
let keys = dict_keys(person)
let vals = dict_values(person)

# Delete
dict_delete(person, "age")

# Build incrementally (no multiline literals)
let config = {}
config["host"] = "localhost"
config["port"] = 8080
config["ssl"] = true
```

## Tuples

```python
let point = (3, 7)
print point[0]    # 3
print point[1]    # 7
print len(point)  # 2
```

\newpage

# Object-Oriented Programming

## Classes

```python
class Person:
    proc init(self, name, age):
        self.name = name
        self.age = age

    proc greet(self):
        return "Hi, I'm " + self.name

let p = Person("Alice", 30)
print p.name       # Alice
print p.greet()    # Hi, I'm Alice
```

## Inheritance

```python
class Animal:
    proc init(self, name):
        self.name = name

    proc speak(self):
        return "..."

class Dog(Animal):
    proc init(self, name, breed):
        super.init(self, name)
        self.breed = breed

    proc speak(self):
        return "Woof!"

let d = Dog("Rex", "German Shepherd")
print d.name       # Rex
print d.breed      # German Shepherd
print d.speak()    # Woof!
```

## Arrow Operator

The `->` operator is an alias for `.`, allowing C-style member access.

```python
class Vec3:
    proc init(self, x, y, z):
        self->x = x
        self->y = y
        self->z = z

    proc length(self):
        return (self->x * self->x + self->y * self->y + self->z * self->z)

let v = Vec3(3, 4, 0)
print v->x          # 3
print v->length()   # 25
```

## Deep Inheritance with Super

```python
class A:
    proc init(self, x):
        self.x = x

class B(A):
    proc init(self, x, y):
        super.init(self, x)
        self.y = y

class C(B):
    proc init(self, x, y, z):
        super.init(self, x, y)
        self.z = z

let obj = C(1, 2, 3)
print obj.x    # 1
print obj.y    # 2
print obj.z    # 3
```

\newpage

# Exception Handling

```python
# Basic try/catch
try:
    let result = risky_operation()
catch e:
    print "Error: " + e

# Try/catch/finally
try:
    let f = open_file("data.txt")
    process(f)
catch e:
    print "Failed: " + e
finally:
    print "Cleanup complete"

# Raising exceptions
proc divide(a, b):
    if b == 0:
        raise "Division by zero"
    return a / b

try:
    print divide(10, 0)
catch e:
    print e    # Division by zero

# Nested exception handling
try:
    try:
        raise "inner error"
    catch e:
        print "Inner: " + e
    print "Outer continues"
catch e:
    print "Should not reach here"
```

\newpage

# Modules

## Importing Modules

```python
# Import entire module
import math
print math.abs(-42)

# Import specific items
from strings import pad_left
print pad_left("42", 5, "0")    # "00042"

# Import with alias
import arrays as arr
let doubled = arr.map([1, 2, 3], proc(x): return x * 2)
```

## Creating Modules

Any `.sage` file is a module. Export functions and variables at the top level.

```python
# mylib.sage
let VERSION = "1.0"

proc hello(name):
    return "Hello, " + name

proc add(a, b):
    return a + b
```

```python
# main.sage
import mylib
print mylib.VERSION        # 1.0
print mylib.hello("World") # Hello, World
```

\newpage

# Standard Library

## Arrays Module

```python
import arrays

let nums = [5, 3, 8, 1, 9, 2]

# Functional operations
let doubled = arrays.map(nums, proc(x): return x * 2)
let evens = arrays.filter(nums, proc(x): return x % 2 == 0)
let total = arrays.reduce(nums, 0, proc(acc, x): return acc + x)

# Search
print arrays.contains(nums, 8)      # true
print arrays.index_of(nums, 8)      # 2

# Transform
let rev = arrays.reverse(nums)
let combined = arrays.concat([1, 2], [3, 4])
```

## Strings Module

```python
import strings

let text = "  Hello, World!  "
print strings.compact(text)            # "Hello, World!"
print strings.pad_left("42", 5, "0")   # "00042"
print strings.pad_right("hi", 10, ".")  # "hi........"
print strings.repeat("ab", 3)          # "ababab"
print strings.surround("hello", "[", "]")  # "[hello]"
print strings.snake_case("HelloWorld")  # "hello_world"
print strings.dash_case("helloWorld")   # "hello-world"
print strings.csv(["a", "b", "c"])      # "a,b,c"
```

## Dicts Module

```python
import dicts

let config = {"host": "localhost", "port": 8080, "debug": false}

print dicts.size(config)                    # 3
print dicts.get_or(config, "timeout", 30)   # 30 (default)
print dicts.has_all(config, ["host", "port"]) # true

let entries = dicts.entries(config)
for e in entries:
    print str(e[0]) + " = " + str(e[1])

let subset = dicts.select_values(config, ["host", "port"], nil)
```

## Iterator Module

```python
import iter

# Infinite counter
for n in iter.count(0, 2):
    if n > 10:
        break
    print n    # 0, 2, 4, 6, 8, 10

# Enumeration
let fruits = ["apple", "banana", "cherry"]
for pair in iter.enumerate_array(fruits):
    print str(pair[0]) + ": " + pair[1]

# Take first N from generator
let first5 = iter.take(iter.count(0, 1), 5)
```

## Stats Module

```python
import stats

let scores = [85, 92, 78, 95, 88, 91, 76]

print stats.mean(scores)         # ~86.4
print stats.min_value(scores)    # 76
print stats.max_value(scores)    # 95
print stats.range_span(scores)   # 19
print stats.sum(scores)          # 605
```

## Math Module

```python
import math

print math.abs(-42)              # 42
print math.sign(-7)              # -1
print math.clamp(150, 0, 100)    # 100
print math.lerp(0, 100, 0.5)    # 50.0
print math.square(7)             # 49
print math.min(3, 7)             # 3
print math.max(3, 7)             # 7
```

## Assert Module

```python
import assert

let result = 2 + 2
assert.assert_equal(result, 4, "Basic addition")
assert.assert_true(result > 0, "Positive result")
assert.assert_not_nil(result, "Not nil")
assert.assert_close(3.14159, 3.14, 0.01, "Pi approximation")
```

## JSON Module

```python
import json

# Parse JSON string
let data = json.cJSON_Parse("{" + chr(34) + "name" + chr(34) + ": " + chr(34) + "Alice" + chr(34) + "}")
let name_item = json.cJSON_GetObjectItem(data, "name")
print json.cJSON_GetStringValue(name_item)    # Alice
json.cJSON_Delete(data)
```

\newpage

# GPU Programming

## Vulkan Graphics Engine

Sage includes a full Vulkan graphics engine with 27 SPIR-V shaders and 16 Sage libraries.

```python
import gpu

# Initialize GPU with a window
gpu.init(800, 600, "Sage Window")

# Create a triangle
let vertices = [
    -0.5, -0.5, 0.0,  1.0, 0.0, 0.0,
     0.5, -0.5, 0.0,  0.0, 1.0, 0.0,
     0.0,  0.5, 0.0,  0.0, 0.0, 1.0
]
let vbo = gpu.create_buffer(vertices, gpu.BUFFER_VERTEX)

# Load shaders
let vert = gpu.load_shader("triangle.vert.spv", gpu.SHADER_VERTEX)
let frag = gpu.load_shader("triangle.frag.spv", gpu.SHADER_FRAGMENT)
let pipeline = gpu.create_pipeline(vert, frag)

# Render loop
while not gpu.should_close():
    gpu.poll_events()
    gpu.begin_frame()
    gpu.cmd_bind_pipeline(pipeline)
    gpu.cmd_bind_vertex_buffer(vbo)
    gpu.cmd_draw(3, 1)
    gpu.end_frame()
    gpu.present()

gpu.cleanup()
```

### 3D Math Library

```python
import gpu.math3d as m3d

# Vectors
let pos = m3d.vec3(1.0, 2.0, 3.0)
let dir = m3d.normalize(m3d.vec3(1.0, 1.0, 0.0))
let dot = m3d.dot(pos, dir)

# Matrices
let proj = m3d.perspective(45.0, 800.0/600.0, 0.1, 100.0)
let view = m3d.look_at(
    m3d.vec3(0.0, 0.0, 5.0),    # eye
    m3d.vec3(0.0, 0.0, 0.0),    # target
    m3d.vec3(0.0, 1.0, 0.0)     # up
)
let model = m3d.mat4_identity()
let mvp = m3d.mat4_mul(proj, m3d.mat4_mul(view, model))
```

\newpage

# Machine Learning

## Training a Neural Network

Sage includes a complete ML pipeline with backpropagation, Adam optimizer, and cuBLAS GPU acceleration.

```python
import ml_native

# Load pre-trained weights
let W = ml_native.load_weights("models/weights/sl_tq_llm.weights")
let embed = W[1]
let qw = W[2]
let kw = W[3]
let vw = W[4]
let ow = W[5]

# Forward pass (real transformer inference)
let token_ids = [72, 101, 108, 108, 111]    # "Hello"
let logits = ml_native.forward_pass(
    embed, qw, kw, vw, ow,
    W[6], W[7], W[8], W[9], W[10], W[11], W[12],
    token_ids, 96, 384, 256, len(token_ids)
)
print "Logits: " + str(len(logits)) + " classes"
```

### C-Only Trainer

For maximum performance, Sage provides a C-only trainer with cuBLAS GPU support:

```bash
# Build the trainer
make train-c

# Train for 200K steps with Adam optimizer
./train_sl_tq 200000 0.0005

# Output: ~14 steps/sec on RTX 4060 with cuBLAS FP32
```

## TurboQuant Compression

```python
import llm.turboquant as tq

# Configure quantization
tq.set_seed(42)

# Build codebook for 3-bit quantization
let codebook = tq._build_codebook(3, 96)

# Create KV cache with compression
let cache = tq.create_kv_cache(64, 96, 3)
# 8.5x memory reduction with zero accuracy loss
```

## Self-Evolving Models

```python
import llm.evolve

# Start with a tiny seed model
let model = evolve.create_seed(64, 1)    # 98K params
let evo = evolve.create_evolver(model)

# Training loop with automatic growth
for step in range(100000):
    let loss = train_step(model)
    evolve.record_loss(evo, loss)
    if evolve.should_grow(evo):
        model = evolve.grow(evo)
        # Model grows: 98K -> 197K -> 400K -> 1M -> 2M -> 8M -> 67M
```

## AutoResearch

```python
import llm.autoresearch

# Create autonomous researcher
let researcher = autoresearch.create(
    {"lr": 0.001, "d_model": 96, "layers": 1},
    proc(cfg): return train_model(cfg),    # train function
    proc(cfg): return eval_model(cfg)      # eval function
)

# Run ratchet loop: propose -> train -> evaluate -> keep/discard
autoresearch.run(researcher, 50)
print autoresearch.summary(researcher)
```

## GPU Acceleration

```python
import ml.gpu_accel

# Auto-detect best hardware (GPU > NPU > CPU)
let ctx = gpu_accel.create("auto")

# Matrix multiplication on GPU
let result = gpu_accel.matmul(ctx, matrix_a, matrix_b, 256, 512, 256)

# Benchmark
print gpu_accel.stats(ctx)
gpu_accel.destroy(ctx)
```

\newpage

# Linux Kernel Development

## System Calls

```python
import os.linux.syscalls as sc

# Build a syscall descriptor
let write_call = sc.make_syscall(
    sc.ARCH_X86_64,
    sc.SYS_WRITE,
    [1, 0, 13]    # fd=stdout, buf, count
)
print write_call["instruction"]    # "syscall"
print write_call["nr_reg"]        # "rax"

# Generate inline assembly
let asm = sc.emit_syscall_asm_x64(sc.SYS_WRITE, 3)
# Output:
#     movq $1, %rax
#     syscall

# File operations
let flags = sc.O_WRONLY + sc.O_CREAT + sc.O_TRUNC    # 577
let mode = sc.S_IRUSR + sc.S_IWUSR                   # 384
```

## Kernel Drivers

```python
import os.linux.driver as drv

# Create a character device driver
let my_driver = drv.simple_char_driver(
    "sage_dev",
    "SageLang Team",
    "A Sage-generated character device"
)

# Add module parameters
drv.add_param(my_driver, "buffer_size", "int", 4096, "Buffer size")
drv.add_param(my_driver, "debug", "bool", false, "Debug mode")

# Set IRQ and I/O region
drv.set_irq(my_driver, 10)
drv.set_io_region(my_driver, 768, 8)

# Generate complete C source code
let c_code = drv.generate_driver_c(my_driver)

# Generate Kbuild Makefile
let kbuild = drv.generate_kbuild(my_driver)
```

## Kernel Modules

```python
import os.linux.kmodule as kmod

# Create a kernel module
let m = kmod.create_module("sage_hello")
kmod.mod_set_meta(m, "GPL", "John Doe", "Hello from Sage", "1.0.0")

# Add parameters
kmod.mod_add_param(m, "greeting", "string", "hello", "Greeting message")

# Add procfs entry
kmod.mod_add_procfs(m, "sage_info", "sage_info_show")

# Add init/exit code
kmod.mod_add_init_line(m, "pr_info(\"Sage module loaded!\\n\");")
kmod.mod_add_exit_line(m, "pr_info(\"Sage module unloaded!\\n\");")

# Generate outputs
let c_source = kmod.generate_module_c(m)
let dkms_conf = kmod.generate_dkms_conf(m)
let kbuild = kmod.generate_kbuild(m)
```

## Reading /proc

```python
import os.linux.procfs

# Read CPU information
let cpuinfo = procfs.read_cpuinfo()
print "CPU count: " + str(cpuinfo["count"])
for cpu in cpuinfo["processors"]:
    print cpu["modelname"]

# Read memory info
let meminfo = procfs.read_meminfo()
print "Total: " + meminfo["MemTotal"]
print "Free: " + meminfo["MemFree"]

# Read system load
let load = procfs.read_loadavg()
print "Load: " + load["load1"] + " " + load["load5"] + " " + load["load15"]

# Read uptime
let uptime = procfs.read_uptime()
print "Uptime: " + uptime["uptime"] + " seconds"
```

## Reading /sys

```python
import os.linux.sysfs

# Block device info
let sda = sysfs.get_block_device_info("sda")
print "Size: " + sda["size_sectors"] + " sectors"

# Network device info
let eth0 = sysfs.get_net_device_info("eth0")
print "MAC: " + eth0["address"]
print "State: " + eth0["operstate"]
print "MTU: " + eth0["mtu"]

# CPU frequency
let cpu0 = sysfs.get_cpu_info(0)
print "Governor: " + cpu0["governor"]
print "Freq: " + cpu0["freq_cur"] + " kHz"

# Thermal zones
let temp = sysfs.get_thermal_zone(0)
print "Temp: " + temp["temp"] + " millidegrees"

# Battery status
let bat = sysfs.get_power_supply_info("BAT0")
print "Capacity: " + bat["capacity"] + "%"
```

## Control Groups (cgroups v2)

```python
import os.linux.cgroups as cg

# Create a container-like cgroup
let container = cg.container_cgroup("web_app", 50, 512, 200)
# 50% CPU, 512MB RAM, max 200 processes

# Generate setup commands
let setup = cg.cg_emit_setup_commands(container)
print setup
# mkdir -p /sys/fs/cgroup/web_app
# echo "+cpu +memory +pids" > .../cgroup.subtree_control
# echo "50000 100000" > .../cpu.max
# echo "536870912" > .../memory.max
# echo "200" > .../pids.max

# Add a process
let add_cmd = cg.cg_emit_add_pid(container, 1234)
# echo 1234 > /sys/fs/cgroup/web_app/cgroup.procs
```

## Linux Namespaces

```python
import os.linux.namespace as ns

# Create a minimal container
let config = ns.minimal_container("sage-os", "/rootfs")
# Includes: mount, UTS, PID, IPC namespaces
# Auto-mounts: /proc, /tmp, /sys

# Add networking
config = ns.ns_add(config, ns.NS_NET)
config = ns.ns_set_net_veth(config, "veth_sage", "eth0", "10.0.0.2", "24")

# Generate unshare command
let cmd = ns.ns_emit_unshare_cmd(config)
# unshare --mount --uts --pid --fork --ipc --net

# Generate setup script
let script = ns.ns_emit_setup_script(config)
# Sets hostname, mounts filesystems, configures networking
```

## Netlink Sockets

```python
import os.linux.netlink as nl

# Build a "get all network interfaces" request
let msg = nl.build_getlink_request(1)

# Serialize to bytes
let bytes = nl.nlmsg_serialize(msg)

# Parse response header
let hdr = nl.nlmsg_parse_header(bytes, 0)
print "Type: " + str(hdr["type"])
print "Seq: " + str(hdr["seq"])

# Interface info
let eth = nl.interface_info("eth0", 65, 1500)
print eth["name"]       # eth0
print eth["up"]         # true
print eth["running"]    # true
print eth["mtu"]        # 1500
```

## Device Tree Overlays

```python
import os.linux.devicetree as dt

# Create a GPIO controller node
let gpio = dt.gpio_node("gpio0", 1048576, 32)

# Create an I2C sensor
let sensor = dt.i2c_device_node("bme280", 118, "bosch,bme280")

# Create an overlay
let overlay = dt.create_overlay("/soc", gpio)
let dts = dt.emit_overlay_dts([overlay])
# Outputs valid DTS source for dtc compilation
```

## Ioctl Commands

```python
import os.linux.ioctl

# Create an ioctl command set
let iset = ioctl.create_ioctl_set("S")
iset = ioctl.ioctl_add_read(iset, "SAGE_GET_VERSION", 4)
iset = ioctl.ioctl_add_write(iset, "SAGE_SET_CONFIG", 64)
iset = ioctl.ioctl_add_none(iset, "SAGE_RESET")

# Generate C header
let header = ioctl.emit_ioctl_header(iset)

# Generate ioctl handler
let handler = ioctl.emit_ioctl_handler(iset, "sage_dev")
```

## Epoll Event Loops

```python
import os.linux.epoll

# Create a TCP server event loop
let ev = epoll.tcp_server_loop("http_server", 5, 128)

# Generate C code for the event loop
let c_code = epoll.emit_event_loop_c(ev)
# Produces complete epoll_create1/epoll_wait loop with handlers
```

\newpage

# Bare-Metal OS Development

## Boot Process

Sage can compile directly to bare-metal ELF binaries using `--compile-bare`.

```python
import os.boot.multiboot as mb
import os.boot.gdt as gdt
import os.boot.start as start
import os.boot.linker as linker

# Generate Multiboot2 header
let header = mb.create_header()

# Generate GDT (Global Descriptor Table)
let gdt_table = gdt.build_gdt64()

# Generate x86_64 startup assembly
let asm = start.generate_startup()

# Generate linker script
let ld_config = linker.default_config()
let ld_script = linker.generate_script(ld_config)
```

## Kernel Console

```python
import os.kernel.console

# Initialize VGA text mode
console.init_vga()
console.set_color(console.LIGHT_GREEN, console.BLACK)
console.clear_screen(console.BLACK)

# Print text
console.print_line("SageOS v0.1.0 booting...")
console.print_str("Hello from the kernel!")

# Framebuffer mode
console.init_framebuffer(addr, 1920, 1080, 7680, 32)
console.fb_putpixel(100, 100, 0xFFFFFF)
console.fb_fill_rect(50, 50, 200, 100, 0xFF0000)
```

## Memory Management

```python
import os.kernel.pmm
import os.kernel.vmm

# Physical memory manager
pmm.init(memory_map)
let page = pmm.alloc_page()
pmm.free_page(page)

# Virtual memory manager
vmm.init()
vmm.map_page(virtual_addr, physical_addr, flags)
```

## Compiling and Running

```bash
# Compile to bare-metal ELF
./sage --compile-bare kernel.sage -o kernel.elf

# Run in QEMU
make qemu-bare

# Debug with GDB
make qemu-debug
# In another terminal:
gdb -ex 'target remote :1234' kernel.elf
```

\newpage

# QEMU Integration

## Virtual Machine Configuration

```python
import os.qemu

# Create a bare-metal VM
let vm = qemu.baremetal_x86("sage_kernel", "kernel.elf")
let cmd = qemu.vm_build_command(vm)
print cmd
# qemu-system-x86_64 -machine q35 -m 64M -display none
#   -serial stdio -no-reboot -kernel kernel.elf

# Create a Linux development VM
let dev = qemu.dev_vm("dev", "bzImage", "rootfs.qcow2", "/home/user/project")
let dev_cmd = qemu.vm_build_command(dev)
# Includes: KVM, 2 cores, 512MB, virtio disk, user networking,
#           9p host share, virtio-rng, virtio-serial

# ARM64 bare-metal
let arm = qemu.baremetal_arm64("arm_test", "kernel-arm64.elf")

# RISC-V bare-metal
let rv = qemu.baremetal_riscv("rv_test", "kernel-rv64.elf")

# Debug with GDB
let dbg = qemu.baremetal_x86("debug", "kernel.elf")
dbg = qemu.vm_debug(dbg, 1234)
let gdb_script = qemu.gdb_script("kernel.elf", 1234)
```

## Disk Image Management

```python
import os.qemu

# Create a 10GB qcow2 disk
let create_cmd = qemu.qemu_img_create("disk.qcow2", "qcow2", "10G")

# Convert raw to qcow2
let convert_cmd = qemu.qemu_img_convert("disk.raw", "raw", "disk.qcow2", "qcow2")

# Snapshots
let snap_cmd = qemu.qemu_img_snapshot_create("disk.qcow2", "clean_install")
let restore_cmd = qemu.qemu_img_snapshot_apply("disk.qcow2", "clean_install")
```

## Automated Kernel Testing

```python
import os.linux.qemu_run as qr

# Create a test runner for a kernel module
let runner = qr.quick_module_test(
    "/tmp/sage_dev.ko",
    "sage_dev",
    "/boot/vmlinuz"
)

# Add custom tests
runner = qr.runner_add_device_test(runner, "dev_exists", "/dev/sage_dev")
runner = qr.runner_add_procfs_test(runner, "proc_check", "/proc/sage_info", "loaded")

# Generate a complete test shell script
let test_script = qr.generate_test_script(runner)
# Creates initramfs, runs QEMU with timeout, checks results
```

\newpage

# Filesystem Libraries

## ext2/ext3/ext4

```python
import os.ext

# Create a filesystem image
let fs = ext.create_filesystem(1048576, ext.BLOCK_SIZE)

# Create a file
ext.create_file(fs, "/hello.txt", "Hello from Sage!")

# Create a directory
ext.create_directory(fs, "/docs")

# Read inode
let inode = ext.read_inode(fs, ext.ROOT_INODE)
print "Root inode type: " + str(inode["type"])
```

## Btrfs

```python
import os.btrfs

# Parse btrfs superblock
let sb = btrfs.parse_superblock(disk_data)
print "Label: " + sb["label"]
print "Generation: " + str(sb["generation"])

# CRC32C checksums
let checksum = btrfs.crc32c(data)
```

## FAT16/32

```python
import os.image.diskimg as disk

# Create a bootable FAT16 disk image
let img = disk.create_mbr_image(32 * 1024 * 1024)    # 32MB
disk.format_fat16(img, 2048, 65536)
disk.write_file_fat16(img, "KERNEL  BIN", kernel_data)
```

## ELF Parser

```python
import os.elf

# Parse an ELF binary
let elf_data = readfile("program.elf")
if elf.is_elf(elf_data):
    let header = elf.parse_header(elf_data)
    print "Class: " + str(header["class"])
    print "Entry: " + str(header["entry"])
```

\newpage

# Compilation Backends

## C Backend

```bash
# Emit C source
./sage --emit-c program.sage -o output.c

# Compile to binary via C
./sage --compile program.sage -o program
```

## LLVM Backend

```bash
# Emit LLVM IR
./sage --emit-llvm program.sage -o output.ll

# Compile to binary via LLVM
./sage --compile-llvm program.sage -o program
```

## Native Assembly Backend

```bash
# Emit assembly (x86-64, aarch64, or rv64)
./sage --emit-asm program.sage -o output.s --target x86-64

# Compile to native binary
./sage --compile-native program.sage -o program --target aarch64
```

## Bare-Metal and UEFI

```bash
# Bare-metal ELF (no libc)
./sage --compile-bare kernel.sage -o kernel.elf --target x86-64

# UEFI application
./sage --compile-uefi boot.sage -o boot.efi
```

## Optimization Levels

```bash
./sage -O0 program.sage    # No optimization
./sage -O1 program.sage    # Basic optimization
./sage -O2 program.sage    # Standard optimization (default)
./sage -O3 program.sage    # Aggressive optimization
./sage -g program.sage     # Debug info
```

\newpage

# Build System

## Makefile

```bash
make                 # Build sage interpreter
make test            # Run interpreter tests
make test-selfhost   # Run self-hosted tests
make test-all        # Run all tests

# Model training
make train-c         # Build C-only trainer
make chatbot-llvm    # Compile chatbot via LLVM
make sl-tq-chat      # Build generative chatbot

# QEMU
make qemu-bare       # Run kernel in QEMU (x86_64)
make qemu-bare-arm64 # Run kernel in QEMU (aarch64)
make qemu-debug      # Debug kernel with GDB

# Kernel
make kernel-bare     # Compile bare-metal kernel
make kernel-uefi     # Compile UEFI application
```

## SageMake

```bash
./sagemake build              # Auto-detect and build
./sagemake test               # Build and test
./sagemake install            # Install to /usr/local
./sagemake train 200000 0.001 # Train model
./sagemake chatbot --llvm     # Compile chatbot
./sagemake qemu x86_64        # Run in QEMU
./sagemake qemu-debug         # Debug with GDB
./sagemake evolve             # Self-evolving training
./sagemake info               # Show environment
./sagemake clean              # Clean artifacts
```

## Version

The version is stored in a single `VERSION` file at the repository root. All build systems (Makefile, CMakeLists.txt, build.sh, sagemake) read from this file automatically.

\newpage

# Tooling

## REPL

```bash
./sage
# or
./sage --repl
```

```
sage> 2 + 3
5
sage> let x = "hello"
sage> print upper(x)
HELLO
sage> :quit
```

## Formatter

```bash
./sage --fmt program.sage
```

## Linter

```bash
./sage --lint program.sage
```

## Language Server (LSP)

```bash
./sage --lsp
# or
./sage-lsp
```

The LSP server provides autocompletion, diagnostics, hover info, and go-to-definition for VS Code and other editors.

\newpage

# Language Gotchas

1. **0 is truthy** -- Only `false` and `nil` are falsy. Use explicit comparisons: `if x == 0:` not `if not x:`

2. **No escape sequences** -- Use `chr(10)` for newline, `chr(9)` for tab, `chr(34)` for double-quote

3. **No hex literals** -- `0xFF` is parsed as `0` followed by variable `xFF`. Use decimal: `255`

4. **elif chains with 5+ branches malfunction** -- Use sequential `if`/`continue` instead

5. **Instance equality always returns false** -- Compare fields structurally

6. **No wildcard imports** -- Use `import module` then `module.func()`, not `from module import *`

7. **No multiline dict/array literals** -- Build incrementally with assignments

8. **Class methods can't see module-level `let` vars** -- Pass as arguments or hardcode

9. **`%` operator casts to int** -- `3.7 % 1` returns `0`, not `0.7`

10. **`chr(0)` truncates strings** -- Null bytes terminate C strings in the interpreter

11. **`push()` in C interpreter, `append()` in self-hosted** -- Use `push()` for interpreter scripts

12. **`super` requires explicit `self`** -- Write `super.init(self, args)` not `super.init(args)`

13. **`init` is a reserved keyword** -- But works as a property name after `.` and `->`

\newpage

# Appendix A: Built-in Functions

| Function | Description |
|----------|-------------|
| `print(value)` | Print to stdout |
| `input(prompt)` | Read line from stdin |
| `len(x)` | Length of string, array, dict, or tuple |
| `type(x)` | Type name as string |
| `str(x)` | Convert to string |
| `tonumber(s)` | Parse string to number |
| `chr(n)` | Integer to character |
| `ord(c)` | Character to integer |
| `push(arr, val)` | Append to array |
| `pop(arr)` | Remove last element |
| `range(n)` | Array [0, 1, ..., n-1] |
| `range(a, b)` | Array [a, a+1, ..., b-1] |
| `slice(arr, start, end)` | Sub-array |
| `split(str, delim)` | Split string by delimiter |
| `join(arr, delim)` | Join array with delimiter |
| `replace(str, old, new)` | Replace substring |
| `upper(str)` | Uppercase |
| `lower(str)` | Lowercase |
| `strip(str)` | Trim whitespace |
| `startswith(str, prefix)` | Check prefix |
| `endswith(str, suffix)` | Check suffix |
| `contains(str, sub)` | Check substring |
| `indexof(str, sub)` | Find substring index |
| `dict_keys(d)` | Array of keys |
| `dict_values(d)` | Array of values |
| `dict_has(d, key)` | Check key exists |
| `dict_delete(d, key)` | Remove key |
| `clock()` | Current time in seconds |
| `readfile(path)` | Read file contents |
| `writefile(path, data)` | Write file |
| `gc_disable()` | Disable garbage collector |

\newpage

# Appendix B: CLI Reference

```
Usage: sage [options] [file.sage]

Options:
  (no args)            Interactive REPL
  file.sage            Run script

Compilation:
  --emit-c file -o f   Emit C source
  --compile file -o f  Compile via C backend
  --emit-llvm file     Emit LLVM IR
  --compile-llvm file  Compile via LLVM
  --emit-asm file      Emit assembly
  --compile-native f   Compile to native binary
  --compile-bare f     Bare-metal ELF (no libc)
  --compile-uefi f     UEFI PE application
  --target ARCH        x86-64, aarch64, rv64

Optimization:
  -O0 to -O3           Optimization level
  -g                   Debug info

Tooling:
  --fmt file           Format source
  --lint file          Lint source
  --lsp                Start LSP server
  --repl               Interactive REPL
```
