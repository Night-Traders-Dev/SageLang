gc_disable()
# test_screenshots.sage - Render each GPU demo for a few frames, screenshot, exit
# Run from project root: ./sage tests/test_screenshots.sage
#
# Captures PNG screenshots to tests/screenshots/ for visual inspection

import gpu
import math

let passed = 0
let failed = 0
let screenshots = []

proc report(name, ok):
    if ok:
        passed = passed + 1
        print "  [PASS] " + name
    else:
        failed = failed + 1
        print "  [FAIL] " + name

proc render_frames(n):
    let i = 0
    while i < n:
        gpu.poll_events()
        if gpu.window_should_close():
            return false
        i = i + 1
    return true

print "=== GPU Screenshot Tests ==="
print ""

# ============================================================================
# Test 1: Empty Window (cycling color)
# ============================================================================
print "--- Test 1: Empty Window ---"
let ok = gpu.init_windowed("Screenshot Test", 800, 600, "Test: Window", false)
if ok:
    let attach = {}
    attach["format"] = gpu.FORMAT_SWAPCHAIN
    attach["load_op"] = gpu.LOAD_CLEAR
    attach["store_op"] = gpu.STORE_STORE
    attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
    attach["final_layout"] = gpu.LAYOUT_PRESENT
    let rp = gpu.create_render_pass([attach])
    let fbs = gpu.create_swapchain_framebuffers(rp)
    let cp = gpu.create_command_pool()
    let cmd = gpu.create_command_buffer(cp)
    let sem_img = gpu.create_semaphore()
    let sem_rdr = gpu.create_semaphore()
    let fence = gpu.create_fence(true)

    let i = 0
    while i < 30:
        gpu.poll_events()
        gpu.wait_fence(fence)
        gpu.reset_fence(fence)
        let idx = gpu.acquire_next_image(sem_img)
        if idx >= 0:
            gpu.begin_commands(cmd)
            gpu.cmd_begin_render_pass(cmd, rp, fbs[idx], [[0.2, 0.3, 0.5, 1.0]])
            gpu.cmd_end_render_pass(cmd)
            gpu.end_commands(cmd)
            gpu.submit_with_sync(cmd, sem_img, sem_rdr, fence)
            gpu.present(idx, sem_rdr)
        i = i + 1

    gpu.device_wait_idle()
    let s1 = gpu.save_screenshot("tests/screenshots/01_window.png")
    report("window screenshot saved", s1)
    push(screenshots, "01_window.png")
    gpu.shutdown_windowed()
else:
    report("window init", false)

