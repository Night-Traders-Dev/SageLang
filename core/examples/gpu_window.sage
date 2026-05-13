# gpu_window.sage - Demo 1: Empty Vulkan window
# Creates a window and clears it to a cycling color
#
# Run: ./sage examples/gpu_window.sage

import gpu

print "=== Sage GPU Demo: Empty Window ==="

# Initialize windowed Vulkan context
let ok = gpu.init_windowed("Sage Window Demo", 800, 600, "Sage - Empty Window", false)
if ok == false:
    print "Failed to initialize GPU (Vulkan + GLFW required)"
    raise "GPU init failed"

print "GPU: " + gpu.device_name()
let ext = gpu.swapchain_extent()
print "Window: " + str(ext["width"]) + "x" + str(ext["height"])

# Create render pass (single color attachment, clear to color)
let attach = {}
attach["format"] = gpu.FORMAT_SWAPCHAIN
attach["load_op"] = gpu.LOAD_CLEAR
attach["store_op"] = gpu.STORE_STORE
attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
attach["final_layout"] = gpu.LAYOUT_PRESENT
let rp = gpu.create_render_pass([attach])

# Create framebuffers for each swapchain image
let framebuffers = gpu.create_swapchain_framebuffers(rp)
print "Swapchain images: " + str(len(framebuffers))

# Create command pool and buffers (one per swapchain image)
let cmd_pool = gpu.create_command_pool()
let cmd_bufs = []
let i = 0
while i < len(framebuffers):
    push(cmd_bufs, gpu.create_command_buffer(cmd_pool))
    i = i + 1

# Create per-frame sync objects (one set per swapchain image)
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

# Main loop
let frame = 0
print "Rendering... (close window to exit)"

while gpu.window_should_close() == false:
    gpu.poll_events()

    let cf = frame % max_frames

    # Wait for this frame's fence
    gpu.wait_fence(fences[cf])
    gpu.reset_fence(fences[cf])

    # Acquire next swapchain image
    let img_idx = gpu.acquire_next_image(image_sems[cf])
    if img_idx < 0:
        continue

    let cmd = cmd_bufs[img_idx]

    # Cycling clear color
    let t = frame * 0.01
    let r = 0.1 + 0.1 * (1 + (t * 0.7))
    let g = 0.1 + 0.1 * (1 + (t * 1.1))
    let b = 0.2 + 0.1 * (1 + (t * 0.5))
    # Keep values in 0-1 range using modular arithmetic
    r = r - (r / 1) * 1
    if r < 0:
        r = r + 1
    g = g - (g / 1) * 1
    if g < 0:
        g = g + 1
    b = b - (b / 1) * 1
    if b < 0:
        b = b + 1

    # Record commands
    gpu.begin_commands(cmd)
    gpu.cmd_begin_render_pass(cmd, rp, framebuffers[img_idx], [[r, g, b, 1.0]])
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
