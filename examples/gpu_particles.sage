# gpu_particles.sage - Demo: GPU Compute Particle System
# 65536 particles simulated via compute shader, rendered as point sprites
#
# Run: ./sage examples/gpu_particles.sage

import gpu
import math

print "=== Sage GPU Demo: GPU Particles ==="

let ok = gpu.init_windowed("Sage Particles", 1024, 768, "Sage - GPU Particles (65536)", false)
if ok == false:
    raise "Failed to initialize GPU"

print "GPU: " + gpu.device_name()
let ext = gpu.swapchain_extent()

# Particle count
let PARTICLE_COUNT = 65536
let PARTICLE_SIZE = 8

# Initialize particle data: [px, py, vx, vy, r, g, b, a] per particle
let init_data = []
let pi = 0
while pi < PARTICLE_COUNT:
    # Random-ish initial position using sin/cos of index
    let angle = pi * 2.399963
    let radius = 0.3 + (pi * 7.31 - (pi * 7.31 / PARTICLE_COUNT) * PARTICLE_COUNT) / PARTICLE_COUNT * 0.6
    let px = math.cos(angle) * radius
    let py = math.sin(angle) * radius
    # Small random velocity
    let vx = math.sin(pi * 1.7) * 0.02
    let vy = math.cos(pi * 2.3) * 0.02
    push(init_data, px)
    push(init_data, py)
    push(init_data, vx)
    push(init_data, vy)
    push(init_data, 0.3)
    push(init_data, 0.5)
    push(init_data, 1.0)
    push(init_data, 1.0)
    pi = pi + 1
print "Particles initialized: " + str(PARTICLE_COUNT)

