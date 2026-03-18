# SageLang Updates

## March 18, 2026 - Phase 15: Vulkan Graphics Library + Self-Hosted Ports

### GPU Graphics Library (Phase 15)

The Sage GPU graphics library provides professional-grade Vulkan compute and graphics capabilities through a 3-layer architecture: a C native module (`import gpu`), ergonomic Sage builders (`lib/vulkan.sage`), and high-level helpers (`lib/gpu.sage`).

#### C Native Module (`src/c/graphics.c`, ~2600 lines)

- **Handle-table design**: All Vulkan objects stored internally, exposed to Sage via integer handles
- **Conditional compilation**: `SAGE_HAS_VULKAN` auto-detected via pkg-config (or `VULKAN=1`); compiles as stubs without Vulkan SDK
- **Context lifecycle**: Instance creation with validation layers, physical device selection (prefers discrete GPU), queue family detection (dedicated compute/transfer)
- **Buffers**: Create/destroy, upload/download float arrays, auto-map host-visible memory
- **Images**: 1D/2D/3D with auto image view creation, 13 formats (RGBA8, RGBA16F, RGBA32F, R32F, depth, etc.)
- **Samplers**: Nearest/linear filter, repeat/clamp/mirror address modes
- **Shaders**: SPIR-V file loading
- **Descriptors**: Layout from dict arrays, pool allocation, buffer/image/sampler binding
- **Compute pipelines**: Shader + layout creation, cmd_dispatch
- **Graphics pipelines**: Full config dict (vertex input, rasterization state, blend, depth test, topology)
- **Render passes & framebuffers**: Attachment config with auto depth detection
- **Commands**: Pool/buffer creation, recording, bind/dispatch/draw, barriers, copy operations
- **Synchronization**: Fences (signaled/unsignaled), semaphores, wait/reset
- **Submission**: Graphics queue and dedicated compute queue support
- **Constants**: 100+ Vulkan enum constants (buffer usage, memory properties, formats, shader stages, topology, blend factors, pipeline stages, access flags, layouts, etc.)

#### Sage-Level Libraries

- **`lib/vulkan.sage`**: Builder-pattern API
  - String-based resource creation: `buffer("storage")`, `shader("compute.spv", "compute")`
  - Descriptor helpers: `binding_desc()`, `bind_buffer()`, `bind_storage_image()`
  - One-liner compute pipeline creation: `compute_pipeline_simple()`
  - Barrier helpers: `compute_barrier()`, `compute_to_host()`, `image_to_general()`
- **`lib/gpu.sage`**: High-level helpers
  - `run_compute(shader, input, output_size, wg_x, wg_y, wg_z)` — fire-and-forget GPU compute
  - `create_ping_pong()` / `ping_pong_swap()` — double-buffered compute management
  - `print_info()` — formatted device capabilities output

### New Self-Hosted Ports

Three additional C modules ported to Sage:

| C Source | Sage Port | Tests |
|----------|-----------|-------|
| `diagnostic.c` (213 lines) | `diagnostic.sage` — Token display names, Rust/Elm-style diagnostic formatting | 53 |
| `gc.c` (738 lines) | `gc.sage` — GC stats/control API, threshold computation | 45 |
| `heartbeat.c` (210 lines) | `heartbeat.sage` — Cooperative heartbeat system, health check aggregator | 44 |

### Professional Rendering Features (same day expansion)

#### C Native Additions (~2000 lines)
- **Input handling**: `key_pressed`, `key_just_pressed`, `key_just_released`, `mouse_pos`, `mouse_button`, `scroll_delta`, `set_cursor_mode`, 27 GLFW key/mouse constants
- **Swapchain recreation**: `recreate_swapchain()` for window resize handling
- **Uniform buffers**: `create_uniform_buffer`, `update_uniform` (persistent mapped write)
- **Offscreen rendering**: `create_offscreen_target` (color + depth, auto render pass + framebuffer)
- **Texture loading**: `load_texture` via stb_image (PNG/JPG/BMP/TGA), staging buffer copy, layout transitions
- **Mipmaps**: `generate_mipmaps` (blit chain), `create_sampler_advanced` (anisotropy, mip LOD)
- **Indirect draw/dispatch**: `cmd_draw_indirect`, `cmd_draw_indexed_indirect`, `cmd_dispatch_indirect`
- **3D textures**: `create_image_3d` with VK_IMAGE_VIEW_TYPE_3D
- **Cubemaps**: `create_cubemap` (6-layer cube-compatible image)
- **Multi-vertex binding**: `cmd_bind_vertex_buffers` (up to 8 bindings for instanced data)
- **MRT render pass**: `create_render_pass_mrt` (multiple color attachments for deferred G-buffer)
- **Byte upload**: `upload_bytes` for raw binary data (glTF buffers)
- **Shader hot-reload**: `reload_shader` (destroy old, load new SPIR-V)
- **Screenshot**: `screenshot` (readback swapchain to pixel array)

