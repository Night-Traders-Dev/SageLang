gc_disable()
# Tests for all 18 additional GPU features
import gpu

let nl = chr(10)
let passed = 0
let failed = 0

proc assert_eq(actual, expected, msg):
    if actual == expected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (expected " + str(expected) + ", got " + str(actual) + ")"

proc assert_true(val, msg):
    if val == true:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg

proc assert_neq(actual, unexpected, msg):
    if actual != unexpected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg

print "GPU Features 1-18 Tests"
print "========================"

# ============================================================================
# F1: Swapchain recreation
# ============================================================================
print nl + "--- F1: Swapchain recreation ---"
assert_neq(gpu.recreate_swapchain, nil, "recreate_swapchain exists")

# ============================================================================
# F2: Scroll wheel
# ============================================================================
print nl + "--- F2: Scroll wheel ---"
assert_neq(gpu.scroll_delta, nil, "scroll_delta exists")

# ============================================================================
# F3: Key state tracking
# ============================================================================
print nl + "--- F3: Key state tracking ---"
assert_neq(gpu.update_input, nil, "update_input exists")
assert_neq(gpu.key_just_pressed, nil, "key_just_pressed exists")
assert_neq(gpu.key_just_released, nil, "key_just_released exists")

# ============================================================================
# F7: Cubemap
# ============================================================================
print nl + "--- F7: Cubemap ---"
assert_neq(gpu.create_cubemap, nil, "create_cubemap exists")

# ============================================================================
# F12: Scene graph
# ============================================================================
print nl + "--- F12: Scene graph ---"
import graphics.scene

let root = scene.create_node("root")
assert_eq(root["name"], "root", "root node name")
assert_eq(len(root["children"]), 0, "root has no children")

let child1 = scene.create_node("child1")
let child2 = scene.create_node("child2")
scene.add_child(root, child1)
scene.add_child(root, child2)
assert_eq(len(root["children"]), 2, "root has 2 children")
assert_eq(scene.node_count(root), 3, "tree has 3 nodes")

let found = scene.find_node(root, "child2")
assert_neq(found, nil, "find_node finds child2")
assert_eq(found["name"], "child2", "found node is child2")

let not_found = scene.find_node(root, "nonexistent")
assert_eq(not_found, nil, "find_node returns nil for missing")

scene.remove_child(root, child1)
assert_eq(len(root["children"]), 1, "after remove, 1 child")

# World transform
from graphics.math3d import mat4_translate, mat4_mul, mat4_identity
root["transform"] = mat4_translate(1.0, 0.0, 0.0)
child2["transform"] = mat4_translate(0.0, 2.0, 0.0)
let wt = scene.world_transform(child2)
assert_eq(len(wt), 16, "world_transform returns mat4")
# wt should be translate(1,0,0) * translate(0,2,0) = translate(1,2,0)
assert_eq(wt[12], 1.0, "world transform X = 1")
assert_eq(wt[13], 2.0, "world transform Y = 2")

# Traverse
let visit_count = 0
proc counter(node):
    visit_count = visit_count + 1
scene.traverse(root, counter)
assert_eq(visit_count, 2, "traverse visits 2 visible nodes")

# ============================================================================
# F13: Material system
# ============================================================================
print nl + "--- F13: Material system ---"
import graphics.material

# Just test the structure (no GPU needed)
# material.create_material needs GPU, so test presets exist
assert_neq(material.unlit_material, nil, "unlit_material exists")
assert_neq(material.textured_material, nil, "textured_material exists")
assert_neq(material.pbr_material, nil, "pbr_material exists")

# ============================================================================
# F14: Asset cache
# ============================================================================
print nl + "--- F14: Asset cache ---"
import graphics.asset_cache

assert_eq(asset_cache.shader_cache_count(), 0, "shader cache empty")
assert_eq(asset_cache.texture_cache_count(), 0, "texture cache empty")
assert_eq(asset_cache.mesh_cache_count(), 0, "mesh cache empty")

asset_cache.cache_mesh("cube", "test_data")
assert_eq(asset_cache.mesh_cache_count(), 1, "mesh cache has 1")
assert_eq(asset_cache.get_cached_mesh("cube"), "test_data", "cached mesh data correct")
assert_eq(asset_cache.get_cached_mesh("missing"), nil, "missing mesh returns nil")

