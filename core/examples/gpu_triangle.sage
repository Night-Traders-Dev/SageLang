# gpu_triangle.sage - Demo 2: Vulkan Triangle
# Renders a classic colored triangle using vertex/fragment shaders
#
# Run: ./sage examples/gpu_triangle.sage

import gpu

print "=== Sage GPU Demo: Triangle ==="

# Initialize windowed Vulkan context
let ok = gpu.init_windowed("Sage Triangle", 800, 600, "Sage - Vulkan Triangle", false)
if ok == false:
    print "Failed to initialize GPU"
    raise "GPU init failed"

print "GPU: " + gpu.device_name()

# Load shaders (compiled SPIR-V)
let vert = gpu.load_shader("examples/shaders/triangle.vert.spv", gpu.STAGE_VERTEX)
let frag = gpu.load_shader("examples/shaders/triangle.frag.spv", gpu.STAGE_FRAGMENT)
if vert < 0:
    print "Failed to load vertex shader"
    raise "shader load failed"
if frag < 0:
    print "Failed to load fragment shader"
    raise "shader load failed"
print "Shaders loaded"

# Create render pass
let attach = {}
attach["format"] = gpu.FORMAT_SWAPCHAIN
attach["load_op"] = gpu.LOAD_CLEAR
attach["store_op"] = gpu.STORE_STORE
attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
attach["final_layout"] = gpu.LAYOUT_PRESENT
let rp = gpu.create_render_pass([attach])

# Create pipeline layout (no descriptors, no push constants)
let pipe_layout = gpu.create_pipeline_layout([], 0)

# Create graphics pipeline
let pipe_cfg = {}
pipe_cfg["layout"] = pipe_layout
pipe_cfg["render_pass"] = rp
pipe_cfg["vertex_shader"] = vert
pipe_cfg["fragment_shader"] = frag
pipe_cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
pipe_cfg["cull_mode"] = gpu.CULL_NONE
pipe_cfg["front_face"] = gpu.FRONT_CCW
let pipeline = gpu.create_graphics_pipeline(pipe_cfg)
if pipeline < 0:
    print "Failed to create graphics pipeline"
    raise "pipeline creation failed"
print "Pipeline created"

# Create swapchain framebuffers
let framebuffers = gpu.create_swapchain_framebuffers(rp)
let ext = gpu.swapchain_extent()

# Command pool and buffers
let cmd_pool = gpu.create_command_pool()
let cmd_bufs = []
let i = 0
while i < len(framebuffers):
    push(cmd_bufs, gpu.create_command_buffer(cmd_pool))
    i = i + 1

# Per-frame sync objects
let max_frames = 2
let image_sems = []
let render_sems = []
let fences = []
let fi = 0
while fi < max_frames:
    push(image_sems, gpu.create_semaphore())
    push(render_sems, gpu.create_semaphore())
    push(fences, gpu.create_fence(true))
    fi = fi + 1

# Main render loop
let frame = 0
print "Rendering triangle... (close window to exit)"

while gpu.window_should_close() == false:
    gpu.poll_events()

    let cf = frame % max_frames
    gpu.wait_fence(fences[cf])
    gpu.reset_fence(fences[cf])

    let img_idx = gpu.acquire_next_image(image_sems[cf])
    if img_idx < 0:
        continue

    let cmd = cmd_bufs[img_idx]

    # Record draw commands
    gpu.begin_commands(cmd)

    # Begin render pass with dark background
    gpu.cmd_begin_render_pass(cmd, rp, framebuffers[img_idx], [[0.05, 0.05, 0.1, 1.0]])

    # Set viewport and scissor
    gpu.cmd_set_viewport(cmd, 0, 0, ext["width"], ext["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, ext["width"], ext["height"])

    # Bind pipeline and draw triangle (3 vertices, hardcoded in shader)
    gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
    gpu.cmd_draw(cmd, 3, 1, 0, 0)

    gpu.cmd_end_render_pass(cmd)
    gpu.end_commands(cmd)

    # Submit and present
    gpu.submit_with_sync(cmd, image_sems[cf], render_sems[cf], fences[cf])
    gpu.present(img_idx, render_sems[cf])

    frame = frame + 1

# Cleanup
gpu.device_wait_idle()
print "Rendered " + str(frame) + " frames"
gpu.shutdown_windowed()
print "Done!"
