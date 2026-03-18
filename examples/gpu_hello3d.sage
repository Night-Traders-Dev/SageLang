# gpu_hello3d.sage - Demo 3: 3D Rotating "HELLO WORLD" Text
# Renders text as line segments that rotate in 3D space
#
# Run: ./sage examples/gpu_hello3d.sage

import gpu

print "=== Sage GPU Demo: 3D Hello World ==="

# Initialize windowed Vulkan context
let ok = gpu.init_windowed("Sage 3D Text", 1024, 600, "Sage - 3D Hello World", false)
if ok == false:
    print "Failed to initialize GPU"
    raise "GPU init failed"

print "GPU: " + gpu.device_name()

# ============================================================================
# Build "HELLO WORLD" as line segments
# Each character is drawn as line segments in a grid.
# Coordinates: each char fits in a 0.0-1.0 box, spacing = 1.2
# ============================================================================

# Helper: add a line segment (2 vertices: x1,y1, x2,y2)
let verts = []

proc add_line(x1, y1, x2, y2):
    push(verts, x1)
    push(verts, y1)
    push(verts, x2)
    push(verts, y2)

proc draw_char(ch, ox, oy):
    let s = 0.7
    if ch == "H":
        add_line(ox, oy, ox, oy + s)
        add_line(ox + s * 0.6, oy, ox + s * 0.6, oy + s)
        add_line(ox, oy + s * 0.5, ox + s * 0.6, oy + s * 0.5)
    if ch == "E":
        add_line(ox, oy, ox, oy + s)
        add_line(ox, oy + s, ox + s * 0.5, oy + s)
        add_line(ox, oy + s * 0.5, ox + s * 0.4, oy + s * 0.5)
        add_line(ox, oy, ox + s * 0.5, oy)
    if ch == "L":
        add_line(ox, oy, ox, oy + s)
        add_line(ox, oy, ox + s * 0.5, oy)
    if ch == "O":
        add_line(ox, oy, ox + s * 0.6, oy)
        add_line(ox + s * 0.6, oy, ox + s * 0.6, oy + s)
        add_line(ox + s * 0.6, oy + s, ox, oy + s)
        add_line(ox, oy + s, ox, oy)
    if ch == "W":
        add_line(ox, oy + s, ox + s * 0.15, oy)
        add_line(ox + s * 0.15, oy, ox + s * 0.3, oy + s * 0.5)
        add_line(ox + s * 0.3, oy + s * 0.5, ox + s * 0.45, oy)
        add_line(ox + s * 0.45, oy, ox + s * 0.6, oy + s)
    if ch == "R":
        add_line(ox, oy, ox, oy + s)
        add_line(ox, oy + s, ox + s * 0.5, oy + s)
        add_line(ox + s * 0.5, oy + s, ox + s * 0.5, oy + s * 0.5)
        add_line(ox + s * 0.5, oy + s * 0.5, ox, oy + s * 0.5)
        add_line(ox, oy + s * 0.5, ox + s * 0.5, oy)
    if ch == "D":
        add_line(ox, oy, ox, oy + s)
        add_line(ox, oy + s, ox + s * 0.4, oy + s)
        add_line(ox + s * 0.4, oy + s, ox + s * 0.6, oy + s * 0.5)
        add_line(ox + s * 0.6, oy + s * 0.5, ox + s * 0.4, oy)
        add_line(ox + s * 0.4, oy, ox, oy)

# Build the text "HELLO WORLD" centered
let text = "HELLOWORLD"
let spacing = 0.55
let total_w = len(text) * spacing
let start_x = 0 - total_w / 2
let cy = -0.06

let ci = 0
while ci < len(text):
    let c = text[ci]
    draw_char(c, start_x + ci * spacing, cy)
    ci = ci + 1

# Add a space gap between HELLO and WORLD by shifting WORLD chars
# (Already handled by the character spacing - 5 chars HELLO, 5 chars WORLD)

let vertex_count = len(verts) / 2
print "Text vertices: " + str(vertex_count) + " (" + str(len(verts) / 4) + " line segments)"

