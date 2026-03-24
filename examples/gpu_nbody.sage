# gpu_nbody.sage - Demo 5: N-Body Galaxy Simulation
# Thousands of gravitating bodies rendered as stars
#
# Run: ./sage examples/gpu_nbody.sage

import gpu
import math

print "=== Sage GPU Demo: N-Body Galaxy ==="

let ok = gpu.init_windowed("Sage Galaxy", 1280, 720, "Sage - N-Body Galaxy", false)
if ok == false:
    raise "Failed to initialize GPU"
print "GPU: " + gpu.device_name()

# Body count (must be multiple of 256)
let BODY_COUNT = 8192
let BODY_SIZE = 8

# Initialize bodies in a spinning disk
let init_data = []
let bi = 0
while bi < BODY_COUNT:
    let angle = bi * 2.399963
    let r = 2.0 + (bi * 17.31 - (bi * 17.31 / BODY_COUNT) * BODY_COUNT) / BODY_COUNT * 15.0
    let px = math.cos(angle) * r
    let py = (math.sin(bi * 3.7) - 0.5) * 0.5
    let pz = math.sin(angle) * r
    let mass = 0.5 + (bi * 7.13 - (bi * 7.13 / BODY_COUNT) * BODY_COUNT) / BODY_COUNT * 1.5

    # Orbital velocity (tangential)
    let speed = math.sqrt(0.5 / (r + 1.0)) * 3.0
    let vx = 0 - math.sin(angle) * speed
    let vy = 0.0
    let vz = math.cos(angle) * speed

    # positionMass (vec4)
    push(init_data, px)
    push(init_data, py)
    push(init_data, pz)
    push(init_data, mass)
    # velocity (vec4)
    push(init_data, vx)
    push(init_data, vy)
    push(init_data, vz)
    push(init_data, 0.0)
    bi = bi + 1

print "Bodies: " + str(BODY_COUNT)