#### New Sage Libraries (16 files, ~2300 lines)
- `math3d.sage`: vec2/3/4, mat4 (column-major), perspective/ortho, look_at, orbit/FPS camera
- `mesh.sage`: procedural cube/plane/sphere, OBJ loading, GPU upload, vertex descriptors
- `renderer.sage`: high-level frame loop (depth buffer + render pass + per-frame sync)
- `postprocess.sage`: HDR render targets, bloom chain (4 levels), tone mapping (ACES/Reinhard)
- `pbr.sage`: Cook-Torrance metallic-roughness materials, lights, IBL context, 8 presets
- `shadows.sage`: shadow maps, depth-only passes, cascade shadow maps (4 cascades)
- `deferred.sage`: G-buffer (4 MRT: position/normal/albedo/emission), SSAO (32 samples), SSR (64-step)
- `gltf.sage`: glTF 2.0 JSON loading, mesh/material/scene extraction
- `taa.sage`: Halton jitter sequence, history/velocity buffers, temporal blend
- `scene.sage`: scene graph (node hierarchy, transforms, traversal, find_by_name)
- `material.sage`: shader+texture+descriptor binding, presets (unlit/textured/PBR)
- `asset_cache.sage`: shader/texture/mesh dedup caching
- `frame_graph.sage`: pass dependency ordering (topological sort), resource tracking
- `debug_ui.sage`: FPS tracking, frame timing, custom values, toggle overlay

#### GLSL Shaders (27 SPIR-V modules)
- PBR: Cook-Torrance BRDF (GGX NDF + Smith geometry + Schlick Fresnel)
- Bloom: brightness extract, 5-tap Gaussian blur, ACES/Reinhard tonemapping composite
- Shadows: depth-only pass from light perspective
- Skybox: cubemap sampling with depth=1.0 (always behind scene)
- N-body: compute shader with shared-memory tiling (65K+ bodies)
- Stars: SSBO-driven instanced point sprites with temperature coloring
- Nebula: FBM 3D noise volumetric compute shader
- Planet: ray-sphere intersection, noise terrain, biome coloring, atmosphere rim glow

#### Demos (6 GPU examples)
- `gpu_window.sage`: empty window with cycling clear color
- `gpu_triangle.sage`: classic RGB triangle via SPIR-V shaders
- `gpu_hello3d.sage`: rotating 3D "HELLO WORLD" line text with push constants
- `gpu_cube.sage`: spinning textured cube with depth buffer and perspective camera
- `gpu_phong.sage`: multi-object Phong-lit scene with orbit camera
- `gpu_particles.sage`: 65536 GPU compute particles with ping-pong SSBOs

### Build & Test

- `VULKAN` Make variable: `auto` (default, pkg-config detection), `1` (force), `0` (disable)
- GLFW auto-detected for windowed mode
- `-lvulkan -lglfw` added to LDFLAGS when detected
- stb_image.h vendored into include/ for texture loading
- 27 SPIR-V shader modules pre-compiled in examples/shaders/
- **1567+ self-hosted tests passing** (285 GPU tests across 3 test suites)
- All existing tests unaffected

## March 17, 2026 - LLVM Backend: Runtime Library & Compile-to-Executable

The LLVM backend now produces fully working executables via `--compile-llvm`. A new standalone C runtime library implements all sage_rt_* functions, and numerous backend fixes bring LLVM IR generation to parity with the C backend for core language features.

### New: Runtime Library (src/c/llvm_runtime.c)

- Standalone C runtime implementing all 40+ `sage_rt_*` functions used by LLVM-generated IR
- Value constructors: `sage_rt_number`, `sage_rt_string`, `sage_rt_bool`, `sage_rt_nil`, `sage_rt_array`, `sage_rt_dict`, `sage_rt_tuple`
- Arithmetic: `sage_rt_add`, `sage_rt_sub`, `sage_rt_mul`, `sage_rt_div`, `sage_rt_mod`, `sage_rt_neg`
- Comparison: `sage_rt_eq`, `sage_rt_neq`, `sage_rt_lt`, `sage_rt_le`, `sage_rt_gt`, `sage_rt_ge`
- Logical: `sage_rt_and`, `sage_rt_or`, `sage_rt_not`
- Bitwise: `sage_rt_band`, `sage_rt_bor`, `sage_rt_bxor`, `sage_rt_bnot`, `sage_rt_shl`, `sage_rt_shr`
- Collections: array push/index/len, dict set/get, tuple index, range, slice
- Property access, conversion (tonumber, tostring), I/O (print, input)

### LLVM Backend Fixes (src/c/llvm_backend.c)

- **ABI fix**: `%SageValue = type { i32, i64 }` now matches clang's SysV x86-64 lowering, eliminating struct-return ABI mismatches
- **Variable assignments**: `EXPR_SET(NULL, name, value)` now emits a store instruction instead of calling `set_attr` on nil
- **Global/local distinction**: Variables correctly resolve to `@name` (global) or `%name` (local) depending on scope
- **Local variable allocation**: New `collect_local_names()` pass pre-allocates all `let` bindings with `alloca` at function entry, preventing use-before-definition in control flow
- **Block termination tracking**: `block_terminated` flag prevents invalid IR after `ret`/`br` instructions
- **Bitwise operators**: `&`, `|`, `^`, `~`, `<<`, `>>` now emit proper runtime calls
- **Class support**: Methods emitted as `sage_fn_ClassName_methodName` functions
- **Exception handling**: `try` executes the try block; `raise` prints the message and aborts
- **Import**: Silently skipped (not applicable in compiled mode)
- **Linker integration**: `--compile-llvm` auto-discovers `obj/llvm_runtime.o` for linking

### Build & Test

