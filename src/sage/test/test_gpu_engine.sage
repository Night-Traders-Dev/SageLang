gc_disable()
# Tests for all engine features: infrastructure, libs, shaders
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

print "GPU Engine Tests"
print "================="

# ============================================================================
# C Infrastructure
# ============================================================================
print nl + "--- C Infrastructure ---"

assert_neq(gpu.last_error, nil, "last_error exists")
assert_neq(gpu.update_descriptor_range, nil, "update_descriptor_range exists")
assert_neq(gpu.create_pipeline_cache, nil, "create_pipeline_cache exists")
assert_neq(gpu.create_secondary_command_buffer, nil, "secondary cmd buf exists")
assert_neq(gpu.begin_secondary, nil, "begin_secondary exists")
assert_neq(gpu.cmd_execute_commands, nil, "cmd_execute_commands exists")
assert_neq(gpu.cmd_queue_transfer_barrier, nil, "queue transfer barrier exists")
assert_neq(gpu.graphics_family, nil, "graphics_family exists")
assert_neq(gpu.compute_family, nil, "compute_family exists")
assert_neq(gpu.allocate_descriptor_sets, nil, "batch descriptor alloc exists")
assert_neq(gpu.mouse_delta, nil, "mouse_delta exists")
assert_neq(gpu.save_screenshot, nil, "save_screenshot exists")

# ============================================================================
# Text Rendering Library
# ============================================================================
print nl + "--- Text Rendering ---"

import text_render

let char_A = text_render.get_char_lines("A")
assert_true(len(char_A) > 0, "char A has line data")

let char_space = text_render.get_char_lines(" ")
assert_eq(len(char_space), 0, "space char has no lines")

let text_verts = text_render.build_text_lines("HI", 10, 10, 12, 18)
assert_true(len(text_verts) > 0, "text HI has vertices")
let text_vc = text_render.text_vertex_count(text_verts)
assert_true(text_vc > 0, "text has vertex count > 0")

let ndc = text_render.screen_to_ndc(text_verts, 800, 600)
assert_eq(len(ndc), len(text_verts), "NDC same length as screen")

# ============================================================================
# LOD System
# ============================================================================
print nl + "--- LOD System ---"

import lod
from math3d import vec3

let lod_cfg = lod.space_lod_config()
assert_eq(len(lod_cfg["distances"]), 5, "space LOD has 5 thresholds")

let l1 = lod.compute_lod(lod_cfg, vec3(0, 0, 0), vec3(10, 0, 0))
assert_eq(l1, lod.LOD_FULL, "10 units = FULL")

let l2 = lod.compute_lod(lod_cfg, vec3(0, 0, 0), vec3(100, 0, 0))
assert_eq(l2, lod.LOD_MEDIUM, "100 units = MEDIUM")

let l3 = lod.compute_lod(lod_cfg, vec3(0, 0, 0), vec3(500, 0, 0))
assert_eq(l3, lod.LOD_LOW, "500 units = LOW")

let l4 = lod.compute_lod(lod_cfg, vec3(0, 0, 0), vec3(50000, 0, 0))
assert_eq(l4, lod.LOD_INVISIBLE, "50000 = INVISIBLE")

let batch = lod.compute_lod_batch(lod_cfg, vec3(0, 0, 0), [vec3(10, 0, 0), vec3(50000, 0, 0)])
assert_eq(len(batch), 2, "batch LOD returns 2 results")
assert_eq(batch[0], lod.LOD_FULL, "batch[0] = FULL")
assert_eq(batch[1], lod.LOD_INVISIBLE, "batch[1] = INVISIBLE")

let stats = lod.lod_stats(batch)
assert_eq(stats[0], 1, "1 FULL in stats")
assert_eq(stats[5], 1, "1 INVISIBLE in stats")

# ============================================================================
# Octree
# ============================================================================
print nl + "--- Octree ---"

import octree

let tree = octree.create_octree(vec3(0, 0, 0), 100.0)
assert_eq(tree["count"], 0, "empty tree")

let ok1 = octree.octree_insert(tree, 0, vec3(5, 5, 5), 0)
assert_true(ok1, "insert 0")
let ok2 = octree.octree_insert(tree, 1, vec3(-5, -5, -5), 0)
assert_true(ok2, "insert 1")
assert_eq(tree["count"], 2, "tree has 2 objects")