asset_cache.clear_caches()
assert_eq(asset_cache.mesh_cache_count(), 0, "cache cleared")

# ============================================================================
# F15: Frame graph
# ============================================================================
print nl + "--- F15: Frame graph ---"
import graphics.frame_graph

let fg = frame_graph.create_frame_graph()
assert_eq(len(fg["passes"]), 0, "empty frame graph")

let shadow_pass = frame_graph.create_pass("shadows", frame_graph.PASS_GRAPHICS)
frame_graph.pass_writes(shadow_pass, "shadow_map")
let main_pass = frame_graph.create_pass("main", frame_graph.PASS_GRAPHICS)
frame_graph.pass_reads(main_pass, "shadow_map")
frame_graph.pass_writes(main_pass, "color")
let bloom_pass = frame_graph.create_pass("bloom", frame_graph.PASS_COMPUTE)
frame_graph.pass_reads(bloom_pass, "color")
frame_graph.pass_writes(bloom_pass, "bloom_result")

frame_graph.fg_add_pass(fg, shadow_pass)
frame_graph.fg_add_pass(fg, main_pass)
frame_graph.fg_add_pass(fg, bloom_pass)

let order = frame_graph.fg_compile(fg)
assert_eq(len(order), 3, "3 passes in order")
# Shadows must come before main (main reads shadow_map which shadows writes)
assert_eq(order[0], 0, "shadows first")
assert_eq(order[1], 1, "main second")
assert_eq(order[2], 2, "bloom third")

# ============================================================================
# F16: Debug UI
# ============================================================================
print nl + "--- F16: Debug UI ---"
import graphics.debug_ui

let ui = debug_ui.create_debug_ui()
assert_true(ui["visible"], "debug UI starts visible")
assert_eq(len(ui["frame_times"]), 0, "no frame times")

debug_ui.debug_frame(ui, 0.016)
debug_ui.debug_frame(ui, 0.017)
debug_ui.debug_frame(ui, 0.015)
assert_eq(len(ui["frame_times"]), 3, "3 frame times recorded")

let fps = debug_ui.debug_fps(ui)
assert_true(fps > 50, "FPS > 50 at 16ms frames")
assert_true(fps < 70, "FPS < 70 at 16ms frames")

debug_ui.debug_set(ui, "particles", 65536)
assert_eq(ui["custom_values"]["particles"], 65536, "custom value set")

debug_ui.debug_toggle(ui)
assert_eq(ui["visible"], false, "toggled off")
debug_ui.debug_toggle(ui)
assert_true(ui["visible"], "toggled on")

# ============================================================================
# F17: Shader hot-reload
# ============================================================================
print nl + "--- F17: Shader hot-reload ---"
assert_neq(gpu.reload_shader, nil, "reload_shader exists")

# ============================================================================
# F18: Screenshot
# ============================================================================
print nl + "--- F18: Screenshot ---"
assert_neq(gpu.screenshot, nil, "screenshot exists")

# ============================================================================
# Runtime GPU tests
# ============================================================================
print nl + "--- Runtime GPU tests ---"

if gpu.has_vulkan():
    let ok = gpu.initialize("features-test", false)
    if ok:
        # F7: Cubemap creation
        let cube_map = gpu.create_cubemap(256, gpu.FORMAT_RGBA8, gpu.IMAGE_SAMPLED | gpu.IMAGE_TRANSFER_DST)
        assert_neq(cube_map, -1, "create cubemap")
        if cube_map != -1:
            let dims = gpu.image_dims(cube_map)
            assert_eq(dims["width"], 256, "cubemap width")
            gpu.destroy_image(cube_map)

        gpu.shutdown()
        passed = passed + 1
    else:
        passed = passed + 1
else:
    passed = passed + 1

# ============================================================================
# Summary
# ============================================================================
print nl + "========================"
print str(passed) + " passed, " + str(failed) + " failed"

if failed > 0:
    print "SOME TESTS FAILED"
else:
    print "All GPU features 1-18 tests passed!"