- New Makefile target builds `obj/llvm_runtime.o` as part of `make`
- New Test 22b: LLVM compile + run validates end-to-end executable generation
- All 1425+ tests passing

## March 16, 2026 - Interpreter Safety Hardening (Fuzz-Driven)

Addressed crash vectors discovered by fuzz testing. All changes are backward-compatible and all existing tests continue to pass (144 interpreter + 28 compiler + 1168 self-hosted).

### String Literal Length Limit

- Lexer now enforces `MAX_STRING_LENGTH 4096` — string literals exceeding this limit produce a parse-time error instead of a potential buffer overflow (SIGSEGV on strings > ~500 chars).

### Loop Iteration Guard

- `while` loops are now capped at `MAX_LOOP_ITERATIONS 1000000` iterations. Exceeding the limit throws a catchable exception (`"While loop exceeded maximum iterations"`) instead of hanging or exhausting the C stack.

### Null Function Pointer Guards

- Both `VAL_FUNCTION` and `VAL_NATIVE` call paths now check for null function pointers before dispatch. A null callee produces a runtime error and returns `nil` instead of crashing.

### Type-Safe Accessor Macros

- New macros in `value.h`: `SAGE_AS_STRING(v)`, `SAGE_AS_NUMBER(v)`, `SAGE_AS_BOOL(v)` — return safe defaults (`""`, `0.0`, `0`) when the value type doesn't match, preventing undefined behavior from incorrect `args[].as.string` access on non-string values.
- Existing `AS_*` macros remain unchanged for callers that validate types with `IS_*` first.

### Files Changed

- `include/value.h` — Added `SAGE_AS_STRING`, `SAGE_AS_NUMBER`, `SAGE_AS_BOOL`
- `src/c/lexer.c` — Added `MAX_STRING_LENGTH` check in `string()`
- `src/c/interpreter.c` — Added `MAX_LOOP_ITERATIONS`, null guards on function dispatch

---

## March 10, 2026 - Documentation Refresh, CLI Reference, and REPL Commands

### Documentation Refresh

- `README.md` now includes an implementation-derived build parameter reference for both Make and CMake
- `README.md` now includes a full `sage` CLI parameter reference covering every top-level mode and backend-specific flag handled in `src/c/main.c`
- `documentation/SageLang_Guide.md` now mirrors the current build surface, CLI surface, and REPL command set from source instead of older draft wording

### REPL Improvements

- Added new interactive REPL commands in `src/c/main.c`:
  - `:vars [prefix]` - list current bindings, optionally filtered by prefix
  - `:type <expr>` - evaluate an expression and print its runtime type and value
  - `:load <file>` - execute a Sage file in the current REPL session
  - `:reset` - recreate the REPL environment and module cache
  - `:pwd` / `:cd <dir>` - inspect or change the working directory
  - `:gc` - run garbage collection and print GC statistics
- Expanded `:help` output so the runtime help now matches the available REPL commands
- Updated `sage --help` text so `--emit-asm` and `--compile-native` advertise the `-g` flag accepted by the implementation

---

## March 9, 2026 - Networking Modules & cJSON Port

### Networking Modules (src/net.c, ~850 lines)

Four new native modules for network programming, backed by libcurl and OpenSSL:

#### `socket` Module (15 functions + constants)

Low-level POSIX socket operations:
- `socket.create(family, type, proto)` — Create a socket
- `socket.bind(sock, host, port)` / `socket.listen(sock, backlog)` / `socket.accept(sock)`
- `socket.connect(sock, host, port)` / `socket.send(sock, data)` / `socket.recv(sock, size)`
- `socket.sendto(sock, data, host, port)` / `socket.recvfrom(sock, size)` — UDP
- `socket.close(sock)` / `socket.setopt(sock, level, name, val)` / `socket.poll(sock, timeout_ms)`
- `socket.resolve(hostname)` / `socket.getpeername(sock)` / `socket.nonblock(sock, enable)`
- Constants: `AF_INET`, `AF_INET6`, `SOCK_STREAM`, `SOCK_DGRAM`, `SOCK_RAW`, `IPPROTO_TCP`, `IPPROTO_UDP`

#### `tcp` Module (9 functions)

High-level TCP with automatic buffering:
- `tcp.connect(host, port)` / `tcp.listen(host, port, backlog)`
- `tcp.accept(server)` / `tcp.send(sock, data)` / `tcp.recv(sock, size)`
- `tcp.sendall(sock, data)` / `tcp.recvall(sock, size)` / `tcp.recvline(sock)`
- `tcp.close(sock)`

#### `http` Module (9 functions)

HTTP/HTTPS client via libcurl:
- `http.get(url, opts?)` / `http.post(url, body, opts?)` / `http.put(url, body, opts?)`
- `http.delete(url, opts?)` / `http.patch(url, body, opts?)` / `http.head(url, opts?)`
- `http.download(url, path, opts?)` / `http.escape(str)` / `http.unescape(str)`
- All request functions return `{status, body, headers}` dicts
- Options dict: `timeout`, `follow`, `verify`, `user_agent`, `headers`, `cainfo`

#### `ssl` Module (13 functions)