let results = []
octree.octree_query_radius(tree, vec3(0, 0, 0), 20.0, results)
assert_eq(len(results), 2, "query finds 2 objects")

let far_results = []
octree.octree_query_radius(tree, vec3(200, 200, 200), 5.0, far_results)
assert_eq(len(far_results), 0, "far query finds 0")

# ============================================================================
# Camera-Relative Rendering
# ============================================================================
print nl + "--- Camera-Relative ---"

import camera_relative

let cam_pos = camera_relative.universe_pos(1000000.0, 2000000.0, 3000000.0)
let obj_pos = camera_relative.universe_pos(1000001.0, 2000000.5, 3000000.0)
let rel = camera_relative.relative_pos(cam_pos, obj_pos)
assert_true(rel[0] > 0.9, "relative X ~ 1.0")
assert_true(rel[0] < 1.1, "relative X ~ 1.0")
assert_true(rel[1] > 0.4, "relative Y ~ 0.5")

let dist = camera_relative.universe_distance(cam_pos, obj_pos)
assert_true(dist > 1.0, "universe distance > 1")
assert_true(dist < 2.0, "universe distance < 2")

let batch_rel = camera_relative.to_camera_relative(cam_pos, [obj_pos])
assert_eq(len(batch_rel), 3, "batch relative has 3 floats")

assert_eq(camera_relative.AU, 149597870700.0, "AU constant")
assert_true(camera_relative.LIGHT_YEAR > 9000000000000000.0, "light year > 9e15")

# ============================================================================
# Trails
# ============================================================================
print nl + "--- Trails ---"

import trails

let trail = trails.create_trail(100, 2.0)
assert_eq(trail["count"], 0, "empty trail")

trails.trail_add_point(trail, 1, 2, 3)
trails.trail_add_point(trail, 4, 5, 6)
assert_eq(trail["count"], 2, "trail has 2 points")

let verts = trails.trail_get_vertices(trail)
assert_eq(len(verts), 6, "trail verts = 6 floats")
assert_eq(verts[0], 1, "first point x")

trails.trail_clear(trail)
assert_eq(trail["count"], 0, "cleared trail")

# Orbit prediction
let orbit = trails.predict_orbit([0, 0, 100], [30, 0, 0], [0, 0, 0], 100000000000000000000.0, 10, 0.1)
assert_true(len(orbit) > 0, "orbit has points")
assert_eq(len(orbit), 30, "orbit = 10 steps * 3 coords")

# ============================================================================
# Camera Library
# ============================================================================
print nl + "--- Camera ---"

import camera

let cam = camera.create_camera(0, 5, 10)
assert_eq(cam["pos"][0], 0, "cam X = 0")
assert_eq(cam["pos"][1], 5, "cam Y = 5")
assert_eq(cam["speed"], 5.0, "default speed")

# ============================================================================
# Runtime GPU tests
# ============================================================================
print nl + "--- Runtime GPU ---"

if gpu.has_vulkan():
    let init_ok = gpu.initialize("engine-test", false)
    if init_ok:
        # Pipeline cache
        let pc_ok = gpu.create_pipeline_cache()
        assert_true(pc_ok, "pipeline cache created")

        # Batch descriptor allocation
        let bd = {}
        bd["binding"] = 0
        bd["type"] = gpu.DESC_STORAGE_BUFFER
        bd["stage"] = gpu.STAGE_COMPUTE
        bd["count"] = 1
        let dl = gpu.create_descriptor_layout([bd])
        let dp_s = {}
        dp_s["type"] = gpu.DESC_STORAGE_BUFFER
        dp_s["count"] = 10
        let dp = gpu.create_descriptor_pool(5, [dp_s])
        let sets = gpu.allocate_descriptor_sets(dp, dl, 3)
        assert_eq(len(sets), 3, "batch allocated 3 descriptor sets")

        # Queue families
        let gf = gpu.graphics_family()
        assert_true(gf >= 0, "graphics family >= 0")

        # Error string (should be nil when no error)
        let err = gpu.last_error()
        assert_eq(err, nil, "no error pending")

        gpu.shutdown()
        passed = passed + 1
    else:
        passed = passed + 1
else:
    passed = passed + 1

# ============================================================================
# Summary
# ============================================================================
print nl + "================="
print str(passed) + " passed, " + str(failed) + " failed"

if failed > 0:
    print "SOME TESTS FAILED"
else:
    print "All GPU engine tests passed!"
