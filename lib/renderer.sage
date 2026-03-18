gc_disable()
# -----------------------------------------
# renderer.sage - High-level Vulkan render loop for SageLang
# Manages window, depth buffer, render pass, framebuffers, sync, and frame lifecycle
# -----------------------------------------

import gpu

let MAX_FRAMES = 2

# ============================================================================
# Create a renderer context dict
# ============================================================================
proc create_renderer(width, height, title):
    let ok = gpu.init_windowed("SageLang", width, height, title, false)
    if ok == false:
        return nil

    let ext = gpu.swapchain_extent()
    let w = ext["width"]
    let h = ext["height"]

    # Depth buffer
    let depth = gpu.create_depth_buffer(w, h)

    # Render pass with color + depth
    let color_attach = {}
    color_attach["format"] = gpu.FORMAT_SWAPCHAIN
    color_attach["load_op"] = gpu.LOAD_CLEAR
    color_attach["store_op"] = gpu.STORE_STORE
    color_attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
    color_attach["final_layout"] = gpu.LAYOUT_PRESENT

    let depth_attach = {}
    depth_attach["format"] = gpu.FORMAT_DEPTH32F
    depth_attach["load_op"] = gpu.LOAD_CLEAR
    depth_attach["store_op"] = gpu.STORE_DONTCARE
    depth_attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
    depth_attach["final_layout"] = gpu.LAYOUT_DEPTH_ATTACH

    let rp = gpu.create_render_pass([color_attach, depth_attach])

    # Framebuffers (color + depth)
    let framebuffers = gpu.create_swapchain_framebuffers_depth(rp, depth)

    # Command pool and per-image command buffers
    let cmd_pool = gpu.create_command_pool()
    let cmd_bufs = []
    let i = 0
    while i < len(framebuffers):
        push(cmd_bufs, gpu.create_command_buffer(cmd_pool))
        i = i + 1

    # Per-frame sync objects
    let img_sems = []
    let rdr_sems = []
    let fences = []
    let fi = 0
    while fi < MAX_FRAMES:
        push(img_sems, gpu.create_semaphore())
        push(rdr_sems, gpu.create_semaphore())
        push(fences, gpu.create_fence(true))
        fi = fi + 1

    let r = {}
    r["width"] = w
    r["height"] = h
    r["depth_image"] = depth
    r["render_pass"] = rp
    r["framebuffers"] = framebuffers
    r["cmd_pool"] = cmd_pool
    r["cmd_bufs"] = cmd_bufs
    r["img_sems"] = img_sems
    r["rdr_sems"] = rdr_sems
    r["fences"] = fences
    r["frame"] = 0
    r["start_time"] = clock()
    return r

# ============================================================================
# Begin frame - returns dict with cmd, image_index, time, or nil if should close
# ============================================================================
proc begin_frame(r):
    if gpu.window_should_close():
        return nil
    gpu.poll_events()

    let cf = r["frame"] % MAX_FRAMES
    gpu.wait_fence(r["fences"][cf])
    gpu.reset_fence(r["fences"][cf])

    let img_idx = gpu.acquire_next_image(r["img_sems"][cf])
    if img_idx < 0:
        return nil

    let cmd = r["cmd_bufs"][img_idx]
    let t = clock() - r["start_time"]

    gpu.begin_commands(cmd)

    # Default clear: dark blue + depth 1.0
    gpu.cmd_begin_render_pass(cmd, r["render_pass"], r["framebuffers"][img_idx], [[0.02, 0.02, 0.06, 1.0], [1.0, 0.0, 0.0, 0.0]])

    gpu.cmd_set_viewport(cmd, 0, 0, r["width"], r["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, r["width"], r["height"])

    let frame = {}
    frame["cmd"] = cmd
    frame["image_index"] = img_idx
    frame["time"] = t
    frame["current_frame"] = cf
    return frame

# ============================================================================
# End frame - present the rendered image
# ============================================================================
proc end_frame(r, frame):
    let cmd = frame["cmd"]
    let cf = frame["current_frame"]
    let img_idx = frame["image_index"]

    gpu.cmd_end_render_pass(cmd)
    gpu.end_commands(cmd)

    gpu.submit_with_sync(cmd, r["img_sems"][cf], r["rdr_sems"][cf], r["fences"][cf])
    gpu.present(img_idx, r["rdr_sems"][cf])

    r["frame"] = r["frame"] + 1

# ============================================================================
# Shutdown renderer
# ============================================================================
proc shutdown_renderer(r):
    gpu.device_wait_idle()
    let elapsed = clock() - r["start_time"]
    let frames = r["frame"]
    if elapsed > 0:
        print "Rendered " + str(frames) + " frames (" + str(frames / elapsed) + " FPS)"
    gpu.shutdown_windowed()

# ============================================================================
# Convenience: aspect ratio
# ============================================================================
proc aspect_ratio(r):
    return r["width"] / r["height"]