# Ping-pong buffers
let buf_size = BODY_COUNT * BODY_SIZE * 4
let buf_a = gpu.create_buffer(buf_size, gpu.BUFFER_STORAGE | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
let buf_b = gpu.create_buffer(buf_size, gpu.BUFFER_STORAGE, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
gpu.buffer_upload(buf_a, init_data)

# Compute pipeline
let comp_shader = gpu.load_shader("examples/shaders/nbody.comp.spv", gpu.STAGE_COMPUTE)
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
let comp_pipe_layout = gpu.create_pipeline_layout([comp_layout], 16, gpu.STAGE_COMPUTE)
let comp_pipeline = gpu.create_compute_pipeline(comp_pipe_layout, comp_shader)

# Graphics pipeline for stars
let star_vert = gpu.load_shader("examples/shaders/star.vert.spv", gpu.STAGE_VERTEX)
let star_frag = gpu.load_shader("examples/shaders/star.frag.spv", gpu.STAGE_FRAGMENT)

let gfx_b0 = {}
gfx_b0["binding"] = 0
gfx_b0["type"] = gpu.DESC_STORAGE_BUFFER
gfx_b0["stage"] = gpu.STAGE_VERTEX
gfx_b0["count"] = 1
let gfx_layout = gpu.create_descriptor_layout([gfx_b0])
let gfx_ps = {}
gfx_ps["type"] = gpu.DESC_STORAGE_BUFFER
gfx_ps["count"] = 2
let gfx_pool = gpu.create_descriptor_pool(2, [gfx_ps])
let gfx_desc_a = gpu.allocate_descriptor_set(gfx_pool, gfx_layout)
let gfx_desc_b = gpu.allocate_descriptor_set(gfx_pool, gfx_layout)
gpu.update_descriptor(gfx_desc_a, 0, gpu.DESC_STORAGE_BUFFER, buf_a)
gpu.update_descriptor(gfx_desc_b, 0, gpu.DESC_STORAGE_BUFFER, buf_b)

let attach = {}
attach["format"] = gpu.FORMAT_SWAPCHAIN
attach["load_op"] = gpu.LOAD_CLEAR
attach["store_op"] = gpu.STORE_STORE
attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
attach["final_layout"] = gpu.LAYOUT_PRESENT
let rp = gpu.create_render_pass([attach])

let gfx_pipe_layout = gpu.create_pipeline_layout([gfx_layout], 64, gpu.STAGE_VERTEX)
let gfx_cfg = {}
gfx_cfg["layout"] = gfx_pipe_layout
gfx_cfg["render_pass"] = rp
gfx_cfg["vertex_shader"] = star_vert
gfx_cfg["fragment_shader"] = star_frag
gfx_cfg["topology"] = gpu.TOPO_POINT_LIST
gfx_cfg["cull_mode"] = gpu.CULL_NONE
gfx_cfg["blend"] = true
let gfx_pipeline = gpu.create_graphics_pipeline(gfx_cfg)

let framebuffers = gpu.create_swapchain_framebuffers(rp)
let ext = gpu.swapchain_extent()

let cmd_pool = gpu.create_command_pool()
let cmd_bufs = []
let ci = 0
while ci < len(framebuffers):
    push(cmd_bufs, gpu.create_command_buffer(cmd_pool))
    ci = ci + 1

let max_frames = 2
let img_sems = []
let rdr_sems = []
let fences_arr = []
let fi2 = 0
while fi2 < max_frames:
    push(img_sems, gpu.create_semaphore())
    push(rdr_sems, gpu.create_semaphore())
    push(fences_arr, gpu.create_fence(true))
    fi2 = fi2 + 1

# Camera orbit
from graphics.math3d import mat4_perspective, mat4_look_at, mat4_mul, vec3, radians

let proj = mat4_perspective(radians(60.0), ext["width"] / ext["height"], 0.1, 200.0)

let frame = 0
let last_time = clock()
let ping = 0
let start_time = clock()
print "Simulating galaxy... (close window to exit)"

while gpu.window_should_close() == false:
    gpu.poll_events()
    gpu.update_input()

    let cf = frame % max_frames
    gpu.wait_fence(fences_arr[cf])
    gpu.reset_fence(fences_arr[cf])

    let img_idx = gpu.acquire_next_image(img_sems[cf])
    if img_idx < 0:
        continue

    let now = clock()
    let dt = now - last_time
    if dt > 0.05:
        dt = 0.016
    last_time = now

    let t = now - start_time

    # Orbit camera
    let cam_dist = 25.0
    let cam_x = math.cos(t * 0.15) * cam_dist
    let cam_z = math.sin(t * 0.15) * cam_dist
    let view = mat4_look_at(vec3(cam_x, 10.0, cam_z), vec3(0, 0, 0), vec3(0, 1, 0))
    let vp = mat4_mul(proj, view)

    let cmd = cmd_bufs[img_idx]
    gpu.begin_commands(cmd)

    # Compute: update bodies
    gpu.cmd_bind_compute_pipeline(cmd, comp_pipeline)
    if ping == 0:
        gpu.cmd_bind_descriptor_set(cmd, comp_pipe_layout, 0, desc_ab)
    else:
        gpu.cmd_bind_descriptor_set(cmd, comp_pipe_layout, 0, desc_ba)
    gpu.cmd_push_constants(cmd, comp_pipe_layout, gpu.STAGE_COMPUTE, [dt, 0.1, 0.5, BODY_COUNT])
    gpu.cmd_dispatch(cmd, BODY_COUNT / 256, 1, 1)

    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_VERTEX_SHADER, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_SHADER_READ)

    # Render stars
    gpu.cmd_begin_render_pass(cmd, rp, framebuffers[img_idx], [[0.0, 0.0, 0.01, 1.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, ext["width"], ext["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, ext["width"], ext["height"])
    gpu.cmd_bind_graphics_pipeline(cmd, gfx_pipeline)
    if ping == 0:
        gpu.cmd_bind_descriptor_set(cmd, gfx_pipe_layout, 0, gfx_desc_b, 0)
    else:
        gpu.cmd_bind_descriptor_set(cmd, gfx_pipe_layout, 0, gfx_desc_a, 0)
    gpu.cmd_push_constants(cmd, gfx_pipe_layout, gpu.STAGE_VERTEX, vp)
    gpu.cmd_draw(cmd, BODY_COUNT, 1, 0, 0)
    gpu.cmd_end_render_pass(cmd)
    gpu.end_commands(cmd)

    gpu.submit_with_sync(cmd, img_sems[cf], rdr_sems[cf], fences_arr[cf])
    gpu.present(img_idx, rdr_sems[cf])

    if ping == 0:
        ping = 1
    else:
        ping = 0
    frame = frame + 1

    # FPS title
    let m = frame - (frame / 60) * 60
    if m == 0:
        let elapsed = clock() - start_time
        if elapsed > 0:
            gpu.set_title("Sage - N-Body Galaxy (" + str(BODY_COUNT) + " bodies) | " + str(frame / elapsed) + " FPS")

gpu.device_wait_idle()
let total = clock() - start_time
print "Rendered " + str(frame) + " frames in " + str(total) + "s"
gpu.shutdown_windowed()
print "Done!"