# ============================================================================
# Test 2: Triangle
# ============================================================================
print "--- Test 2: Triangle ---"
ok = gpu.init_windowed("Screenshot Test", 800, 600, "Test: Triangle", false)
if ok:
    let vert = gpu.load_shader("examples/shaders/triangle.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("examples/shaders/triangle.frag.spv", gpu.STAGE_FRAGMENT)
    let attach = {}
    attach["format"] = gpu.FORMAT_SWAPCHAIN
    attach["load_op"] = gpu.LOAD_CLEAR
    attach["store_op"] = gpu.STORE_STORE
    attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
    attach["final_layout"] = gpu.LAYOUT_PRESENT
    let rp = gpu.create_render_pass([attach])
    let layout = gpu.create_pipeline_layout([], 0)
    let cfg = {}
    cfg["layout"] = layout
    cfg["render_pass"] = rp
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_NONE
    let pipeline = gpu.create_graphics_pipeline(cfg)
    report("triangle pipeline", pipeline >= 0)

    let fbs = gpu.create_swapchain_framebuffers(rp)
    let ext = gpu.swapchain_extent()
    let cp = gpu.create_command_pool()
    let cmd = gpu.create_command_buffer(cp)
    let sem_img = gpu.create_semaphore()
    let sem_rdr = gpu.create_semaphore()
    let fence = gpu.create_fence(true)

    let i = 0
    while i < 30:
        gpu.poll_events()
        gpu.wait_fence(fence)
        gpu.reset_fence(fence)
        let idx = gpu.acquire_next_image(sem_img)
        if idx >= 0:
            gpu.begin_commands(cmd)
            gpu.cmd_begin_render_pass(cmd, rp, fbs[idx], [[0.05, 0.05, 0.1, 1.0]])
            gpu.cmd_set_viewport(cmd, 0, 0, ext["width"], ext["height"], 0.0, 1.0)
            gpu.cmd_set_scissor(cmd, 0, 0, ext["width"], ext["height"])
            gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
            gpu.cmd_draw(cmd, 3, 1, 0, 0)
            gpu.cmd_end_render_pass(cmd)
            gpu.end_commands(cmd)
            gpu.submit_with_sync(cmd, sem_img, sem_rdr, fence)
            gpu.present(idx, sem_rdr)
        i = i + 1

    gpu.device_wait_idle()
    let s2 = gpu.save_screenshot("tests/screenshots/02_triangle.png")
    report("triangle screenshot saved", s2)
    push(screenshots, "02_triangle.png")
    gpu.shutdown_windowed()
else:
    report("triangle init", false)

# ============================================================================
# Test 3: 3D Hello World
# ============================================================================
print "--- Test 3: 3D Text ---"
ok = gpu.init_windowed("Screenshot Test", 1024, 600, "Test: 3D Text", false)
if ok:
    # Build text vertices
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

    let text = "HELLO"
    let spacing = 0.55
    let start_x = 0 - len(text) * spacing / 2
    let ci = 0
    while ci < len(text):
        draw_char(text[ci], start_x + ci * spacing, -0.06)
        ci = ci + 1

    let vertex_count = len(verts) / 2
    let vbuf_size = len(verts) * 4
    let vbuf = gpu.create_buffer(vbuf_size, gpu.BUFFER_VERTEX | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
    gpu.buffer_upload(vbuf, verts)

    let vert = gpu.load_shader("examples/shaders/text3d.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("examples/shaders/text3d.frag.spv", gpu.STAGE_FRAGMENT)
    let attach = {}
    attach["format"] = gpu.FORMAT_SWAPCHAIN
    attach["load_op"] = gpu.LOAD_CLEAR
    attach["store_op"] = gpu.STORE_STORE
    attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
    attach["final_layout"] = gpu.LAYOUT_PRESENT
    let rp = gpu.create_render_pass([attach])
    let pipe_layout = gpu.create_pipeline_layout([], 16, gpu.STAGE_VERTEX)
    let vb = {}
    vb["binding"] = 0
    vb["stride"] = 8
    vb["rate"] = gpu.INPUT_RATE_VERTEX
    let va = {}
    va["location"] = 0
    va["binding"] = 0
    va["format"] = gpu.ATTR_VEC2
    va["offset"] = 0
    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = rp
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_LINE_LIST
    cfg["cull_mode"] = gpu.CULL_NONE
    cfg["vertex_bindings"] = [vb]
    cfg["vertex_attribs"] = [va]
    let pipeline = gpu.create_graphics_pipeline(cfg)
    report("3d text pipeline", pipeline >= 0)

    let fbs = gpu.create_swapchain_framebuffers(rp)
    let ext = gpu.swapchain_extent()
    let aspect = ext["width"] / ext["height"]
    let cp = gpu.create_command_pool()
    let cmd = gpu.create_command_buffer(cp)
    let sem_img = gpu.create_semaphore()
    let sem_rdr = gpu.create_semaphore()
    let fence = gpu.create_fence(true)

    let i = 0
    while i < 60:
        gpu.poll_events()
        gpu.wait_fence(fence)
        gpu.reset_fence(fence)
        let idx = gpu.acquire_next_image(sem_img)
        if idx >= 0:
            let t = i * 0.008
            gpu.begin_commands(cmd)
            gpu.cmd_begin_render_pass(cmd, rp, fbs[idx], [[0.02, 0.02, 0.05, 1.0]])
            gpu.cmd_set_viewport(cmd, 0, 0, ext["width"], ext["height"], 0.0, 1.0)
            gpu.cmd_set_scissor(cmd, 0, 0, ext["width"], ext["height"])
            gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
            gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_VERTEX, [t, aspect, 0.0, 0.0])
            gpu.cmd_bind_vertex_buffer(cmd, vbuf)
            gpu.cmd_draw(cmd, vertex_count, 1, 0, 0)
            gpu.cmd_end_render_pass(cmd)
            gpu.end_commands(cmd)
            gpu.submit_with_sync(cmd, sem_img, sem_rdr, fence)
            gpu.present(idx, sem_rdr)
        i = i + 1

    gpu.device_wait_idle()
    let s3 = gpu.save_screenshot("tests/screenshots/03_hello3d.png")
    report("3d text screenshot saved", s3)
    push(screenshots, "03_hello3d.png")
    gpu.shutdown_windowed()
else:
    report("3d text init", false)

# ============================================================================
# Test 4: Cube (with depth)
# ============================================================================
print "--- Test 4: Cube ---"
ok = gpu.init_windowed("Screenshot Test", 800, 600, "Test: Cube", false)
if ok:
    from mesh import cube_mesh, upload_mesh, mesh_vertex_binding, mesh_vertex_attribs
    from math3d import mat4_perspective, mat4_rotate_y, mat4_rotate_x, mat4_mul, mat4_translate, radians, pack_mvp

    let ext = gpu.swapchain_extent()
    let depth = gpu.create_depth_buffer(ext["width"], ext["height"])
    report("depth buffer", depth >= 0)

    let ca = {}
    ca["format"] = gpu.FORMAT_SWAPCHAIN
    ca["load_op"] = gpu.LOAD_CLEAR
    ca["store_op"] = gpu.STORE_STORE
    ca["initial_layout"] = gpu.LAYOUT_UNDEFINED
    ca["final_layout"] = gpu.LAYOUT_PRESENT
    let da = {}
    da["format"] = gpu.FORMAT_DEPTH32F
    da["load_op"] = gpu.LOAD_CLEAR
    da["store_op"] = gpu.STORE_DONTCARE
    da["initial_layout"] = gpu.LAYOUT_UNDEFINED
    da["final_layout"] = gpu.LAYOUT_DEPTH_ATTACH
    let rp = gpu.create_render_pass([ca, da])
    let fbs = gpu.create_swapchain_framebuffers_depth(rp, depth)
    report("framebuffers with depth", len(fbs) > 0)

    let vert = gpu.load_shader("examples/shaders/cube.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("examples/shaders/cube.frag.spv", gpu.STAGE_FRAGMENT)
    let pipe_layout = gpu.create_pipeline_layout([], 64, gpu.STAGE_VERTEX)
    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = rp
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_BACK
    cfg["front_face"] = gpu.FRONT_CCW
    cfg["depth_test"] = true
    cfg["depth_write"] = true
    cfg["vertex_bindings"] = [mesh_vertex_binding()]
    cfg["vertex_attribs"] = mesh_vertex_attribs()
    let pipeline = gpu.create_graphics_pipeline(cfg)
    report("cube pipeline", pipeline >= 0)

    let mesh = cube_mesh()
    let gpu_mesh = upload_mesh(mesh)
    report("cube mesh uploaded", gpu_mesh["vbuf"] >= 0)

    let proj = mat4_perspective(radians(60.0), ext["width"] / ext["height"], 0.1, 100.0)
    let cp = gpu.create_command_pool()
    let cmd = gpu.create_command_buffer(cp)
    let sem_img = gpu.create_semaphore()
    let sem_rdr = gpu.create_semaphore()
    let fence = gpu.create_fence(true)

    let i = 0
    while i < 60:
        gpu.poll_events()
        gpu.wait_fence(fence)
        gpu.reset_fence(fence)
        let idx = gpu.acquire_next_image(sem_img)
        if idx >= 0:
            let t = i * 0.03
            let model = mat4_mul(mat4_rotate_y(t * 1.2), mat4_rotate_x(t * 0.7))
            let view = mat4_translate(0.0, -0.3, -3.0)
            let mvp = pack_mvp(model, view, proj)

            gpu.begin_commands(cmd)
            gpu.cmd_begin_render_pass(cmd, rp, fbs[idx], [[0.05, 0.05, 0.1, 1.0], [1.0, 0, 0, 0]])
            gpu.cmd_set_viewport(cmd, 0, 0, ext["width"], ext["height"], 0.0, 1.0)
            gpu.cmd_set_scissor(cmd, 0, 0, ext["width"], ext["height"])
            gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
            gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_VERTEX, mvp)
            gpu.cmd_bind_vertex_buffer(cmd, gpu_mesh["vbuf"])
            gpu.cmd_bind_index_buffer(cmd, gpu_mesh["ibuf"])
            gpu.cmd_draw_indexed(cmd, gpu_mesh["index_count"], 1, 0, 0, 0)
            gpu.cmd_end_render_pass(cmd)
            gpu.end_commands(cmd)
            gpu.submit_with_sync(cmd, sem_img, sem_rdr, fence)
            gpu.present(idx, sem_rdr)
        i = i + 1

    gpu.device_wait_idle()
    let s4 = gpu.save_screenshot("tests/screenshots/04_cube.png")
    report("cube screenshot saved", s4)
    push(screenshots, "04_cube.png")
    gpu.shutdown_windowed()
else:
    report("cube init", false)

# ============================================================================
# Test 5: Planet
# ============================================================================
print "--- Test 5: Planet ---"
ok = gpu.init_windowed("Screenshot Test", 800, 600, "Test: Planet", false)
if ok:
    let vert = gpu.load_shader("examples/shaders/planet.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("examples/shaders/planet.frag.spv", gpu.STAGE_FRAGMENT)
    let attach = {}
    attach["format"] = gpu.FORMAT_SWAPCHAIN
    attach["load_op"] = gpu.LOAD_CLEAR
    attach["store_op"] = gpu.STORE_STORE
    attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
    attach["final_layout"] = gpu.LAYOUT_PRESENT
    let rp = gpu.create_render_pass([attach])
    let pipe_layout = gpu.create_pipeline_layout([], 32, gpu.STAGE_FRAGMENT)
    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = rp
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_NONE
    let pipeline = gpu.create_graphics_pipeline(cfg)
    report("planet pipeline", pipeline >= 0)

    let fbs = gpu.create_swapchain_framebuffers(rp)
    let ext = gpu.swapchain_extent()
    let aspect = ext["width"] / ext["height"]
    let cp = gpu.create_command_pool()
    let cmd = gpu.create_command_buffer(cp)
    let sem_img = gpu.create_semaphore()
    let sem_rdr = gpu.create_semaphore()
    let fence = gpu.create_fence(true)

    let i = 0
    while i < 30:
        gpu.poll_events()
        gpu.wait_fence(fence)
        gpu.reset_fence(fence)
        let idx = gpu.acquire_next_image(sem_img)
        if idx >= 0:
            gpu.begin_commands(cmd)
            gpu.cmd_begin_render_pass(cmd, rp, fbs[idx], [[0.0, 0.0, 0.02, 1.0]])
            gpu.cmd_set_viewport(cmd, 0, 0, ext["width"], ext["height"], 0.0, 1.0)
            gpu.cmd_set_scissor(cmd, 0, 0, ext["width"], ext["height"])
            gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
            gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_FRAGMENT, [2.0, aspect, 0.0, 0.0, 1.0, 0.05, 0.15, 0.0])
            gpu.cmd_draw(cmd, 3, 1, 0, 0)
            gpu.cmd_end_render_pass(cmd)
            gpu.end_commands(cmd)
            gpu.submit_with_sync(cmd, sem_img, sem_rdr, fence)
            gpu.present(idx, sem_rdr)
        i = i + 1

    gpu.device_wait_idle()
    let s5 = gpu.save_screenshot("tests/screenshots/05_planet.png")
    report("planet screenshot saved", s5)
    push(screenshots, "05_planet.png")
    gpu.shutdown_windowed()
else:
    report("planet init", false)

# ============================================================================
# Test 6: N-Body Galaxy
# ============================================================================
print "--- Test 6: N-Body Galaxy ---"
ok = gpu.init_windowed("Screenshot Test", 800, 600, "Test: Galaxy", false)
if ok:
    from math3d import mat4_perspective, mat4_look_at, mat4_mul, vec3, radians

    let BODY_COUNT = 4096
    let init_data = []
    let bi = 0
    while bi < BODY_COUNT:
        let angle = bi * 2.399963
        let r = 2.0 + (bi * 17.31 - (bi * 17.31 / BODY_COUNT) * BODY_COUNT) / BODY_COUNT * 15.0
        let speed = math.sqrt(0.5 / (r + 1.0)) * 3.0
        push(init_data, math.cos(angle) * r)
        push(init_data, (math.sin(bi * 3.7) - 0.5) * 0.3)
        push(init_data, math.sin(angle) * r)
        push(init_data, 0.5 + (bi * 7.13 - (bi * 7.13 / BODY_COUNT) * BODY_COUNT) / BODY_COUNT)
        push(init_data, 0 - math.sin(angle) * speed)
        push(init_data, 0.0)
        push(init_data, math.cos(angle) * speed)
        push(init_data, 0.0)
        bi = bi + 1

    let buf_size = BODY_COUNT * 8 * 4
    let buf_a = gpu.create_buffer(buf_size, gpu.BUFFER_STORAGE | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
    let buf_b = gpu.create_buffer(buf_size, gpu.BUFFER_STORAGE, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
    gpu.buffer_upload(buf_a, init_data)

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
    report("nbody compute pipeline", comp_pipeline >= 0)

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
    report("star render pipeline", gfx_pipeline >= 0)

    let fbs = gpu.create_swapchain_framebuffers(rp)
    let ext = gpu.swapchain_extent()
    let cp = gpu.create_command_pool()
    let cmd = gpu.create_command_buffer(cp)
    let sem_img = gpu.create_semaphore()
    let sem_rdr = gpu.create_semaphore()
    let fence = gpu.create_fence(true)
    let proj = mat4_perspective(radians(60.0), ext["width"] / ext["height"], 0.1, 200.0)
    let view = mat4_look_at(vec3(20, 12, 20), vec3(0, 0, 0), vec3(0, 1, 0))
    let vp = mat4_mul(proj, view)
    let ping = 0

    let i = 0
    while i < 60:
        gpu.poll_events()
        gpu.wait_fence(fence)
        gpu.reset_fence(fence)
        let idx = gpu.acquire_next_image(sem_img)
        if idx >= 0:
            gpu.begin_commands(cmd)
            gpu.cmd_bind_compute_pipeline(cmd, comp_pipeline)
            if ping == 0:
                gpu.cmd_bind_descriptor_set(cmd, comp_pipe_layout, 0, desc_ab)
            else:
                gpu.cmd_bind_descriptor_set(cmd, comp_pipe_layout, 0, desc_ba)
            gpu.cmd_push_constants(cmd, comp_pipe_layout, gpu.STAGE_COMPUTE, [0.016, 0.1, 0.5, BODY_COUNT])
            gpu.cmd_dispatch(cmd, BODY_COUNT / 256, 1, 1)
            gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_VERTEX_SHADER, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_SHADER_READ)

            gpu.cmd_begin_render_pass(cmd, rp, fbs[idx], [[0.0, 0.0, 0.01, 1.0]])
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
            gpu.submit_with_sync(cmd, sem_img, sem_rdr, fence)
            gpu.present(idx, sem_rdr)
            if ping == 0:
                ping = 1
            else:
                ping = 0
        i = i + 1

    gpu.device_wait_idle()
    let s6 = gpu.save_screenshot("tests/screenshots/06_nbody.png")
    report("nbody screenshot saved", s6)
    push(screenshots, "06_nbody.png")
    gpu.shutdown_windowed()
else:
    report("nbody init", false)

# ============================================================================
# Summary
# ============================================================================
print ""
print "=== Screenshot Test Results ==="
print str(passed) + " passed, " + str(failed) + " failed"
print "Screenshots saved:"
let si = 0
while si < len(screenshots):
    print "  tests/screenshots/" + screenshots[si]
    si = si + 1

if failed > 0:
    print "SOME TESTS FAILED"
else:
    print "All screenshot tests passed!"
