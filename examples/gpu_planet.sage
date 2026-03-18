# gpu_planet.sage - Demo 4: Planet Raymarching
# Renders a procedural planet with terrain, oceans, and atmosphere
#
# Run: ./sage examples/gpu_planet.sage

import gpu
from math3d import radians

print "=== Sage GPU Demo: Planet ==="

let ok = gpu.init_windowed("Sage Planet", 1024, 768, "Sage - Planet", false)
if ok == false:
    raise "Failed to initialize GPU"
print "GPU: " + gpu.device_name()

# Load shaders (fullscreen quad raymarcher)
let vert = gpu.load_shader("examples/shaders/planet.vert.spv", gpu.STAGE_VERTEX)
let frag = gpu.load_shader("examples/shaders/planet.frag.spv", gpu.STAGE_FRAGMENT)

# Render pass
let attach = {}
attach["format"] = gpu.FORMAT_SWAPCHAIN
attach["load_op"] = gpu.LOAD_CLEAR
attach["store_op"] = gpu.STORE_STORE
attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
attach["final_layout"] = gpu.LAYOUT_PRESENT
let rp = gpu.create_render_pass([attach])

# Pipeline: push constants = time, aspect, mouseX, mouseY, radius, oceanLevel, atmosphere, rotation (32 bytes = 8 floats)
let pipe_layout = gpu.create_pipeline_layout([], 32, gpu.STAGE_FRAGMENT)

let cfg = {}
cfg["layout"] = pipe_layout
cfg["render_pass"] = rp
cfg["vertex_shader"] = vert
cfg["fragment_shader"] = frag
cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
cfg["cull_mode"] = gpu.CULL_NONE
let pipeline = gpu.create_graphics_pipeline(cfg)

let framebuffers = gpu.create_swapchain_framebuffers(rp)
let ext = gpu.swapchain_extent()
let aspect = ext["width"] / ext["height"]

# Sync + commands
let cmd_pool = gpu.create_command_pool()
let cmd_bufs = []
let i = 0
while i < len(framebuffers):
    push(cmd_bufs, gpu.create_command_buffer(cmd_pool))
    i = i + 1

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

let frame = 0
let start_time = clock()
print "Rendering planet... (close window to exit)"

while gpu.window_should_close() == false:
    gpu.poll_events()
    let cf = frame % max_frames
    gpu.wait_fence(fences[cf])
    gpu.reset_fence(fences[cf])

    let img_idx = gpu.acquire_next_image(img_sems[cf])
    if img_idx < 0:
        continue

    let t = clock() - start_time
    let cmd = cmd_bufs[img_idx]

    gpu.begin_commands(cmd)
    gpu.cmd_begin_render_pass(cmd, rp, framebuffers[img_idx], [[0.0, 0.0, 0.02, 1.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, ext["width"], ext["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, ext["width"], ext["height"])

    gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
    # push: time, aspect, mouseX, mouseY, radius, oceanLevel, atmosphereThickness, rotation
    gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_FRAGMENT, [t, aspect, 0.0, 0.0, 1.0, 0.05, 0.15, 0.0])
    gpu.cmd_draw(cmd, 3, 1, 0, 0)

    gpu.cmd_end_render_pass(cmd)
    gpu.end_commands(cmd)

    gpu.submit_with_sync(cmd, img_sems[cf], rdr_sems[cf], fences[cf])
    gpu.present(img_idx, rdr_sems[cf])

    # FPS in title every 60 frames
    if frame > 0:
        let m = frame - (frame / 60) * 60
        if m == 0:
            let elapsed = clock() - start_time
            if elapsed > 0:
                gpu.set_title("Sage - Planet | " + str(frame / elapsed) + " FPS")

    frame = frame + 1

gpu.device_wait_idle()
gpu.shutdown_windowed()
print "Done!"