OpenSSL TLS/SSL bindings:
- `ssl.context(method?)` / `ssl.load_cert(ctx, cert, key)` / `ssl.wrap(ctx, sock)`
- `ssl.connect(ssl)` / `ssl.accept(ssl)` / `ssl.send(ssl, data)` / `ssl.recv(ssl, size)`
- `ssl.shutdown(ssl)` / `ssl.free(ssl)` / `ssl.free_context(ctx)`
- `ssl.error(ssl, ret)` / `ssl.peer_cert(ssl)` / `ssl.set_verify(ctx, mode)`

### cJSON Port (lib/json.sage, ~1,050 lines)

Complete 1:1 port of Dave Gamble's [cJSON](https://github.com/DaveGamble/cJSON) library, exposing the same API:

- **Parsing**: `cJSON_Parse`, `cJSON_ParseWithLength`, `cJSON_GetErrorPtr`
- **Printing**: `cJSON_Print` (formatted), `cJSON_PrintUnformatted` (compact), `cJSON_PrintBuffered`
- **Creation** (13 functions): `cJSON_CreateNull/True/False/Bool/Number/String/Raw/Array/Object`, `CreateIntArray/DoubleArray/FloatArray/StringArray`
- **Query** (7): `cJSON_GetArraySize`, `GetArrayItem`, `GetObjectItem` (case-insensitive), `GetObjectItemCaseSensitive`, `HasObjectItem`, `GetStringValue`, `GetNumberValue`
- **Type checks** (10): `cJSON_IsInvalid/False/True/Bool/Null/Number/String/Array/Object/Raw`
- **Array modification** (5): `AddItemToArray`, `InsertItemInArray`, `DetachItemFromArray`, `DeleteItemFromArray`, `ReplaceItemInArray`
- **Object modification** (8): `AddItemToObject/CS`, `DetachItemFromObject/CaseSensitive`, `DeleteItemFromObject/CaseSensitive`, `ReplaceItemInObject/CaseSensitive`
- **Helpers** (9): `cJSON_AddNullToObject`, `AddTrueToObject`, `AddFalseToObject`, `AddBoolToObject`, `AddNumberToObject`, `AddStringToObject`, `AddRawToObject`, `AddArrayToObject`, `AddObjectToObject`
- **Utility** (7): `cJSON_Duplicate`, `Compare`, `Minify`, `Delete`, `SetValuestring`, `SetNumberHelper`, `Version`
- **Sage extras** (2): `cJSON_ToSage` (tree→native dict/array), `cJSON_FromSage` (native→tree)

### Build System Changes

- `Makefile`: Added `-lcurl -lssl -lcrypto` to LDFLAGS, `net.c` to CORE_SOURCES
- `CMakeLists.txt`: Added PkgConfig for libcurl and openssl, all targets link `${CURL_LIBRARIES} ${OPENSSL_LIBRARIES}`

### Test Suite

- 88 new JSON tests (`tests/test_json.sage`) covering parse, print, create, query, type checks, array/object manipulation, duplicate, compare, minify, roundtrip, escape sequences, nested structures, case sensitivity, and Sage conversion
- All existing C and self-hosted test coverage maintained

### Interpreter Bugs Discovered

- **Instance `==` always returns false** — Sage class instances cannot be compared by reference with `==`. Workaround: compare by structural position (e.g., `item.prev == nil` to detect first child).
- **elif chains with 5+ branches malfunction** — The 4th+ branch in a long elif chain inside a class method can produce incorrect results. Workaround: extract to a helper function with early returns.

---

## March 9, 2026 - Build System: CMake and Make Support for Self-Hosted Builds

The build system now supports building SageLang in two modes: from C sources (default) and self-hosted (Sage-on-Sage). Both Make and CMake are supported.

### Makefile Targets

- `make` - Build `sage` from C (default, unchanged)
- `make sage-boot FILE=<file>` - Run a `.sage` file through the self-hosted Sage interpreter
- `make test-selfhost` - Run the full self-hosted suite (lexer, parser, interpreter, bootstrap, tooling, passes, stdlib, compiler, LSP, CLI)
- `make test-selfhost-lexer` / `test-selfhost-parser` / `test-selfhost-interpreter` / `test-selfhost-bootstrap` - Individual core suites
- `make test-all` - Run ALL tests (C + self-hosted)
- `make cmake-sage` - Setup CMake self-hosted build
- `make cmake-sage-build` - Build and run self-hosted tests via CMake

### CMakeLists.txt Options

- Default (no flags) - Builds `sage` and `sage-lsp` from C
- `-DBUILD_SAGE=ON` - Self-hosted mode: builds `sage` and provides targets:
  - `sage_boot` - Run files via bootstrap (needs `SAGE_FILE=path`)
  - `test_selfhost` - Run all self-hosted tests
  - `test_selfhost_lexer`, `test_selfhost_parser`, `test_selfhost_interpreter`, `test_selfhost_bootstrap` - Individual suites
- `-DBUILD_PICO=ON` - Pico embedded build (unchanged)
- `-DENABLE_DEBUG=ON` - Debug symbols
- `-DENABLE_TESTS=ON` - C test executables
- Version updated to 0.13.0

### Key Details

- The self-hosted build first compiles the C host interpreter, then uses it to run the Sage bootstrap
- `BUILD_SAGE` and the default desktop CMake path are mutually exclusive modes, but both produce a `sage` executable
- Self-hosted tests are in `src/sage/` directory: `test_lexer.sage`, `test_parser.sage`, `test_interpreter.sage`, `test_bootstrap.sage`

