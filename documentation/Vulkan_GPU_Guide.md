# SageLang Vulkan/GPU Guide

A comprehensive guide to the SageLang GPU graphics engine — from opening a window to building universe simulations.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Getting Started](#getting-started)
3. [Core Concepts](#core-concepts)
4. [Windowing & Input](#windowing--input)
5. [Buffers & Memory](#buffers--memory)
6. [Images & Textures](#images--textures)
7. [Shaders & Pipelines](#shaders--pipelines)
8. [Render Passes & Framebuffers](#render-passes--framebuffers)
9. [Command Recording](#command-recording)
10. [Synchronization & Submission](#synchronization--submission)
11. [Descriptors & Uniforms](#descriptors--uniforms)
12. [3D Math Library](#3d-math-library)
13. [Meshes & Geometry](#meshes--geometry)
14. [Interactive Camera](#interactive-camera)
15. [High-Level Renderer](#high-level-renderer)
16. [PBR Materials](#pbr-materials)
17. [Post-Processing (HDR, Bloom, Tone Mapping)](#post-processing)
18. [Shadows](#shadows)
19. [Deferred Rendering & Screen-Space Effects](#deferred-rendering)
20. [Compute Shaders](#compute-shaders)
21. [Advanced Features](#advanced-features)
22. [Engine Libraries Reference](#engine-libraries-reference)
23. [Demo Catalog](#demo-catalog)
24. [Troubleshooting](#troubleshooting)
25. [API Reference](#api-reference)
26. [OpenGL 4.5 Backend](#opengl-45-backend)
27. [UI Widget Library](#ui-widget-library)

---

## Architecture Overview

The GPU engine has five layers, with three execution paths:

```text
Layer 5:  Sage Demos (examples/gpu_*.sage)
            |
Layer 4:  Engine Libraries (lib/renderer.sage, lib/scene.sage, lib/pbr.sage, ...)
            |
Layer 3:  Builder Libraries (lib/vulkan.sage, lib/opengl.sage, lib/math3d.sage, ...)
            |
Layer 2:  Execution Path (one of three):
            |-- Interpreter:  src/c/graphics.c (Value-based wrappers)
            |-- LLVM Compiled: src/c/llvm_runtime.c -> sage_rt_gpu_* -> sgpu_*
            |-- Bytecode VM:   src/vm/vm.c -> BC_OP_GPU_* -> sgpu_*
            |
Layer 1:  Pure C GPU API (include/gpu_api.h, src/c/gpu_api.c)
            |
          Vulkan SDK / OpenGL 4.5 + GLFW
```

**Layer 1 (C GPU API)**: Backend-agnostic pure C API (`sgpu_*` functions) with ~100 functions. No interpreter dependency (no Value types). Supports Vulkan and OpenGL backends via `SAGE_HAS_VULKAN`/`SAGE_HAS_OPENGL` compile flags.

**Layer 2 (Execution Paths)**:

- **Interpreter path**: `graphics.c` (~5700 lines) wraps `sgpu_*` with Value-based argument extraction. Used when running `sage game.sage`.
- **LLVM compiled path**: `llvm_runtime.c` provides 103 `sage_rt_gpu_*` bridge functions. Used when compiling with `sage --compile-llvm game.sage`.
- **Bytecode VM path**: 30 dedicated `BC_OP_GPU_*` opcodes call `sgpu_*` directly. Used for frame-loop hot paths in the VM runtime.

**Layer 3 (Sage builders)**: String-based helpers that wrap the verbose `gpu.*` calls. `vulkan.buffer("storage")` instead of `gpu.create_buffer(1024, gpu.BUFFER_STORAGE, gpu.MEMORY_DEVICE_LOCAL)`. Also includes `opengl.sage` as a drop-in backend replacement.

**Layer 4 (Engine)**: Application-level systems — scene graph, materials, PBR, shadows, post-processing, deferred rendering, TAA.

**Layer 5 (Demos)**: Complete examples from "hello triangle" to N-body galaxy simulations.

### Build Requirements

```bash
# Auto-detect Vulkan + GLFW + OpenGL (default)
make

# Force enable/disable
make VULKAN=1    # Force Vulkan
make VULKAN=0    # Disable Vulkan (stub mode)
make OPENGL=1    # Force OpenGL
make OPENGL=0    # Disable OpenGL

# Compile shaders
make shaders     # Compiles all .vert/.frag/.comp to .spv

# Compile a game to native executable with GPU support
sage --compile-llvm game.sage -o game
```

Without Vulkan SDK: the `gpu` module loads in stub mode — all constants are available, functions return error values gracefully.

Without GLFW: headless compute works, windowed rendering is disabled (`gpu.has_window` is `false`).

### OpenGL Backend

To use OpenGL instead of Vulkan, use `lib/opengl.sage`:

```sage
import opengl

# Initializes with OpenGL 4.5 core profile instead of Vulkan
opengl.init_windowed("My App", 800, 600)

# Rest of the API is identical to gpu module
print opengl.device_name()
let buf = opengl.create_buffer(1024, gpu.BUFFER_VERTEX, gpu.MEMORY_HOST_VISIBLE)
# ...
opengl.shutdown_windowed()
```

For GLSL shaders (OpenGL path), use `gpu.load_shader_glsl(source, stage)` instead of `gpu.load_shader(path, stage)` which loads SPIR-V.

### LLVM-Compiled GPU Programs

Games compiled via `--compile-llvm` get native-speed GPU access:

```bash
# Compile a game to a standalone executable
sage --compile-llvm my_game.sage -o my_game

# The executable links against Vulkan/GLFW/OpenGL automatically
./my_game
```

The LLVM backend resolves GPU constants at compile time and emits direct calls to `sage_rt_gpu_*` functions, which are linked from `obj/gpu_api.o`.

---

## Getting Started

### Minimal Window

```sage
import gpu

gpu.init_windowed("My App", 800, 600, "Window Title", false)
print gpu.device_name()

# Create render pass
let attach = {}
attach["format"] = gpu.FORMAT_SWAPCHAIN
attach["load_op"] = gpu.LOAD_CLEAR
attach["store_op"] = gpu.STORE_STORE
attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
attach["final_layout"] = gpu.LAYOUT_PRESENT
let rp = gpu.create_render_pass([attach])
let fbs = gpu.create_swapchain_framebuffers(rp)

# Sync objects
let cmd_pool = gpu.create_command_pool()
let cmd = gpu.create_command_buffer(cmd_pool)
let img_sem = gpu.create_semaphore()
let rdr_sem = gpu.create_semaphore()
let fence = gpu.create_fence(true)

# Render loop
while gpu.window_should_close() == false:
    gpu.poll_events()
    gpu.wait_fence(fence)
    gpu.reset_fence(fence)

    let idx = gpu.acquire_next_image(img_sem)
    if idx >= 0:
        gpu.begin_commands(cmd)
        gpu.cmd_begin_render_pass(cmd, rp, fbs[idx], [[0.1, 0.2, 0.3, 1.0]])
        gpu.cmd_end_render_pass(cmd)
        gpu.end_commands(cmd)
        gpu.submit_with_sync(cmd, img_sem, rdr_sem, fence)
        gpu.present(idx, rdr_sem)

gpu.device_wait_idle()
gpu.shutdown_windowed()
```

### Using the High-Level Renderer

For most applications, use `lib/renderer.sage` which handles all boilerplate:

```sage
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, aspect_ratio

let r = create_renderer(1024, 768, "My Scene")

let frame = begin_frame(r)
while frame != nil:
    let cmd = frame["cmd"]
    let t = frame["time"]

    # Your draw calls here
    # gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
    # gpu.cmd_draw(cmd, 3, 1, 0, 0)

    end_frame(r, frame)
    frame = begin_frame(r)

shutdown_renderer(r)
```

The renderer automatically creates: depth buffer, render pass (color + depth), swapchain framebuffers, command pool/buffers, per-frame sync (2 frames in flight), viewport/scissor setup.

---

## Core Concepts

### Handle System

Every GPU resource is represented by an integer handle. Invalid handles are `-1` (`gpu.INVALID_HANDLE`).

```sage
let buf = gpu.create_buffer(1024, gpu.BUFFER_STORAGE, gpu.MEMORY_DEVICE_LOCAL)
if buf < 0:
    print "failed!"
# ... use buf ...
gpu.destroy_buffer(buf)
```

### Constants

All Vulkan enums are exposed as module-level constants with bitwise OR composition:

```sage
# Buffer usage (combine with |)
let usage = gpu.BUFFER_STORAGE | gpu.BUFFER_TRANSFER_DST

# Memory properties
let mem = gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT

# Image formats
gpu.FORMAT_RGBA8        # 8-bit RGBA
gpu.FORMAT_RGBA16F      # 16-bit float RGBA (HDR)
gpu.FORMAT_RGBA32F      # 32-bit float RGBA
gpu.FORMAT_DEPTH32F     # 32-bit float depth
gpu.FORMAT_SWAPCHAIN    # Auto-resolves to actual swapchain format

# Shader stages
gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT    # Both stages
gpu.STAGE_COMPUTE                         # Compute only
gpu.STAGE_ALL                             # All stages
```

---

## Windowing & Input

### Window Management

```sage
gpu.init_windowed(app_name, width, height, title, validation?)  # Create window + Vulkan
gpu.window_should_close()     # Check close button
gpu.poll_events()             # Process OS events
gpu.set_title(new_title)      # Update window title
gpu.window_size()             # Returns {width, height}
gpu.swapchain_extent()        # Returns {width, height}
gpu.recreate_swapchain()      # Rebuild after resize
gpu.window_resized()          # Check and clear resize flag
gpu.shutdown_windowed()       # Destroy everything
```

### Keyboard Input

```sage
gpu.update_input()                   # Call once per frame
gpu.key_pressed(gpu.KEY_W)           # Held down?
gpu.key_just_pressed(gpu.KEY_SPACE)  # First frame pressed?
gpu.key_just_released(gpu.KEY_E)     # First frame released?
```

Key constants: `KEY_W`, `KEY_A`, `KEY_S`, `KEY_D`, `KEY_Q`, `KEY_E`, `KEY_R`, `KEY_F`, `KEY_SPACE`, `KEY_ESCAPE`, `KEY_ENTER`, `KEY_TAB`, `KEY_SHIFT`, `KEY_CTRL`, `KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT`, `KEY_1` through `KEY_5`.

### Mouse Input

```sage
gpu.mouse_pos()                     # Returns {x, y} in pixels
gpu.mouse_button(gpu.MOUSE_LEFT)    # Button held?
gpu.scroll_delta()                   # Returns {x, y}, consumed on read
gpu.set_cursor_mode(gpu.CURSOR_DISABLED)  # Capture mouse for FPS camera
```

Cursor modes: `CURSOR_NORMAL` (0), `CURSOR_HIDDEN` (1), `CURSOR_DISABLED` (2, captured for FPS look).

### Time

```sage
gpu.get_time()    # GLFW high-resolution timer (seconds since init)
```

---

## Buffers & Memory

### Creating Buffers

```sage
# Host-visible (CPU can read/write directly)
let buf = gpu.create_buffer(size_bytes, usage_flags, memory_flags)

# Common patterns:
let staging = gpu.create_buffer(1024, gpu.BUFFER_STAGING, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
let ssbo = gpu.create_buffer(4096, gpu.BUFFER_STORAGE, gpu.MEMORY_DEVICE_LOCAL)
let vbo = gpu.create_buffer(1024, gpu.BUFFER_VERTEX | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_DEVICE_LOCAL)
```

### Upload / Download

```sage
# Upload float array to host-visible buffer
gpu.buffer_upload(buf, [1.0, 2.0, 3.0, 4.0])

# Download as float array
let data = gpu.buffer_download(buf)

# Upload to device-local (uses staging buffer internally)
let device_buf = gpu.upload_device_local([1.0, 2.0, 3.0], gpu.BUFFER_VERTEX)

# Upload raw bytes (for index buffers, binary data)
let ibuf = gpu.upload_bytes([0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0], gpu.BUFFER_INDEX)
```

### Uniform Buffers

```sage
let ubo = gpu.create_uniform_buffer(256)    # Persistent mapped
gpu.update_uniform(ubo, [1.0, 0.0, 0.0, 0.0, ...])  # Fast write (no staging)
```

### Buffer Usage Flags

| Flag | Value | Purpose |
|------|-------|---------|
| `BUFFER_STORAGE` | 0x01 | Shader storage buffer (SSBO) |
| `BUFFER_UNIFORM` | 0x02 | Uniform buffer (UBO) |
| `BUFFER_VERTEX` | 0x04 | Vertex buffer |
| `BUFFER_INDEX` | 0x08 | Index buffer |
| `BUFFER_STAGING` | 0x10 | CPU-to-GPU transfer source |
| `BUFFER_INDIRECT` | 0x20 | Indirect draw/dispatch args |
| `BUFFER_TRANSFER_SRC` | 0x40 | Copy source |
| `BUFFER_TRANSFER_DST` | 0x80 | Copy destination |

### Memory Flags

| Flag | Value | Purpose |
|------|-------|---------|
| `MEMORY_DEVICE_LOCAL` | 0x01 | Fast GPU memory (not CPU accessible) |
| `MEMORY_HOST_VISIBLE` | 0x02 | CPU can read/write |
| `MEMORY_HOST_COHERENT` | 0x04 | No manual flush needed |

---

## Images & Textures

### Creating Images

```sage
# 2D image
let img = gpu.create_image(width, height, 1, gpu.FORMAT_RGBA8, gpu.IMAGE_SAMPLED)

# 3D volume texture
let vol = gpu.create_image_3d(64, 64, 64, gpu.FORMAT_RGBA16F, gpu.IMAGE_STORAGE | gpu.IMAGE_SAMPLED)

# Cubemap (6 faces)
let cube = gpu.create_cubemap(512, gpu.FORMAT_RGBA8, gpu.IMAGE_SAMPLED | gpu.IMAGE_TRANSFER_DST)

# Depth buffer (auto-detects best format)
let depth = gpu.create_depth_buffer(width, height)
```

### Loading Textures from Files

```sage
# PNG, JPG, BMP, TGA supported (via stb_image)
let tex = gpu.load_texture("textures/diffuse.png")
let dims = gpu.texture_dims(tex)
print dims["width"] + "x" + dims["height"]
```

### Mipmaps & Samplers

```sage
# Generate mipmap chain
gpu.generate_mipmaps(image_handle, width, height)

# Simple sampler
let smp = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_REPEAT)

# Advanced sampler with anisotropy and mipmaps
let smp = gpu.create_sampler_advanced(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_REPEAT, 16.0, 8.0)
```

---

## Shaders & Pipelines

### Loading Shaders

Shaders must be pre-compiled to SPIR-V format:

```bash
glslc shader.vert -o shader.vert.spv
glslc shader.frag -o shader.frag.spv
glslc shader.comp -o shader.comp.spv
```

```sage
let vert = gpu.load_shader("shader.vert.spv", gpu.STAGE_VERTEX)
let frag = gpu.load_shader("shader.frag.spv", gpu.STAGE_FRAGMENT)
let comp = gpu.load_shader("compute.comp.spv", gpu.STAGE_COMPUTE)

# Hot-reload (replace shader module without destroying pipeline)
gpu.reload_shader(vert, "shader_v2.vert.spv")
```

### Compute Pipelines

```sage
let layout = gpu.create_pipeline_layout([desc_layout], push_size, gpu.STAGE_COMPUTE)
let pipeline = gpu.create_compute_pipeline(layout, comp_shader)
```

### Graphics Pipelines

```sage
let cfg = {}
cfg["layout"] = pipe_layout
cfg["render_pass"] = render_pass
cfg["vertex_shader"] = vert
cfg["fragment_shader"] = frag
cfg["topology"] = gpu.TOPO_TRIANGLE_LIST    # or LINE_LIST, POINT_LIST
cfg["cull_mode"] = gpu.CULL_BACK            # NONE, FRONT, BACK
cfg["front_face"] = gpu.FRONT_CCW           # or FRONT_CW
cfg["depth_test"] = true
cfg["depth_write"] = true
cfg["blend"] = true                          # Alpha blending
cfg["vertex_bindings"] = [binding_desc]
cfg["vertex_attribs"] = [attr_descs]

let pipeline = gpu.create_graphics_pipeline(cfg)
```

---

## Render Passes & Framebuffers

### Standard Render Pass

```sage
# Color-only
let attach = {}
attach["format"] = gpu.FORMAT_SWAPCHAIN
attach["load_op"] = gpu.LOAD_CLEAR
attach["store_op"] = gpu.STORE_STORE
attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
attach["final_layout"] = gpu.LAYOUT_PRESENT
let rp = gpu.create_render_pass([attach])
```

### Render Pass with Depth

```sage
let color = {}
color["format"] = gpu.FORMAT_SWAPCHAIN
color["load_op"] = gpu.LOAD_CLEAR
color["store_op"] = gpu.STORE_STORE
color["initial_layout"] = gpu.LAYOUT_UNDEFINED
color["final_layout"] = gpu.LAYOUT_PRESENT

let depth = {}
depth["format"] = gpu.FORMAT_DEPTH32F
depth["load_op"] = gpu.LOAD_CLEAR
depth["store_op"] = gpu.STORE_DONTCARE
depth["initial_layout"] = gpu.LAYOUT_UNDEFINED
depth["final_layout"] = gpu.LAYOUT_DEPTH_ATTACH

let rp = gpu.create_render_pass([color, depth])
let fbs = gpu.create_swapchain_framebuffers_depth(rp, depth_image)
```

### Multiple Render Targets (Deferred/G-Buffer)

```sage
let formats = [gpu.FORMAT_RGBA16F, gpu.FORMAT_RGBA16F, gpu.FORMAT_RGBA8, gpu.FORMAT_RGBA16F]
let rp = gpu.create_render_pass_mrt(formats, true)  # 4 color + depth
```

### Offscreen Render Targets

```sage
let target = gpu.create_offscreen_target(512, 512, gpu.FORMAT_RGBA16F, true)
# Returns: {image, depth, render_pass, framebuffer, width, height}
```

---

## Command Recording

```sage
let pool = gpu.create_command_pool()
let cmd = gpu.create_command_buffer(pool)

gpu.begin_commands(cmd)

# Compute dispatch
gpu.cmd_bind_compute_pipeline(cmd, compute_pipe)
gpu.cmd_bind_descriptor_set(cmd, pipe_layout, 0, desc_set)
gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_COMPUTE, [dt, 0.0, 0.0, 0.0])
gpu.cmd_dispatch(cmd, 256, 1, 1)

# Barrier
gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_FRAGMENT, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_SHADER_READ)

# Render pass
gpu.cmd_begin_render_pass(cmd, rp, framebuffer, [[0.0, 0.0, 0.0, 1.0]])
gpu.cmd_set_viewport(cmd, 0, 0, width, height, 0.0, 1.0)
gpu.cmd_set_scissor(cmd, 0, 0, width, height)

gpu.cmd_bind_graphics_pipeline(cmd, graphics_pipe)
gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_VERTEX, mvp_matrix)
gpu.cmd_bind_vertex_buffer(cmd, vbo)
gpu.cmd_bind_index_buffer(cmd, ibo)
gpu.cmd_draw_indexed(cmd, index_count, 1, 0, 0, 0)

gpu.cmd_end_render_pass(cmd)
gpu.end_commands(cmd)
```

### Indirect Drawing (GPU-Driven)

```sage
gpu.cmd_draw_indirect(cmd, indirect_buffer, offset, draw_count, stride)
gpu.cmd_draw_indexed_indirect(cmd, indirect_buffer, offset, draw_count, stride)
gpu.cmd_dispatch_indirect(cmd, indirect_buffer, offset)
```

---

## Synchronization & Submission

### Fences and Semaphores

```sage
let fence = gpu.create_fence(true)        # Signaled initially
let sem = gpu.create_semaphore()

gpu.wait_fence(fence)                     # Block until signaled
gpu.reset_fence(fence)                    # Reset for reuse
```

### Frame Synchronization Pattern

```sage
# Per-frame sync (2 frames in flight)
let max_frames = 2
let img_sems = []
let rdr_sems = []
let fences = []
let fi = 0
while fi < max_frames:
    push(img_sems, gpu.create_semaphore())
    push(rdr_sems, gpu.create_semaphore())
    push(fences, gpu.create_fence(true))
    fi = fi + 1

# In render loop:
let cf = frame % max_frames
gpu.wait_fence(fences[cf])
gpu.reset_fence(fences[cf])
let idx = gpu.acquire_next_image(img_sems[cf])
# ... record commands ...
gpu.submit_with_sync(cmd, img_sems[cf], rdr_sems[cf], fences[cf])
gpu.present(idx, rdr_sems[cf])
```

---

## Descriptors & Uniforms

### Descriptor Layout

```sage
let b0 = {}
b0["binding"] = 0
b0["type"] = gpu.DESC_STORAGE_BUFFER   # or UNIFORM_BUFFER, SAMPLED_IMAGE, STORAGE_IMAGE, COMBINED_SAMPLER
b0["stage"] = gpu.STAGE_COMPUTE
b0["count"] = 1

let layout = gpu.create_descriptor_layout([b0])
```

### Pool, Set, and Binding

```sage
let ps = {}
ps["type"] = gpu.DESC_STORAGE_BUFFER
ps["count"] = 4
let pool = gpu.create_descriptor_pool(2, [ps])
let desc_set = gpu.allocate_descriptor_set(pool, layout)

# Bind buffer to descriptor
gpu.update_descriptor(desc_set, 0, gpu.DESC_STORAGE_BUFFER, buffer_handle)

# Bind combined image sampler
gpu.update_descriptor_image(desc_set, 1, image_handle, sampler_handle)
```

---

## 3D Math Library

`lib/math3d.sage` provides all vector/matrix operations needed for 3D rendering.

### Vectors

```sage
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_dot, v3_cross, v3_normalize, v3_length

let a = vec3(1.0, 0.0, 0.0)
let b = vec3(0.0, 1.0, 0.0)
let c = v3_cross(a, b)         # [0, 0, 1]
let d = v3_dot(a, b)           # 0.0
let n = v3_normalize(vec3(3, 0, 4))   # [0.6, 0, 0.8]
```

### Matrices

Matrices are column-major flat arrays of 16 floats (matching GLSL/Vulkan):

```sage
from math3d import mat4_identity, mat4_mul, mat4_translate, mat4_scale
from math3d import mat4_rotate_x, mat4_rotate_y, mat4_rotate_z
from math3d import mat4_perspective, mat4_ortho, mat4_look_at
from math3d import radians, pack_mvp

# Transform chain
let model = mat4_mul(mat4_translate(0, 1, 0), mat4_rotate_y(radians(45)))
let view = mat4_look_at(vec3(0, 2, 5), vec3(0, 0, 0), vec3(0, 1, 0))
let proj = mat4_perspective(radians(60), aspect, 0.1, 100.0)

# Pack for push constants
let mvp = pack_mvp(model, view, proj)
gpu.cmd_push_constants(cmd, layout, gpu.STAGE_VERTEX, mvp)
```

The perspective matrix is Vulkan-convention: Y-flipped, depth range 0-1.

### Cameras

```sage
from math3d import camera_orbit, camera_fps

# Orbit camera (for object inspection)
let view = camera_orbit(angle_x, angle_y, distance, target_vec3)

# FPS camera
let view = camera_fps(position_vec3, yaw, pitch)
```

---

## Meshes & Geometry

`lib/mesh.sage` provides procedural mesh generation and OBJ loading.

### Vertex Format

All meshes use: `[px, py, pz, nx, ny, nz, u, v]` per vertex (32 bytes stride).

### Procedural Meshes

```sage
from mesh import cube_mesh, plane_mesh, sphere_mesh, upload_mesh

let cube = upload_mesh(cube_mesh())           # 24 verts, 36 indices
let floor = upload_mesh(plane_mesh(10.0))     # 4 verts, 6 indices
let sphere = upload_mesh(sphere_mesh(24, 48)) # UV sphere

# Returns {vbuf, ibuf, vertex_count, index_count}
```

### OBJ File Loading

```sage
from mesh import load_obj, upload_mesh

let mesh = load_obj("models/teapot.obj")
if mesh != nil:
    let gpu_mesh = upload_mesh(mesh)
    print "Loaded: " + str(mesh["vertex_count"]) + " vertices"
```

Supports: `v` (positions), `vn` (normals), `vt` (UVs), `f` (faces with triangulation).

### Drawing Meshes

```sage
from mesh import mesh_vertex_binding, mesh_vertex_attribs

# For pipeline creation:
cfg["vertex_bindings"] = [mesh_vertex_binding()]
cfg["vertex_attribs"] = mesh_vertex_attribs()

# For drawing:
gpu.cmd_bind_vertex_buffer(cmd, gpu_mesh["vbuf"])
gpu.cmd_bind_index_buffer(cmd, gpu_mesh["ibuf"])
gpu.cmd_draw_indexed(cmd, gpu_mesh["index_count"], 1, 0, 0, 0)
```

**Important**: Index buffers must be uploaded as uint32 bytes (not floats). `upload_mesh()` handles this automatically using `gpu.upload_bytes()`.

---

## Interactive Camera

`lib/camera.sage` provides a ready-to-use FPS/orbit camera with WASD + mouse look.

```sage
from camera import create_camera, update_camera, camera_position

let cam = create_camera(0.0, 2.0, 5.0)   # Starting position

# In render loop:
gpu.update_input()  # Must call before camera update
let view = update_camera(cam, delta_time)

# Controls:
# WASD      - Move forward/back/left/right
# Space     - Move up
# Shift     - Move down
# Mouse     - Look around (when captured)
# Right MB  - Capture mouse
# Escape    - Release mouse
# Scroll    - Adjust movement speed
```

---

## High-Level Renderer

`lib/renderer.sage` manages the full frame lifecycle:

```sage
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer
from renderer import aspect_ratio, check_resize, update_title_fps

let r = create_renderer(1024, 768, "My Scene")

let frame = begin_frame(r)
while frame != nil:
    check_resize(r)                    # Handle window resize
    update_title_fps(r, "My Scene")    # FPS in title bar

    let cmd = frame["cmd"]
    let t = frame["time"]

    # Draw your scene...

    end_frame(r, frame)
    frame = begin_frame(r)

shutdown_renderer(r)  # Prints FPS stats
```

---

## PBR Materials

`lib/pbr.sage` provides physically-based rendering material definitions.

### Material Presets

```sage
from pbr import pbr_gold, pbr_silver, pbr_copper, pbr_plastic_red, pbr_rubber, pbr_ceramic

let gold = pbr_gold()           # metallic=1.0, roughness=0.3
let plastic = pbr_plastic_red() # metallic=0.0, roughness=0.5
let emissive = pbr_emissive([1.0, 0.5, 0.0], 5.0)  # Glowing orange
```

### Custom Materials

```sage
from pbr import create_pbr_material, pack_pbr_material

let mat = create_pbr_material([0.9, 0.1, 0.1], 0.8, 0.2, 1.0)
# albedo=[R,G,B], metallic, roughness, ambient_occlusion

let ubo_data = pack_pbr_material(mat)  # 16 floats for UBO
```

### PBR Shader

The `pbr.frag` shader implements Cook-Torrance BRDF with:
- GGX/Trowbridge-Reitz Normal Distribution Function
- Smith Geometry Function (Schlick-GGX)
- Schlick Fresnel Approximation
- Reinhard HDR tone mapping
- Gamma correction

---

## Post-Processing

`lib/postprocess.sage` manages HDR rendering, bloom, and tone mapping.

```sage
from postprocess import create_postprocess, tonemap_params

let pp = create_postprocess(1024, 768)
pp["exposure"] = 1.5
pp["bloom_intensity"] = 0.4
pp["tonemap_mode"] = TONEMAP_ACES   # or REINHARD, UNCHARTED2
```

### Bloom Pipeline

Three shader passes in `examples/shaders/`:
1. `bloom_extract.frag` — Extract pixels above brightness threshold
2. `bloom_blur.frag` — 5-tap Gaussian blur (horizontal + vertical)
3. `bloom_composite.frag` — Combine scene + bloom with tone mapping (ACES or Reinhard)

---

## Shadows

`lib/shadows.sage` provides shadow mapping utilities.

```sage
from shadows import create_shadow_map, create_shadow_pass, create_cascade_shadows, compute_light_matrix

# Single shadow map
let sm = create_shadow_map(2048)
let sp = create_shadow_pass()

# Cascade shadows (4 cascades for large scenes)
let csm = create_cascade_shadows(2048, 4)

# Compute light-space matrix
let light_mat = compute_light_matrix(light_direction, scene_min, scene_max)
```

### Two-Pass Shadow Rendering

1. **Depth pass**: Render scene from light's perspective using `shadow_depth.vert/.frag`
2. **Main pass**: Sample shadow map in fragment shader, compare depth

---

## Deferred Rendering

`lib/deferred.sage` provides G-buffer management and screen-space effects.

### G-Buffer

```sage
from deferred import create_gbuffer, create_ssao_context, create_ssr_context

let gb = create_gbuffer(1024, 768)
# Creates 4 color attachments + depth:
# 0: Position (RGBA16F)
# 1: Normal (RGBA16F)
# 2: Albedo (RGBA8)
# 3: Emission (RGBA16F)
# + Depth (auto format)
```

### SSAO (Screen-Space Ambient Occlusion)

```sage
let ssao = create_ssao_context(1024, 768)
ssao["radius"] = 0.5
ssao["kernel_size"] = 32
```

### SSR (Screen-Space Reflections)

```sage
let ssr = create_ssr_context(1024, 768)
ssr["max_steps"] = 64
ssr["max_distance"] = 50.0
```

---

## Compute Shaders

### Basic Compute Dispatch

```sage
let comp = gpu.load_shader("compute.comp.spv", gpu.STAGE_COMPUTE)
let layout = gpu.create_pipeline_layout([desc_layout], 16, gpu.STAGE_COMPUTE)
let pipeline = gpu.create_compute_pipeline(layout, comp)

gpu.cmd_bind_compute_pipeline(cmd, pipeline)
gpu.cmd_bind_descriptor_set(cmd, layout, 0, desc_set)
gpu.cmd_push_constants(cmd, layout, gpu.STAGE_COMPUTE, [dt, param1, param2, param3])
gpu.cmd_dispatch(cmd, workgroup_x, workgroup_y, workgroup_z)
```

### Ping-Pong Pattern (Double Buffering)

Used for particle systems and physics simulations:

```sage
# Create two SSBOs
let buf_a = gpu.create_buffer(size, gpu.BUFFER_STORAGE, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
let buf_b = gpu.create_buffer(size, gpu.BUFFER_STORAGE, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)

# Two descriptor sets: A->B and B->A
let desc_ab = gpu.allocate_descriptor_set(pool, layout)
let desc_ba = gpu.allocate_descriptor_set(pool, layout)
gpu.update_descriptor(desc_ab, 0, gpu.DESC_STORAGE_BUFFER, buf_a)  # Read from A
gpu.update_descriptor(desc_ab, 1, gpu.DESC_STORAGE_BUFFER, buf_b)  # Write to B
gpu.update_descriptor(desc_ba, 0, gpu.DESC_STORAGE_BUFFER, buf_b)  # Read from B
gpu.update_descriptor(desc_ba, 1, gpu.DESC_STORAGE_BUFFER, buf_a)  # Write to A

# Alternate each frame
if ping == 0:
    gpu.cmd_bind_descriptor_set(cmd, layout, 0, desc_ab)
else:
    gpu.cmd_bind_descriptor_set(cmd, layout, 0, desc_ba)
```

---

## Advanced Features

### Temporal Anti-Aliasing (TAA)

```sage
from taa import create_taa, taa_jitter_projection, taa_advance, pack_taa_params

let taa = create_taa(1024, 768)
let jittered_proj = taa_jitter_projection(projection_matrix, taa)
# ... render with jittered projection ...
taa_advance(taa)  # Swap history buffers, advance frame
```

### Scene Graph

```sage
from scene import create_node, add_child, world_transform, traverse, find_node

let root = create_node("root")
let cube = create_node("cube")
cube["transform"] = mat4_translate(2.0, 0.0, 0.0)
add_child(root, cube)

# Recursive traversal
proc draw_node(node):
    let wt = world_transform(node)
    # draw with wt as model matrix

traverse(root, draw_node)
```

### Material System

```sage
from material import create_material, build_pipeline, bind_material

let mat = create_material("vert.spv", "frag.spv", descriptor_bindings, push_size)
build_pipeline(mat, render_pass, vertex_bindings, vertex_attribs, config)

# In render loop:
bind_material(cmd, mat)
```

### Asset Cache

```sage
from asset_cache import load_shader_cached, load_texture_cached, cache_mesh

let shader = load_shader_cached("shader.spv", gpu.STAGE_VERTEX)  # Deduped
let tex = load_texture_cached("texture.png")                      # Deduped
```

### Frame Graph

```sage
from frame_graph import create_frame_graph, create_pass, fg_add_pass, fg_compile, fg_execute

let fg = create_frame_graph()
let shadow = create_pass("shadows", PASS_GRAPHICS)
pass_writes(shadow, "shadow_map")
let main = create_pass("main", PASS_GRAPHICS)
pass_reads(main, "shadow_map")
fg_add_pass(fg, shadow)
fg_add_pass(fg, main)
fg_compile(fg)   # Topological sort by dependencies
fg_execute(fg, cmd)
```

### Debug UI

```sage
from debug_ui import create_debug_ui, debug_frame, debug_fps, debug_set, debug_print

let ui = create_debug_ui()
debug_frame(ui, delta_time)
debug_set(ui, "particles", 65536)
debug_set(ui, "draw_calls", 42)
if gpu.key_just_pressed(gpu.KEY_F):
    debug_print(ui)   # Prints FPS, GPU name, custom values to console
```

### Screenshot

```sage
# Save current frame to PNG
gpu.save_screenshot("output.png")

# Raw pixel data
let shot = gpu.screenshot()   # {width, height, pixels}
```

---

## Engine Libraries Reference

| Library | File | Purpose |
|---------|------|---------|
| `gpu` | native C module | Core Vulkan operations |
| `vulkan` | lib/vulkan.sage | Builder pattern helpers |
| `math3d` | lib/math3d.sage | Vectors, matrices, camera, projection |
| `mesh` | lib/mesh.sage | Procedural meshes, OBJ loading, GPU upload |
| `camera` | lib/camera.sage | Interactive FPS/orbit camera |
| `renderer` | lib/renderer.sage | High-level frame loop |
| `pbr` | lib/pbr.sage | PBR materials and lights |
| `postprocess` | lib/postprocess.sage | HDR, bloom, tone mapping |
| `shadows` | lib/shadows.sage | Shadow map management |
| `deferred` | lib/deferred.sage | G-buffer, SSAO, SSR |
| `taa` | lib/taa.sage | Temporal anti-aliasing |
| `scene` | lib/scene.sage | Scene graph (node hierarchy) |
| `material` | lib/material.sage | Material system |
| `asset_cache` | lib/asset_cache.sage | Resource deduplication |
| `frame_graph` | lib/frame_graph.sage | Pass dependency ordering |
| `debug_ui` | lib/debug_ui.sage | FPS and debug overlay |
| `gltf` | lib/gltf.sage | glTF 2.0 model loading |
| `gpu` (lib) | lib/gpu.sage | High-level compute helpers |

---

## Demo Catalog

| Demo | File | What it shows |
|------|------|--------------|
| Empty Window | `examples/gpu_window.sage` | Window creation, clear color, frame loop |
| Triangle | `examples/gpu_triangle.sage` | Vertex/fragment shaders, SPIR-V loading |
| 3D Hello World | `examples/gpu_hello3d.sage` | Line rendering, push constants, perspective |
| Spinning Cube | `examples/gpu_cube.sage` | Depth buffer, indexed drawing, 3D transforms |
| Phong Scene | `examples/gpu_phong.sage` | Phong/Blinn-Phong lighting, orbit camera |
| GPU Particles | `examples/gpu_particles.sage` | Compute shader, ping-pong SSBO, 65536 particles |
| Planet | `examples/gpu_planet.sage` | Fullscreen raymarching, procedural terrain, atmosphere |
| N-Body Galaxy | `examples/gpu_nbody.sage` | N-body gravity, shared-memory compute, 8192 stars |
| PBR Materials | `examples/gpu_pbr.sage` | Cook-Torrance BRDF, metallic/roughness grid |

Run any demo:
```bash
./sage examples/gpu_planet.sage
```

---

## Troubleshooting

### "Vulkan not available"
- Install Vulkan SDK: `sudo apt install vulkan-tools libvulkan-dev`
- Verify: `vulkaninfo | head`
- Rebuild: `make clean && make`

### "window creation failed"
- Install GLFW: `sudo apt install libglfw3-dev`
- On Wayland, the engine forces X11 via `GLFW_PLATFORM_X11` to avoid libdecor crashes

### Black screen / no rendering
- Check shader compilation: `make shaders`
- Verify pipeline creation returns >= 0
- Ensure `cmd_set_viewport` and `cmd_set_scissor` are called

### Cube/mesh not visible
- Index buffers must use `gpu.upload_bytes()` with uint32 byte packing (not float upload)
- `upload_mesh()` handles this automatically
- Check view matrix direction — Vulkan is right-handed with -Z forward

### Validation errors about semaphores
- Use per-frame-in-flight sync (2+ semaphore/fence sets)
- Don't reuse a semaphore that's still pending from a previous present

---

## API Reference

### Context

| Function | Returns | Description |
|----------|---------|-------------|
| `gpu.has_vulkan()` | bool | Vulkan available? |
| `gpu.has_window` | bool | GLFW available? |
| `gpu.initialize(name, validation?)` | bool | Headless Vulkan init |
| `gpu.init_windowed(name, w, h, title, validation?)` | bool | Windowed init |
| `gpu.shutdown()` | nil | Destroy headless |
| `gpu.shutdown_windowed()` | nil | Destroy window + Vulkan |
| `gpu.device_name()` | string | GPU name |
| `gpu.device_limits()` | dict | Device capability limits |
| `gpu.device_wait_idle()` | nil | Wait for GPU idle |

### Buffers

| Function | Returns | Description |
|----------|---------|-------------|
| `gpu.create_buffer(size, usage, mem)` | handle | Create buffer |
| `gpu.create_uniform_buffer(size)` | handle | Persistent-mapped UBO |
| `gpu.update_uniform(handle, data)` | nil | Fast UBO write |
| `gpu.buffer_upload(handle, floats)` | bool | Upload float array |
| `gpu.buffer_download(handle)` | array | Download as floats |
| `gpu.upload_device_local(floats, usage)` | handle | Staging upload |
| `gpu.upload_bytes(bytes, usage)` | handle | Raw byte upload |
| `gpu.buffer_size(handle)` | number | Buffer size in bytes |
| `gpu.destroy_buffer(handle)` | nil | Destroy buffer |

### Images & Textures

| Function | Returns | Description |
|----------|---------|-------------|
| `gpu.create_image(w, h, d, fmt, usage)` | handle | Create 2D/3D image |
| `gpu.create_image_3d(w, h, d, fmt, usage)` | handle | Create 3D volume |
| `gpu.create_cubemap(size, fmt, usage)` | handle | Create cubemap (6 faces) |
| `gpu.create_depth_buffer(w, h)` | handle | Auto-format depth |
| `gpu.load_texture(path)` | handle | Load PNG/JPG via stb_image |
| `gpu.generate_mipmaps(img, w, h)` | nil | Generate mip chain |
| `gpu.create_sampler(mag, min, addr)` | handle | Simple sampler |
| `gpu.create_sampler_advanced(mag, min, addr, aniso, mips)` | handle | Anisotropic sampler |
| `gpu.image_dims(handle)` | dict | {width, height, depth} |
| `gpu.destroy_image(handle)` | nil | Destroy image |

### Shaders & Pipelines

| Function | Returns | Description |
|----------|---------|-------------|
| `gpu.load_shader(path, stage)` | handle | Load SPIR-V |
| `gpu.reload_shader(handle, path)` | bool | Hot-reload shader |
| `gpu.create_pipeline_layout(layouts, push_size?, stages?)` | handle | Pipeline layout |
| `gpu.create_compute_pipeline(layout, shader)` | handle | Compute pipeline |
| `gpu.create_graphics_pipeline(config_dict)` | handle | Graphics pipeline |
| `gpu.destroy_pipeline(handle)` | nil | Destroy pipeline |

### Render Passes

| Function | Returns | Description |
|----------|---------|-------------|
| `gpu.create_render_pass(attachments)` | handle | Standard render pass |
| `gpu.create_render_pass_mrt(formats, depth?)` | handle | Multi-target pass |
| `gpu.create_offscreen_target(w, h, fmt, depth?)` | dict | Offscreen target |
| `gpu.create_framebuffer(rp, images, w, h)` | handle | Custom framebuffer |
| `gpu.create_swapchain_framebuffers(rp)` | array | Swapchain FBs |
| `gpu.create_swapchain_framebuffers_depth(rp, depth)` | array | Swapchain FBs + depth |

### Commands

| Function | Description |
|----------|-------------|
| `gpu.begin_commands(cmd)` | Begin recording |
| `gpu.end_commands(cmd)` | End recording |
| `gpu.cmd_bind_compute_pipeline(cmd, pipe)` | Bind compute |
| `gpu.cmd_bind_graphics_pipeline(cmd, pipe)` | Bind graphics |
| `gpu.cmd_bind_descriptor_set(cmd, layout, idx, set)` | Bind descriptors |
| `gpu.cmd_dispatch(cmd, x, y, z)` | Compute dispatch |
| `gpu.cmd_dispatch_indirect(cmd, buf, offset)` | Indirect dispatch |
| `gpu.cmd_push_constants(cmd, layout, stage, data)` | Push constants |
| `gpu.cmd_begin_render_pass(cmd, rp, fb, clear)` | Begin render pass |
| `gpu.cmd_end_render_pass(cmd)` | End render pass |
| `gpu.cmd_draw(cmd, verts, inst, first_v, first_i)` | Draw |
| `gpu.cmd_draw_indexed(cmd, idx, inst, first, off, fi)` | Indexed draw |
| `gpu.cmd_draw_indirect(cmd, buf, off, count, stride)` | Indirect draw |
| `gpu.cmd_bind_vertex_buffer(cmd, buf)` | Bind single VBO |
| `gpu.cmd_bind_vertex_buffers(cmd, bufs_array)` | Bind multiple VBOs |
| `gpu.cmd_bind_index_buffer(cmd, buf)` | Bind IBO |
| `gpu.cmd_set_viewport(cmd, x, y, w, h, min, max)` | Set viewport |
| `gpu.cmd_set_scissor(cmd, x, y, w, h)` | Set scissor |
| `gpu.cmd_pipeline_barrier(cmd, src, dst, sa, da)` | Memory barrier |
| `gpu.cmd_image_barrier(cmd, img, old, new, ss, ds, sa, da)` | Image barrier |

### Sync & Present

| Function | Returns | Description |
|----------|---------|-------------|
| `gpu.create_fence(signaled?)` | handle | Create fence |
| `gpu.wait_fence(handle, timeout?)` | bool | Wait for fence |
| `gpu.reset_fence(handle)` | nil | Reset fence |
| `gpu.create_semaphore()` | handle | Create semaphore |
| `gpu.acquire_next_image(semaphore)` | number | Get swapchain image |
| `gpu.present(image_idx, wait_sem)` | bool | Present to screen |
| `gpu.submit_with_sync(cmd, wait, signal, fence)` | nil | Full sync submit |
| `gpu.submit(cmd, wait?, signal?, fence?)` | nil | Graphics submit |
| `gpu.submit_compute(cmd, wait?, signal?, fence?)` | nil | Compute submit |
| `gpu.recreate_swapchain()` | bool | Rebuild swapchain |

### Input

| Function | Returns | Description |
|----------|---------|-------------|
| `gpu.key_pressed(key)` | bool | Key held down |
| `gpu.key_just_pressed(key)` | bool | First frame pressed |
| `gpu.key_just_released(key)` | bool | First frame released |
| `gpu.update_input()` | nil | Update key states |
| `gpu.mouse_pos()` | dict | {x, y} in pixels |
| `gpu.mouse_button(btn)` | bool | Button held |
| `gpu.scroll_delta()` | dict | {x, y} consumed |
| `gpu.set_cursor_mode(mode)` | nil | Cursor capture |
| `gpu.get_time()` | number | Seconds since init |
| `gpu.set_title(title)` | nil | Window title |
| `gpu.save_screenshot(path)` | bool | Save to PNG |

---

## OpenGL 4.5 Backend

SageLang supports OpenGL 4.5+ as an alternative to Vulkan via `lib/opengl.sage`.

### Setup

```sage
import opengl

# Initialize with OpenGL instead of Vulkan
opengl.init_windowed("My App", 800, 600)
print opengl.device_name()
```

### Differences from Vulkan

| Feature | Vulkan (`import gpu`) | OpenGL (`import opengl`) |
|---------|----------------------|-------------------------|
| Shader format | SPIR-V (`.spv` files) | GLSL via `gpu.load_shader_glsl()` |
| Initialization | `gpu.init_windowed()` | `opengl.init_windowed()` |
| API surface | Identical after init | Identical after init |
| Backend flag | `SAGE_HAS_VULKAN` | `SAGE_HAS_OPENGL` |

### Build Detection

OpenGL is auto-detected via pkg-config:

```bash
make                 # Auto-detect both Vulkan and OpenGL
make OPENGL=1        # Force OpenGL
make OPENGL=0        # Disable OpenGL
```

When `SAGE_HAS_OPENGL` is set, the GPU API layer (`gpu_api.c`) initializes an OpenGL 4.5 core profile context via GLFW. All `sgpu_*` functions route to OpenGL calls instead of Vulkan.

### LLVM Compiled Path

LLVM-compiled programs automatically link against both backends:

```bash
sage --compile-llvm game.sage -o game
# Links: -lvulkan -lglfw -lGL
```

---

## UI Widget Library

`lib/ui.sage` provides an immediate-mode GUI system for GPU applications, similar in philosophy to Dear ImGui.

### Quick Start

```sage
import gpu
import ui

gpu.init_windowed("UI Demo", 800, 600, "Sage UI", false)
let ctx = ui.ui_create()

while not gpu.window_should_close():
    gpu.poll_events()
    ui.ui_begin_frame(ctx)

    # Draw widgets
    ui.ui_panel(ctx, 10, 10, 300, 400, "My Panel")
    if ui.ui_button(ctx, 20, 50, 120, 30, "Click Me"):
        print "Button clicked!"

    ui.ui_label(ctx, 20, 90, "Hello from Sage UI")

    ui.ui_end_frame(ctx)
    # ui.ui_render(ctx, cmd_buf, font)  # Issue GPU draw commands
```

### Widget Reference

| Widget | Function | Returns |
|--------|----------|---------|
| Label | `ui_label(ctx, x, y, text)` | nil |
| Button | `ui_button(ctx, x, y, w, h, label)` | bool (clicked) |
| Panel | `ui_panel(ctx, x, y, w, h, title)` | nil |
| Window | `ui_window(ctx, x, y, w, h, title)` | dict (content area) |
| Checkbox | `ui_checkbox(ctx, x, y, label, checked)` | bool (new state) |
| Slider | `ui_slider(ctx, x, y, w, label, value)` | number (0.0-1.0) |
| Scrollbar | `ui_scrollbar_v(ctx, x, y, h, content_h, scroll)` | number (0.0-1.0) |
| Menu | `ui_menu_button(ctx, x, y, w, h, label, items)` | int (item index or -1) |
| Text Input | `ui_text_input(ctx, x, y, w, label, text)` | string (current text) |
| Progress | `ui_progress(ctx, x, y, w, h, value, label)` | nil |
| Separator | `ui_separator(ctx, x, y, w)` | nil |
| Tooltip | `ui_tooltip(ctx, text)` | nil |

### Theming

```sage
let ctx = ui.ui_create()
let theme = ctx["theme"]

# Customize colors (RGBA arrays)
theme["accent"] = [0.9, 0.3, 0.1, 1.0]     # Orange accent
theme["bg"] = [0.05, 0.05, 0.08, 0.95]      # Darker background
theme["text"] = [1.0, 1.0, 1.0, 1.0]        # White text

# Customize sizes
theme["font_size"] = 14
theme["padding"] = 8
theme["title_height"] = 28
```

### Architecture

The UI library uses an immediate-mode pattern:

1. **`ui_begin_frame(ctx)`** — reads mouse input from `gpu.mouse_pos()` / `gpu.mouse_button()`
2. **Widget calls** — each widget checks hit-testing, updates state, and appends draw commands to `ctx["draw_list"]`
3. **`ui_end_frame(ctx)`** — resets active state when mouse released
4. **`ui_render(ctx, cmd_buf, font)`** — issues GPU draw commands for all accumulated quads and text

Draw commands are dicts with `type` ("rect" or "text"), position, size, and color. Custom renderers can read `ui_get_draw_list(ctx)` directly.