# Create ping-pong storage buffers
let buf_size = PARTICLE_COUNT * PARTICLE_SIZE * 4
let buf_a = gpu.create_buffer(buf_size, gpu.BUFFER_STORAGE | gpu.BUFFER_VERTEX | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
let buf_b = gpu.create_buffer(buf_size, gpu.BUFFER_STORAGE | gpu.BUFFER_VERTEX, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
gpu.buffer_upload(buf_a, init_data)

# Compute pipeline setup
let comp_shader = gpu.load_shader("examples/shaders/particle.comp.spv", gpu.STAGE_COMPUTE)
if comp_shader < 0:
    raise "Failed to load compute shader"

# Descriptor layout: binding 0 = input SSBO, binding 1 = output SSBO
let b0 = {}
b0["binding"] = 0
b0["type"] = gpu.DESC_STORAGE_BUFFER
b0["stage"] = gpu.STAGE_COMPUTE
b0["count"] = 1
let b1 = {}
b1["binding"] = 1
b1["type"] = gpu.DESC_STORAGE_BUFFER
b1["stage"] = gpu.STAGE_COMPUTE
b1["count"] = 1
let comp_layout = gpu.create_descriptor_layout([b0, b1])

# Two descriptor sets for ping-pong
let ps = {}
ps["type"] = gpu.DESC_STORAGE_BUFFER
ps["count"] = 4
let comp_pool = gpu.create_descriptor_pool(2, [ps])
let desc_ab = gpu.allocate_descriptor_set(comp_pool, comp_layout)
let desc_ba = gpu.allocate_descriptor_set(comp_pool, comp_layout)
gpu.update_descriptor(desc_ab, 0, gpu.DESC_STORAGE_BUFFER, buf_a)
gpu.update_descriptor(desc_ab, 1, gpu.DESC_STORAGE_BUFFER, buf_b)
gpu.update_descriptor(desc_ba, 0, gpu.DESC_STORAGE_BUFFER, buf_b)
gpu.update_descriptor(desc_ba, 1, gpu.DESC_STORAGE_BUFFER, buf_a)

# Compute pipeline layout (push: dt, attractorX, attractorY, count = 16 bytes)
let comp_pipe_layout = gpu.create_pipeline_layout([comp_layout], 16, gpu.STAGE_COMPUTE)
let comp_pipeline = gpu.create_compute_pipeline(comp_pipe_layout, comp_shader)

# Graphics pipeline for rendering particles
let gfx_vert = gpu.load_shader("examples/shaders/particle.vert.spv", gpu.STAGE_VERTEX)
let gfx_frag = gpu.load_shader("examples/shaders/particle.frag.spv", gpu.STAGE_FRAGMENT)

# Descriptor layout for graphics: binding 0 = particle SSBO (vertex shader reads it)
let gfx_b0 = {}
gfx_b0["binding"] = 0
gfx_b0["type"] = gpu.DESC_STORAGE_BUFFER
gfx_b0["stage"] = gpu.STAGE_VERTEX
gfx_b0["count"] = 1
let gfx_desc_layout = gpu.create_descriptor_layout([gfx_b0])

let gfx_ps = {}
gfx_ps["type"] = gpu.DESC_STORAGE_BUFFER
gfx_ps["count"] = 2
let gfx_pool = gpu.create_descriptor_pool(2, [gfx_ps])
let gfx_desc_a = gpu.allocate_descriptor_set(gfx_pool, gfx_desc_layout)
let gfx_desc_b = gpu.allocate_descriptor_set(gfx_pool, gfx_desc_layout)
gpu.update_descriptor(gfx_desc_a, 0, gpu.DESC_STORAGE_BUFFER, buf_a)
gpu.update_descriptor(gfx_desc_b, 0, gpu.DESC_STORAGE_BUFFER, buf_b)

# Render pass (no depth needed for particles)
let color_attach = {}
color_attach["format"] = gpu.FORMAT_SWAPCHAIN
color_attach["load_op"] = gpu.LOAD_CLEAR
color_attach["store_op"] = gpu.STORE_STORE
color_attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
color_attach["final_layout"] = gpu.LAYOUT_PRESENT
let rp = gpu.create_render_pass([color_attach])

let gfx_pipe_layout = gpu.create_pipeline_layout([gfx_desc_layout], 0)

let gfx_cfg = {}
gfx_cfg["layout"] = gfx_pipe_layout
gfx_cfg["render_pass"] = rp
gfx_cfg["vertex_shader"] = gfx_vert
gfx_cfg["fragment_shader"] = gfx_frag
gfx_cfg["topology"] = gpu.TOPO_POINT_LIST
gfx_cfg["cull_mode"] = gpu.CULL_NONE
gfx_cfg["blend"] = true
let gfx_pipeline = gpu.create_graphics_pipeline(gfx_cfg)
if gfx_pipeline < 0:
    raise "Failed to create particle graphics pipeline"

let framebuffers = gpu.create_swapchain_framebuffers(rp)
let cmd_pool = gpu.create_command_pool()
let cmd_bufs = []
let ci = 0
while ci < len(framebuffers):
    push(cmd_bufs, gpu.create_command_buffer(cmd_pool))
    ci = ci + 1

# Sync
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

# Render loop
let frame = 0
let last_time = clock()
let ping = 0
print "Simulating " + str(PARTICLE_COUNT) + " particles... (close window to exit)"

while gpu.window_should_close() == false:
    gpu.poll_events()

    let cf = frame % max_frames
    gpu.wait_fence(fences[cf])
    gpu.reset_fence(fences[cf])

    let img_idx = gpu.acquire_next_image(img_sems[cf])
    if img_idx < 0:
        continue

    let now = clock()
    let dt = now - last_time
    if dt > 0.1:
        dt = 0.016
    last_time = now

    # Attractor orbits
    let t = now
    let ax = math.cos(t * 0.7) * 0.5
    let ay = math.sin(t * 1.1) * 0.5

    let cmd = cmd_bufs[img_idx]
    gpu.begin_commands(cmd)

    # Compute pass
    gpu.cmd_bind_compute_pipeline(cmd, comp_pipeline)
    if ping == 0:
        gpu.cmd_bind_descriptor_set(cmd, comp_pipe_layout, 0, desc_ab)
    else:
        gpu.cmd_bind_descriptor_set(cmd, comp_pipe_layout, 0, desc_ba)
    gpu.cmd_push_constants(cmd, comp_pipe_layout, gpu.STAGE_COMPUTE, [dt, ax, ay, PARTICLE_COUNT])
    gpu.cmd_dispatch(cmd, PARTICLE_COUNT / 256, 1, 1)

    # Barrier: compute -> vertex read
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_VERTEX_SHADER, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_SHADER_READ)

    # Render pass
    gpu.cmd_begin_render_pass(cmd, rp, framebuffers[img_idx], [[0.01, 0.01, 0.03, 1.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, ext["width"], ext["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, ext["width"], ext["height"])

    gpu.cmd_bind_graphics_pipeline(cmd, gfx_pipeline)
    if ping == 0:
        gpu.cmd_bind_descriptor_set(cmd, gfx_pipe_layout, 0, gfx_desc_b, 0)
    else:
        gpu.cmd_bind_descriptor_set(cmd, gfx_pipe_layout, 0, gfx_desc_a, 0)
    gpu.cmd_draw(cmd, PARTICLE_COUNT, 1, 0, 0)

    gpu.cmd_end_render_pass(cmd)
    gpu.end_commands(cmd)

    gpu.submit_with_sync(cmd, img_sems[cf], rdr_sems[cf], fences[cf])
    gpu.present(img_idx, rdr_sems[cf])

    # Swap ping-pong
    if ping == 0:
        ping = 1
    else:
        ping = 0
    frame = frame + 1

gpu.device_wait_idle()
let total_t = clock() - (last_time - 0.016)
print "Rendered " + str(frame) + " frames"
gpu.shutdown_windowed()
print "Done!"