---

## March 9, 2026 - Phase 13 Complete: Self-Hosting

Phase 13 delivers a self-hosted Sage interpreter written entirely in SageLang. The lexer, parser, and interpreter have been ported from C to Sage, enabling Sage to run Sage programs through its own pipeline.

### Self-Hosted Components

- **Lexer** (`src/sage/lexer.sage`, ~300 lines) - Indentation-aware tokenizer with dict-based keyword lookup
- **Parser** (`src/sage/parser.sage`, ~700 lines) - Recursive descent parser with 12 precedence levels
- **Interpreter** (`src/sage/interpreter.sage`, ~920 lines) - Tree-walking evaluator with dict-based value representation
- **Token definitions** (`src/sage/token.sage`) - Token type constants
- **AST definitions** (`src/sage/ast.sage`) - Dict-based AST node constructors
- **Bootstrap entry** (`src/sage/sage.sage`) - Runs target `.sage` files through the self-hosted interpreter

### New Native Builtins (7)

- **`type()`** - Returns value type as string
- **`chr()`** - Number to character conversion
- **`ord()`** - Character to number conversion
- **`startswith()`** - String prefix check
- **`endswith()`** - String suffix check
- **`contains()`** - Substring search
- **`indexof()`** - Find substring position

### Bootstrap Coverage

- Arithmetic, variables, if/else, while, for loops
- Functions, recursion, closures, nested functions
- Classes, inheritance, method dispatch
- Arrays, dicts, strings, string builtins
- Try/catch, break/continue, boolean ops
- GC must be disabled for self-hosted code (`gc_disable()`)

### Notable Fix

- **Truthiness bug** - 0 is truthy in Sage; must use `true`/`false` for booleans

### Running the Self-Hosted Interpreter

```bash
cd src/sage && ../../sage sage.sage <file.sage>
```

### Test Suites

- `test_lexer.sage` - 12/12 tests passing
- `test_parser.sage` - 130/130 tests passing
- `test_interpreter.sage` - 18/18 tests passing
- `test_bootstrap.sage` - 18/18 tests passing
- All existing tests maintained: 112 interpreter tests + 28 compiler tests

---

## March 9, 2026 - Phase 12 Complete: Tooling Ecosystem

Phase 12 delivers a complete developer tooling ecosystem for SageLang: an interactive REPL, code formatter, linter, syntax highlighting, and a Language Server Protocol (LSP) server.

### REPL (Read-Eval-Print Loop)

- **`sage` (no args) or `sage --repl`** - Launches interactive REPL
- **Multi-line block support** - Automatic continuation for indented blocks (if/while/proc/class)
- **Error recovery** - Parse and runtime errors displayed without exiting the session
- **Built-in commands** - `:help`, `:quit`, `:exit`, `:vars`, `:type`, `:load`, `:reset`, `:pwd`, `:cd`, `:gc`

### Code Formatter

- **`sage fmt <file>`** - Format a Sage source file in place
- **`sage fmt --check <file>`** - Check formatting without modifying the file (exit code 1 if changes needed)
- Normalizes indentation, spacing, and blank lines for consistent style

### Linter

- **`sage lint <file>`** - Static analysis with 13 rules across three categories
- **Error rules (E001-E003)** - Syntax and structural errors
- **Warning rules (W001-W005)** - Potential bugs and bad practices
- **Style rules (S001-S005)** - Code style and naming conventions
- Reports file, line, rule code, and message for each finding

### Syntax Highlighting

- **TextMate grammar** - `editors/sage.tmLanguage.json` for any TextMate-compatible editor
- **VSCode extension** - `editors/vscode/` with language configuration and theme support

### Language Server Protocol (LSP)

- **`sage --lsp`** - LSP server mode integrated into the main `sage` binary
- **`sage-lsp` standalone binary** - Dedicated LSP server for editor integration
- **Diagnostics** - Real-time error and warning reporting on save
- **Completion** - Keyword and symbol completions
- **Hover** - Type information and documentation on hover
- **Formatting** - Format-on-save via `textDocument/formatting`

### Files Modified/Created

- `src/main.c` - REPL implementation, CLI dispatch, and REPL command handling
- `src/formatter.c` - Code formatter with in-place and check modes
- `src/linter.c` - Linter with 13 rules (errors, warnings, style)
- `src/lsp.c` - LSP server (diagnostics, completion, hover, formatting)
- `include/repl.h`, `include/formatter.h`, `include/linter.h`, `include/lsp.h` - Headers
- `src/main.c` - CLI dispatch for `--repl`, `fmt`, `lint`, `--lsp`
- `editors/sage.tmLanguage.json` - TextMate grammar for syntax highlighting
- `editors/vscode/` - VSCode extension (package.json, language configuration)

### Test Suite

- 4 new compiler tests (Tests 25-28): REPL, formatter, linter, LSP
- Total: 112 interpreter tests across 28 categories + 28 compiler tests, all passing

---

## March 9, 2026 - Phase 11 Complete: Concurrency & Parallelism

Phase 11 brings threading, async/await, native standard library modules, and expanded compiler backends.

### Native Standard Library Modules