# Upload vertex data to GPU buffer
let vbuf_size = len(verts) * 4
let vbuf = gpu.create_buffer(vbuf_size, gpu.BUFFER_VERTEX | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
gpu.buffer_upload(vbuf, verts)

# Load shaders
let vert_shader = gpu.load_shader("examples/shaders/text3d.vert.spv", gpu.STAGE_VERTEX)
let frag_shader = gpu.load_shader("examples/shaders/text3d.frag.spv", gpu.STAGE_FRAGMENT)
if vert_shader < 0:
    raise "Failed to load text3d vertex shader"
if frag_shader < 0:
    raise "Failed to load text3d fragment shader"
print "Shaders loaded"

# Render pass
let attach = {}
attach["format"] = gpu.FORMAT_SWAPCHAIN
attach["load_op"] = gpu.LOAD_CLEAR
attach["store_op"] = gpu.STORE_STORE
attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
attach["final_layout"] = gpu.LAYOUT_PRESENT
let rp = gpu.create_render_pass([attach])

# Pipeline layout with push constants (time + aspect ratio = 16 bytes)
let pipe_layout = gpu.create_pipeline_layout([], 16, gpu.STAGE_VERTEX)

# Vertex input: vec2 position per vertex
let vb = {}
vb["binding"] = 0
vb["stride"] = 8
vb["rate"] = gpu.INPUT_RATE_VERTEX

let va = {}
va["location"] = 0
va["binding"] = 0
va["format"] = gpu.ATTR_VEC2
va["offset"] = 0

# Graphics pipeline (line list topology)
let pipe_cfg = {}
pipe_cfg["layout"] = pipe_layout
pipe_cfg["render_pass"] = rp
pipe_cfg["vertex_shader"] = vert_shader
pipe_cfg["fragment_shader"] = frag_shader
pipe_cfg["topology"] = gpu.TOPO_LINE_LIST
pipe_cfg["cull_mode"] = gpu.CULL_NONE
pipe_cfg["vertex_bindings"] = [vb]
pipe_cfg["vertex_attribs"] = [va]
let pipeline = gpu.create_graphics_pipeline(pipe_cfg)
if pipeline < 0:
    raise "Failed to create 3D text pipeline"
print "Pipeline created"

# Swapchain framebuffers
let framebuffers = gpu.create_swapchain_framebuffers(rp)
let ext = gpu.swapchain_extent()
let aspect = ext["width"] / ext["height"]

# Command pool and buffers
let cmd_pool = gpu.create_command_pool()
let cmd_bufs = []
let idx = 0
while idx < len(framebuffers):
    push(cmd_bufs, gpu.create_command_buffer(cmd_pool))
    idx = idx + 1

# Per-frame sync
let max_frames = 2
let image_sems = []
let render_sems = []
let fences = []
let fi2 = 0
while fi2 < max_frames:
    push(image_sems, gpu.create_semaphore())
    push(render_sems, gpu.create_semaphore())
    push(fences, gpu.create_fence(true))
    fi2 = fi2 + 1

# Main render loop
let frame = 0
let start_time = clock()
print "Rendering 3D text... (close window to exit)"

while gpu.window_should_close() == false:
    gpu.poll_events()

    let cf = frame % max_frames
    gpu.wait_fence(fences[cf])
    gpu.reset_fence(fences[cf])

    let img_idx = gpu.acquire_next_image(image_sems[cf])
    if img_idx < 0:
        continue

    let cmd = cmd_bufs[img_idx]
    let t = clock() - start_time

    # Record draw commands
    gpu.begin_commands(cmd)
    gpu.cmd_begin_render_pass(cmd, rp, framebuffers[img_idx], [[0.02, 0.02, 0.05, 1.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, ext["width"], ext["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, ext["width"], ext["height"])

    # Bind pipeline and push time/aspect
    gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
    gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_VERTEX, [t, aspect, 0.0, 0.0])

    # Bind vertex buffer and draw all line segments
    gpu.cmd_bind_vertex_buffer(cmd, vbuf)
    gpu.cmd_draw(cmd, vertex_count, 1, 0, 0)

    gpu.cmd_end_render_pass(cmd)
    gpu.end_commands(cmd)

    # Submit and present
    gpu.submit_with_sync(cmd, image_sems[cf], render_sems[cf], fences[cf])
    gpu.present(img_idx, render_sems[cf])

    frame = frame + 1

# Cleanup
gpu.device_wait_idle()
let elapsed = clock() - start_time
print "Rendered " + str(frame) + " frames in " + str(elapsed) + "s"
if elapsed > 0:
    print "Average FPS: " + str(frame / elapsed)
gpu.shutdown_windowed()
print "Done!"
