# gpu_galaxy.sage - Interactive Galaxy with WASD Camera
# N-body simulation with flythrough camera controls
#
# Controls: WASD move, Mouse look (right-click to capture), Scroll = speed, ESC = release
# Run: ./sage examples/gpu_galaxy.sage

import gpu
import math
from graphics.math3d import mat4_perspective, mat4_mul, vec3, radians
from graphics.camera import create_camera, update_camera

print "=== Sage GPU: Interactive Galaxy ==="

let ok = gpu.init_windowed("Sage Galaxy", 1280, 720, "Sage - Interactive Galaxy (WASD + Mouse)", false)
if ok == false:
    raise "GPU init failed"
print "GPU: " + gpu.device_name()

let BODY_COUNT = 8192
let ext = gpu.swapchain_extent()

# Initialize galaxy disk
let init_data = []
let bi = 0
while bi < BODY_COUNT:
    let angle = bi * 2.399963
    let r = 2.0 + (bi * 17.31 - math.floor(bi * 17.31 / BODY_COUNT) * BODY_COUNT) / BODY_COUNT * 18.0
    let speed = math.sqrt(0.5 / (r + 1.0)) * 3.0
    push(init_data, math.cos(angle) * r)
    push(init_data, (math.sin(bi * 3.7) - 0.5) * 0.4)
    push(init_data, math.sin(angle) * r)
    push(init_data, 0.3 + (bi * 7.13 - math.floor(bi * 7.13 / BODY_COUNT) * BODY_COUNT) / BODY_COUNT * 1.2)
    push(init_data, 0 - math.sin(angle) * speed)
    push(init_data, 0.0)
    push(init_data, math.cos(angle) * speed)
    push(init_data, 0.0)
    bi = bi + 1

let buf_size = BODY_COUNT * 8 * 4
let buf_a = gpu.create_buffer(buf_size, gpu.BUFFER_STORAGE | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
let buf_b = gpu.create_buffer(buf_size, gpu.BUFFER_STORAGE, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
gpu.buffer_upload(buf_a, init_data)

# Compute setup
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

# Star rendering
let star_vert = gpu.load_shader("examples/shaders/star.vert.spv", gpu.STAGE_VERTEX)
let star_frag = gpu.load_shader("examples/shaders/star.frag.spv", gpu.STAGE_FRAGMENT)
let gb0 = {}
gb0["binding"] = 0
gb0["type"] = gpu.DESC_STORAGE_BUFFER
gb0["stage"] = gpu.STAGE_VERTEX
gb0["count"] = 1
let gfx_layout = gpu.create_descriptor_layout([gb0])
let gps = {}
gps["type"] = gpu.DESC_STORAGE_BUFFER
gps["count"] = 2
let gfx_pool = gpu.create_descriptor_pool(2, [gps])
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
let gcfg = {}
gcfg["layout"] = gfx_pipe_layout
gcfg["render_pass"] = rp
gcfg["vertex_shader"] = star_vert
gcfg["fragment_shader"] = star_frag
gcfg["topology"] = gpu.TOPO_POINT_LIST
gcfg["cull_mode"] = gpu.CULL_NONE
gcfg["blend"] = true
let gfx_pipeline = gpu.create_graphics_pipeline(gcfg)

let framebuffers = gpu.create_swapchain_framebuffers(rp)
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

# Interactive camera
let cam = create_camera(0.0, 15.0, 30.0)
cam["speed"] = 10.0
let proj = mat4_perspective(radians(60.0), ext["width"] / ext["height"], 0.01, 500.0)

let frame = 0
let last_time = gpu.get_time()
let ping = 0
let start_time = gpu.get_time()
print str(BODY_COUNT) + " stars. WASD + mouse to fly. Right-click to capture mouse."

while gpu.window_should_close() == false:
    gpu.poll_events()
    gpu.update_input()

    let now = gpu.get_time()
    let dt = now - last_time
    if dt > 0.05:
        dt = 0.016
    last_time = now

    # Update camera
    let view = update_camera(cam, dt)
    let vp = mat4_mul(proj, view)

    let cf = frame % max_frames
    gpu.wait_fence(fences_arr[cf])
    gpu.reset_fence(fences_arr[cf])

    let img_idx = gpu.acquire_next_image(img_sems[cf])
    if img_idx < 0:
        continue

    let cmd = cmd_bufs[img_idx]
    gpu.begin_commands(cmd)

    # Compute
    gpu.cmd_bind_compute_pipeline(cmd, comp_pipeline)
    if ping == 0:
        gpu.cmd_bind_descriptor_set(cmd, comp_pipe_layout, 0, desc_ab)
    else:
        gpu.cmd_bind_descriptor_set(cmd, comp_pipe_layout, 0, desc_ba)
    gpu.cmd_push_constants(cmd, comp_pipe_layout, gpu.STAGE_COMPUTE, [dt, 0.1, 0.5, BODY_COUNT])
    gpu.cmd_dispatch(cmd, BODY_COUNT / 256, 1, 1)
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_VERTEX_SHADER, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_SHADER_READ)

    # Render
    gpu.cmd_begin_render_pass(cmd, rp, framebuffers[img_idx], [[0.0, 0.0, 0.005, 1.0]])
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

    let m = frame - math.floor(frame / 60) * 60
    if m == 0:
        let elapsed = gpu.get_time() - start_time
        if elapsed > 0:
            gpu.set_title("Sage Galaxy (" + str(BODY_COUNT) + " stars) | " + str(math.floor(frame / elapsed)) + " FPS")

gpu.device_wait_idle()
gpu.shutdown_windowed()
print "Done!"