- **`math` module** - `sqrt`, `sin`, `cos`, `tan`, `floor`, `ceil`, `abs`, `pow`, `log`, `pi`, `e`
- **`io` module** - `readfile`, `writefile`, `appendfile`, `exists`, `remove`, `rename`
- **`string` module** - `char`, `ord`, `startswith`, `endswith`, `contains`, `repeat`, `reverse`
- **`sys` module** - `args`, `exit`, `platform`, `version`, `env`, `setenv`
- Native module infrastructure: `create_native_module()` pre-loads modules into cache before file resolution

### Thread Module

- **`thread.spawn(proc, args...)`** - Spawn a new thread running a procedure with pre-evaluated arguments
- **`thread.join(t)`** - Wait for thread completion and return its result
- **`thread.mutex()`** - Create a mutex for synchronization
- **`thread.lock(m)` / `thread.unlock(m)`** - Lock and unlock mutexes
- **`thread.sleep(ms)`** - Sleep for milliseconds
- **`thread.id()`** - Get current thread identifier
- **GC thread safety** - Garbage collector protected with pthread mutex

### Async/Await

- **`async proc` syntax** - Declares an asynchronous procedure (sets `is_async` flag on FunctionValue)
- **`await` expression** - Joins async thread and retrieves the return value
- Calling an async proc automatically spawns a background thread via `thread_spawn_native`
- New AST nodes: `STMT_ASYNC_PROC`, `EXPR_AWAIT`
- Lexer: `async` and `await` keywords
- All compiler passes updated: pass.c, constfold.c, dce.c, inline.c, typecheck.c

### LLVM Backend Expansion

- Dictionary literals, tuple literals, slice expressions
- Property access (`EXPR_GET`) and property assignment (`EXPR_SET`)
- `for...in` loops using `sage_rt_array_len` + counter + `sage_rt_index`
- `break` and `continue` with loop label stack (`loop_cond_labels[]`, `loop_end_labels[]`, `loop_depth`)
- 11 new runtime function declarations (dict, tuple, slice, get/set, array_len, range)

### Native Codegen Expansion

- `for...in` loops using `VINST_CALL_BUILTIN("len")` + counter + `VINST_INDEX`
- `break` and `continue` with loop label stack in `ISelContext`
- Updated `STMT_WHILE` to push/pop loop labels

### Files Modified

- `src/stdlib.c` - Thread module functions, native module infrastructure
- `src/module.c` - `register_stdlib_modules()`, `create_native_module()`
- `include/module.h` - Thread module declaration
- `include/token.h` - `TOKEN_ASYNC`, `TOKEN_AWAIT`
- `include/ast.h` - `AwaitExpr`, `EXPR_AWAIT`, `STMT_ASYNC_PROC`
- `src/ast.c` - Constructors and free functions for new nodes
- `src/lexer.c` - `async`/`await` keyword recognition
- `src/parser.c` - `async_proc_declaration()`, `await` in `unary()`
- `include/value.h` - `is_async` field on FunctionValue
- `src/value.c` - Initialize `is_async = 0`
- `src/interpreter.c` - Async proc execution, await joining, thread spawning
- `src/llvm_backend.c` - Loop labels, dict/tuple/slice/get/set/for-in/break/continue
- `include/codegen.h` - Loop label stack in ISelContext
- `src/codegen.c` - For-in loops, break/continue with loop labels
- `src/pass.c`, `src/constfold.c`, `src/dce.c`, `src/inline.c`, `src/typecheck.c`, `src/compiler.c` - New node handling

### Test Suite

- 4 new tests in `tests/27_threads/`: basic spawn, thread args, mutex, thread ID
- 3 new tests in `tests/28_async/`: basic async, async args, async parallel
- 5 new tests in `tests/26_stdlib/`: math, io, string, sys modules
- Total: 112 interpreter tests across 28 categories + 24 compiler tests, all passing

---

## March 9, 2026 - Phase 10 Complete: Compiler Development

Full compiler pipeline with three backends: C codegen, LLVM IR, and native assembly.

- C backend: complete coverage of all language features (classes, modules, exceptions, builtins)
- LLVM IR backend: `--emit-llvm` / `--compile-llvm` with runtime declarations
- Native assembly backend: `--emit-asm` / `--compile-native` for x86-64, aarch64, rv64
- Optimization passes: type checking (`-O1+`), constant folding (`-O1+`), dead code elimination (`-O2+`), function inlining (`-O3`)
- Debug information: `-g` flag
- 24 compiler tests, all passing

---

## March 8, 2026 - Phase 9 Complete: Low-Level Programming

Phase 9 is now complete with all 5 sub-features implemented.

### Phase 9.5: C Struct Interop

- **`struct_def(fields)`**: Define C struct layout from `["name", "type"]` pairs with proper alignment
- **`struct_new(def)`**: Allocate zeroed struct instance
- **`struct_get(ptr, def, field)`** / **`struct_set(ptr, def, field, val)`**: Read/write fields
- **`struct_size(def)`**: Get total struct size (including padding)
- Types: `"char"`, `"byte"`, `"short"`, `"int"`, `"long"`, `"float"`, `"double"`, `"ptr"`
- Proper C ABI alignment: each field aligned to natural boundary, tail padding to max alignment
- 4 new tests in `tests/25_structs/`
- Total: 100 tests across 25 categories, all passing

---

## March 8, 2026 - Phase 9.4: Inline Assembly (Multi-Architecture)

SageLang can now compile and execute raw assembly code, with support for x86-64, aarch64, and RISC-V 64 architectures.

### Assembly Functions

- **`asm_exec(code, ret_type, ...args)`**: Compile and execute assembly on the host architecture. Return types: `"int"`, `"double"`, `"void"`. Up to 4 numeric arguments passed via ABI registers.
- **`asm_compile(code, arch, output_path)`**: Cross-compile assembly to an object file. Architectures: `"x86_64"`, `"aarch64"`, `"rv64"`.
- **`asm_arch()`**: Returns the host architecture name (e.g., `"x86_64"`)

### Implementation Details

- Assembly is compiled via temp files: `.s` → `as` → `.o` → `gcc -shared` → `.so` → `dlopen`/`dlsym`
- Escape sequences `\n` and `\t` processed in code strings (since SageLang strings are raw)
- Cross-compilation uses `aarch64-linux-gnu-as` / `riscv64-linux-gnu-as` toolchains
- System V ABI calling convention: integer args in rdi/rsi/rdx/rcx (x86-64), x0-x3 (aarch64), a0-a3 (rv64)
- Double args passed via xmm0-3 (x86-64), d0-3 (aarch64), fa0-3 (rv64)
- Temp files cleaned up after execution

### Files Modified

- `src/interpreter.c` — `asm_exec`, `asm_compile`, `asm_arch` native functions with multi-arch support

### Test Suite

- 5 new tests in `tests/24_assembly/`: basic ops, arguments, doubles, arch detection, cross-compilation
- Total: 96 tests across 24 categories, all passing

---

## March 8, 2026 - Phase 9.3: Raw Memory Operations

SageLang now supports direct memory allocation, reading, and writing for low-level programming.

### Memory Functions

- **`mem_alloc(size)`**: Allocate zero-initialized raw memory (up to 64MB), returns a pointer value
- **`mem_free(ptr)`**: Free allocated memory and invalidate the pointer
- **`mem_read(ptr, offset, type)`**: Read a value at ptr+offset. Types: `"byte"`, `"int"`, `"double"`, `"string"`
- **`mem_write(ptr, offset, type, val)`**: Write a value at ptr+offset. Types: `"byte"`, `"int"`, `"double"`
- **`mem_size(ptr)`**: Get the size of an allocation
- **`addressof(val)`**: Get the memory address of any value (as a number)

### Implementation Details

- New `VAL_POINTER` value type with `PointerValue` struct tracking raw pointer, size, and ownership
- Bounds checking prevents reads/writes past the end of owned allocations
- Memory is zero-initialized via `calloc` for safety
- Allocation capped at 64MB to prevent abuse
- `mem_free` invalidates the pointer (sets to NULL) to prevent use-after-free

### Files Modified

- `include/value.h` — `PointerValue` struct, `VAL_POINTER` enum, macros, constructor
- `src/value.c` — `val_pointer()` constructor, print/equality support
- `src/interpreter.c` — 6 memory native functions registered in `init_stdlib()`

### Test Suite

- 5 new tests in `tests/23_memory/`: alloc/free, byte ops, int/double ops, addressof, byte buffer
- Total: 91 tests across 23 categories, all passing

---

## March 8, 2026 - Phase 9.2: Foreign Function Interface (FFI)

SageLang can now call functions in shared C libraries via `dlopen`/`dlsym`.

### FFI Functions

- **`ffi_open(path)`**: Open a shared library (`.so`/`.dylib`/`.dll`), returns a library handle
- **`ffi_call(lib, func, ret_type, ...args)`**: Call a function in the library. `ret_type` is `"double"`, `"int"`, `"long"`, `"string"`, or `"void"`
- **`ffi_sym(lib, name)`**: Check if a symbol exists in the library (returns `true`/`false`)
- **`ffi_close(lib)`**: Close the library handle

### Implementation Details

- New `VAL_CLIB` value type wraps `dlopen` handle and library name
- `ffi_call` supports 0–3 arguments, with numeric and string argument types
- Uses `#pragma GCC diagnostic` to safely cast `void*` to function pointers (POSIX-guaranteed)
- Added `-ldl` to linker flags

### Files Modified

- `include/value.h` — `CLibValue` struct, `VAL_CLIB` enum, macros, constructor
- `src/value.c` — `val_clib()` constructor, print/equality support
- `src/interpreter.c` — 4 FFI native functions registered in `init_stdlib()`
- `Makefile` — `-ldl` added to `LDFLAGS`

### Test Suite

- 3 new tests in `tests/22_ffi/`: math library calls, libc string functions, symbol checking
- Total: 86 tests across 22 categories, all passing

---

## March 8, 2026 - Phase 9: Bitwise Operators (First Low-Level Feature)

The first feature of Phase 9 (Low-Level Programming): full bitwise operator support.

### Bitwise Operators

- **`&` (AND)**: Integer bitwise AND — `5 & 3` → `1`
- **`|` (OR)**: Integer bitwise OR — `5 | 3` → `7`
- **`^` (XOR)**: Integer bitwise XOR — `5 ^ 3` → `6`
- **`~` (NOT)**: Integer bitwise complement — `~0` → `-1`
- **`<<` (Left Shift)**: Shift bits left — `1 << 4` → `16`
- **`>>` (Right Shift)**: Shift bits right — `16 >> 2` → `4`

### Implementation Details

- Operators work on integer values (doubles truncated to `long long` for bitwise ops)
- Correct C-style operator precedence: `~` (unary) → `<<`/`>>` → `&` → `^` → `|` → `and`/`or`
- Unary `~` handled at same precedence level as unary `-` and `not`

### Files Modified

- `include/token.h` — New tokens: `TOKEN_AMP`, `TOKEN_PIPE`, `TOKEN_CARET`, `TOKEN_TILDE`, `TOKEN_LSHIFT`, `TOKEN_RSHIFT`
- `src/lexer.c` — Lex `&`, `|`, `^`, `~`, `<<`, `>>`; updated `<`/`>` to check for shift first
- `src/parser.c` — New precedence levels: `shift()`, `bitwise_and()`, `bitwise_xor()`, `bitwise_or()`; unary `~` in `unary()`
- `src/interpreter.c` — Evaluate all 6 bitwise operators in `eval_binary()`

### Test Suite

- 6 new tests in `tests/21_bitwise/`: AND, OR, XOR, NOT, shifts, combined operations
- Total: 83 tests across 21 categories, all passing

---

## March 8, 2026 - Phase 8.5: Security & Performance Hardening

A comprehensive audit and hardening pass across the entire interpreter codebase, plus completion of the Phase 8 module system.

### Security Fixes

- **Recursion depth limits**: Interpreter capped at 1000 frames, parser at 500 nesting levels. Exceeding limits raises a clean exception instead of crashing.
- **OOM safety**: All `malloc`/`realloc` calls replaced with `SAGE_ALLOC`/`SAGE_REALLOC` wrappers that abort with a diagnostic message on failure. No code path can dereference a NULL allocation.
- **GC pinning**: New `gc_pin()`/`gc_unpin()` API prevents garbage collection during multi-step allocations (e.g., `instance_create`, `class_create`), fixing a class of use-after-free bugs.
- **Module path traversal**: Module names are validated to reject `/`, `\`, and `..`. Resolved paths are checked with `realpath()` to ensure they stay within search directories.
- **Iterative lexer**: `scan_token()` converted from recursive to iterative, eliminating potential stack overflow on files with many consecutive blank lines or comments.

### Performance Improvements

- **Hash table dictionaries**: Dictionaries rewritten from O(n) linear scan to O(1) amortized hash table using FNV-1a hashing, open-addressing with linear probing, 75% load factor growth, and backward-shift deletion.
- **O(n) string operations**: `string_join()` and `string_replace()` rewritten with write-pointer approach, replacing O(n^2) repeated `strcat`/`memmove`.
- **`size_t` string lengths**: String length calculations use `size_t` instead of `int` to prevent overflow on large strings.
- **Environment GC integration**: Environments now participate in mark-and-sweep GC via an `int marked` flag on `Env`, replacing the O(n^2) `MarkedEnv` linked list with O(1) mark checks. Unreachable environments are freed during GC sweep instead of only at shutdown.

### Module System (Phase 8 Completion)

- All three import forms fully working: `import mod`, `import mod as alias`, `from mod import x, y`
- `from mod import x as alias` supported
- Module attribute access via dot notation (`mod.value`, `mod.func()`)
- Circular dependency detection via `is_loading` flag
- Module caching prevents redundant loads

### Test Suite

- New `tests/` directory with 77 automated tests across 20 categories
- Bash test runner (`tests/run_tests.sh`) with `# EXPECT:` and `# EXPECT_ERROR:` patterns
- Categories: variables, arithmetic, comparison, logical, strings, control flow, loops, functions, arrays, dicts, tuples, classes, inheritance, exceptions, generators, modules, closures, builtins, edge cases, GC
- All 77 tests passing

### Files Modified

- `include/gc.h` - Safe allocation macros, pin API
- `include/value.h` - DictEntry hash field for hash table
- `include/env.h` - `int marked` flag, `env_sweep_unmarked()`, `env_clear_marks()`
- `src/gc.c` - Pin support, dict hash table iteration, env sweep integration, O(1) env marking
- `src/value.c` - Hash table dict ops, GC pinning in allocators, O(n) string ops, size_t lengths
- `src/interpreter.c` - Recursion depth counter, safe allocations, size_t string concat
- `src/parser.c` - Parser depth counter, safe allocations
- `src/lexer.c` - Iterative scan_token loop
- `src/module.c` - Path validation, realpath containment, safe allocations
- `src/env.c` - Marked flag init, sweep/clear functions, safe allocations
- `src/main.c` - ftell error check, safe allocations

---

## December 28, 2025 - Phase 8: Module System (60%)

- Added function closure support to FunctionValue struct
- Module infrastructure: parsing, loading, caching
- Search path system for module resolution

## November 29, 2025 - Phase 7: Advanced Control Flow (100%)

- Generators with yield/next fully working
- Exception handling: try/catch/finally/raise
- Loop control: for-in, break, continue

## November 28, 2025 - Phase 6: Object-Oriented Programming (100%)

- Classes with init, methods, self binding
- Single inheritance with method overriding
- Property access and assignment

## November 27, 2025 - Phase 5: Advanced Data Structures (100%)

- Arrays, dictionaries, tuples
- Array slicing, string methods
- 20+ native functions added

## November 27, 2025 - Phase 4: Garbage Collection (100%)

- Mark-and-sweep GC with configurable threshold
- gc_collect(), gc_stats(), gc_enable(), gc_disable()
