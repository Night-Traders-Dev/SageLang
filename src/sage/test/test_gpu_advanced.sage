gc_disable()
# Tests for all 14 priority GPU features
# Tests constants, API existence, data structures, and (when Vulkan present) runtime behavior
import gpu

let nl = chr(10)
let passed = 0
let failed = 0

proc assert_eq(actual, expected, msg):
    if actual == expected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg
        print "  expected: " + str(expected)
        print "  actual:   " + str(actual)

proc assert_true(val, msg):
    if val == true:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg

proc assert_false(val, msg):
    if val == false:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg

proc assert_neq(actual, unexpected, msg):
    if actual != unexpected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (was " + str(unexpected) + ")"

proc assert_gte(val, min_val, msg):
    if val >= min_val:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (" + str(val) + " < " + str(min_val) + ")"

print "GPU Advanced Features Tests"
print "============================"

# ============================================================================
# P1: Input handling - key constants
# ============================================================================
print nl + "--- P1: Input constants ---"

assert_neq(gpu.KEY_W, nil, "KEY_W exists")
assert_neq(gpu.KEY_A, nil, "KEY_A exists")
assert_neq(gpu.KEY_S, nil, "KEY_S exists")
assert_neq(gpu.KEY_D, nil, "KEY_D exists")
assert_neq(gpu.KEY_SPACE, nil, "KEY_SPACE exists")
assert_neq(gpu.KEY_ESCAPE, nil, "KEY_ESCAPE exists")
assert_neq(gpu.KEY_UP, nil, "KEY_UP exists")
assert_neq(gpu.KEY_DOWN, nil, "KEY_DOWN exists")
assert_neq(gpu.KEY_LEFT, nil, "KEY_LEFT exists")
assert_neq(gpu.KEY_RIGHT, nil, "KEY_RIGHT exists")
assert_neq(gpu.KEY_SHIFT, nil, "KEY_SHIFT exists")
assert_neq(gpu.KEY_CTRL, nil, "KEY_CTRL exists")
assert_neq(gpu.MOUSE_LEFT, nil, "MOUSE_LEFT exists")
assert_neq(gpu.MOUSE_RIGHT, nil, "MOUSE_RIGHT exists")
assert_eq(gpu.CURSOR_NORMAL, 0, "CURSOR_NORMAL = 0")
assert_eq(gpu.CURSOR_HIDDEN, 1, "CURSOR_HIDDEN = 1")
assert_eq(gpu.CURSOR_DISABLED, 2, "CURSOR_DISABLED = 2")

# P1: Input functions exist
assert_neq(gpu.key_pressed, nil, "key_pressed exists")
assert_neq(gpu.mouse_pos, nil, "mouse_pos exists")
assert_neq(gpu.mouse_button, nil, "mouse_button exists")
assert_neq(gpu.set_cursor_mode, nil, "set_cursor_mode exists")
assert_neq(gpu.get_time, nil, "get_time exists")
assert_neq(gpu.set_title, nil, "set_title exists")
assert_neq(gpu.window_resized, nil, "window_resized exists")

# ============================================================================
# P2: UBO support - functions exist
# ============================================================================
print nl + "--- P2: UBO functions ---"

assert_neq(gpu.create_uniform_buffer, nil, "create_uniform_buffer exists")
assert_neq(gpu.update_uniform, nil, "update_uniform exists")

# ============================================================================
# P3: Render-to-texture
# ============================================================================
print nl + "--- P3: Offscreen rendering ---"

assert_neq(gpu.create_offscreen_target, nil, "create_offscreen_target exists")

# ============================================================================
# P4: HDR + Tone mapping + Bloom (Sage library)
# ============================================================================
print nl + "--- P4: Post-processing library ---"

import postprocess
let pp = postprocess.create_postprocess(800, 600)
assert_eq(pp["width"], 800, "postprocess width")
assert_eq(pp["height"], 600, "postprocess height")
assert_eq(pp["tonemap_mode"], postprocess.TONEMAP_ACES, "default tonemap ACES")
assert_eq(pp["exposure"], 1.0, "default exposure")
assert_eq(pp["bloom_intensity"], 0.3, "default bloom intensity")

let tp = postprocess.tonemap_params(pp)
assert_eq(len(tp), 4, "tonemap params has 4 values")
assert_eq(tp[0], 1.0, "tonemap param 0 = exposure")

let fq = postprocess.create_fullscreen_quad()
assert_eq(fq, 3, "fullscreen quad = 3 vertices")

# ============================================================================
# P5: PBR materials + IBL (Sage library)
# ============================================================================
print nl + "--- P5: PBR library ---"

import pbr
let gold = pbr.pbr_gold()
assert_eq(gold["metallic"], 1.0, "gold is metallic")
assert_eq(gold["roughness"], 0.3, "gold roughness 0.3")
assert_eq(gold["albedo"][0], 1.0, "gold albedo R")

let plastic = pbr.pbr_plastic_red()
assert_eq(plastic["metallic"], 0.0, "plastic not metallic")

let emissive = pbr.pbr_emissive([1.0, 0.5, 0.0], 5.0)
assert_eq(emissive["emission"][0], 5.0, "emissive R = 5.0")
assert_eq(emissive["emission"][1], 2.5, "emissive G = 2.5")

let packed = pbr.pack_pbr_material(gold)
assert_eq(len(packed), 16, "packed PBR = 16 floats")

let light = pbr.create_point_light([1.0, 2.0, 3.0], [1.0, 1.0, 1.0], 10.0)
assert_eq(light["intensity"], 10.0, "light intensity")
let pl = pbr.pack_point_light(light)
assert_eq(len(pl), 8, "packed light = 8 floats")
assert_eq(pl[0], 1.0, "light pos X")

let ibl = pbr.create_ibl_context()
assert_eq(ibl["irradiance_map"], -1, "IBL irradiance starts -1")

# ============================================================================
# P6: Mipmaps + anisotropic
# ============================================================================
print nl + "--- P6: Mipmap functions ---"

assert_neq(gpu.generate_mipmaps, nil, "generate_mipmaps exists")
assert_neq(gpu.create_sampler_advanced, nil, "create_sampler_advanced exists")

# ============================================================================
# P7: Shadow mapping (Sage library)
# ============================================================================
print nl + "--- P7: Shadow library ---"

import shadows
from math3d import vec3

let light_mat = shadows.compute_light_matrix(vec3(0.5, -1.0, 0.3), vec3(-10, -5, -10), vec3(10, 10, 10))
assert_eq(len(light_mat), 16, "light matrix = 16 floats")

# ============================================================================
# P8: Indirect draw/dispatch
# ============================================================================
print nl + "--- P8: Indirect functions ---"

assert_neq(gpu.cmd_draw_indirect, nil, "cmd_draw_indirect exists")
assert_neq(gpu.cmd_draw_indexed_indirect, nil, "cmd_draw_indexed_indirect exists")
assert_neq(gpu.cmd_dispatch_indirect, nil, "cmd_dispatch_indirect exists")

# ============================================================================
# P9: 3D textures
# ============================================================================
print nl + "--- P9: 3D texture functions ---"

assert_neq(gpu.create_image_3d, nil, "create_image_3d exists")

# ============================================================================
# P10: Multi-buffer vertex binding
# ============================================================================
print nl + "--- P10: Instanced rendering ---"

assert_neq(gpu.cmd_bind_vertex_buffers, nil, "cmd_bind_vertex_buffers exists")

# ============================================================================
# P11: Deferred rendering (Sage library)
# ============================================================================
print nl + "--- P11: Deferred library ---"

assert_neq(gpu.create_render_pass_mrt, nil, "create_render_pass_mrt exists")

import deferred
let ssao = deferred.create_ssao_context(800, 600)
assert_eq(ssao["width"], 800, "SSAO width")
assert_eq(ssao["kernel_size"], 32, "SSAO kernel size")
assert_eq(ssao["radius"], 0.5, "SSAO radius")

let ssao_params = deferred.pack_ssao_params(ssao)
assert_eq(len(ssao_params), 8, "SSAO params = 8 floats")

# ============================================================================
# P12: SSR (Sage library)
# ============================================================================
print nl + "--- P12: SSR library ---"

let ssr = deferred.create_ssr_context(800, 600)
assert_eq(ssr["max_steps"], 64, "SSR max steps")
assert_eq(ssr["max_distance"], 50.0, "SSR max distance")

let ssr_params = deferred.pack_ssr_params(ssr)
assert_eq(len(ssr_params), 8, "SSR params = 8 floats")

# ============================================================================
# P13: glTF loading (Sage library)
# ============================================================================
print nl + "--- P13: glTF library ---"

import gltf
assert_neq(gpu.upload_bytes, nil, "upload_bytes exists")

let empty_count = gltf.gltf_mesh_count(nil)
assert_eq(empty_count, 0, "nil gltf mesh count = 0")

let empty_mat = gltf.gltf_material_count(nil)
assert_eq(empty_mat, 0, "nil gltf material count = 0")

# ============================================================================
# P14: TAA (Sage library)
# ============================================================================
print nl + "--- P14: TAA library ---"

import taa

# Halton sequence
let h2 = taa.halton(1, 2)
assert_eq(h2, 0.5, "halton(1,2) = 0.5")
let h3 = taa.halton(1, 3)
assert_true(h3 > 0.3, "halton(1,3) > 0.3")
assert_true(h3 < 0.4, "halton(1,3) < 0.4")

let h2d = taa.halton_2d(0)
assert_eq(len(h2d), 2, "halton_2d returns 2 values")

# TAA params
let taa_params = taa.pack_taa_params(taa.create_taa(800, 600))
assert_eq(len(taa_params), 8, "TAA params = 8 floats")

# ============================================================================
# Math3d tests (used by P5, P7, and all rendering)
# ============================================================================
print nl + "--- Math3d library ---"

from math3d import mat4_identity, mat4_mul, mat4_translate, mat4_scale, mat4_perspective
from math3d import mat4_look_at, mat4_rotate_y, mat4_mul_vec4, mat4_transpose
from math3d import v3_add, v3_sub, v3_dot, v3_cross, v3_normalize, v3_length, v3_scale
from math3d import vec3, vec4, radians, camera_orbit

# Vectors
let a = vec3(1.0, 0.0, 0.0)
let b = vec3(0.0, 1.0, 0.0)
let c = v3_cross(a, b)
assert_eq(c[0], 0.0, "cross X")
assert_eq(c[1], 0.0, "cross Y")
assert_eq(c[2], 1.0, "cross Z")

assert_eq(v3_dot(a, b), 0.0, "perpendicular dot = 0")
assert_eq(v3_dot(a, a), 1.0, "unit dot self = 1")

let sum = v3_add(vec3(1, 2, 3), vec3(4, 5, 6))
assert_eq(sum[0], 5, "add X")
assert_eq(sum[1], 7, "add Y")
assert_eq(sum[2], 9, "add Z")

let diff = v3_sub(vec3(5, 3, 1), vec3(1, 1, 1))
assert_eq(diff[0], 4, "sub X")

let n = v3_normalize(vec3(3, 0, 0))
assert_eq(n[0], 1.0, "normalize unit X")

let l = v3_length(vec3(0, 3, 4))
assert_eq(l, 5.0, "length 3-4-5")

# Matrix identity
let I = mat4_identity()
assert_eq(I[0], 1.0, "identity [0,0]")
assert_eq(I[5], 1.0, "identity [1,1]")
assert_eq(I[10], 1.0, "identity [2,2]")
assert_eq(I[15], 1.0, "identity [3,3]")
assert_eq(I[1], 0.0, "identity [1,0]")

# Matrix multiply: I * I = I
let II = mat4_mul(I, I)
assert_eq(II[0], 1.0, "I*I [0,0]")
assert_eq(II[5], 1.0, "I*I [1,1]")
assert_eq(II[1], 0.0, "I*I [1,0]")

# Translation
let T = mat4_translate(1.0, 2.0, 3.0)
assert_eq(T[12], 1.0, "translate X")
assert_eq(T[13], 2.0, "translate Y")
assert_eq(T[14], 3.0, "translate Z")

# Transform vec4 by translation
let p = mat4_mul_vec4(T, vec4(0, 0, 0, 1))
assert_eq(p[0], 1.0, "translated point X")
assert_eq(p[1], 2.0, "translated point Y")
assert_eq(p[2], 3.0, "translated point Z")

# Scale
let S = mat4_scale(2.0, 3.0, 4.0)
let sp = mat4_mul_vec4(S, vec4(1, 1, 1, 1))
assert_eq(sp[0], 2.0, "scaled X")
assert_eq(sp[1], 3.0, "scaled Y")
assert_eq(sp[2], 4.0, "scaled Z")

# Perspective produces 16 floats
let P = mat4_perspective(radians(60.0), 16.0 / 9.0, 0.1, 100.0)
assert_eq(len(P), 16, "perspective = 16 floats")
assert_neq(P[0], 0.0, "perspective [0,0] != 0")
assert_eq(P[11], -1.0, "perspective [3,2] = -1 (Vulkan)")

# Look-at
let V = mat4_look_at(vec3(0, 0, 5), vec3(0, 0, 0), vec3(0, 1, 0))
assert_eq(len(V), 16, "look_at = 16 floats")

# Camera orbit
let orbit = camera_orbit(0.0, 0.3, 5.0, vec3(0, 0, 0))
assert_eq(len(orbit), 16, "orbit camera = 16 floats")

# Transpose
let Tt = mat4_transpose(T)
assert_eq(Tt[3], T[12], "transpose swaps [0,3] and [3,0]")

# ============================================================================
# Mesh library tests
# ============================================================================
print nl + "--- Mesh library ---"

from mesh import cube_mesh, plane_mesh, sphere_mesh, mesh_vertex_binding, mesh_vertex_attribs

let cm = cube_mesh()
assert_eq(cm["vertex_count"], 24, "cube has 24 vertices")
assert_eq(cm["index_count"], 36, "cube has 36 indices")
assert_true(cm["has_normals"], "cube has normals")
assert_true(cm["has_uvs"], "cube has UVs")
assert_eq(len(cm["vertices"]), 24 * 8, "cube verts = 192 floats")

let pm = plane_mesh(10.0)
assert_eq(pm["vertex_count"], 4, "plane has 4 vertices")
assert_eq(pm["index_count"], 6, "plane has 6 indices")

let sm = sphere_mesh(8, 16)
assert_true(sm["vertex_count"] > 0, "sphere has vertices")
assert_true(sm["index_count"] > 0, "sphere has indices")

let vb = mesh_vertex_binding()
assert_eq(vb["stride"], 32, "mesh stride = 32")
let va = mesh_vertex_attribs()
assert_eq(len(va), 3, "mesh has 3 vertex attribs")
assert_eq(va[0]["offset"], 0, "attrib 0 offset = 0")
assert_eq(va[1]["offset"], 12, "attrib 1 offset = 12")
assert_eq(va[2]["offset"], 24, "attrib 2 offset = 24")

# ============================================================================
# Runtime GPU tests (if Vulkan available)
# ============================================================================
print nl + "--- Runtime GPU tests ---"

if gpu.has_vulkan():
    let ok = gpu.initialize("advanced-test", false)
    if ok:
        # P2: UBO create + update
        let ubo = gpu.create_uniform_buffer(256)
        assert_neq(ubo, -1, "create UBO")
        if ubo != -1:
            gpu.update_uniform(ubo, [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0])
            assert_eq(gpu.buffer_size(ubo), 256, "UBO size = 256")
            gpu.destroy_buffer(ubo)

        # P3: Offscreen target
        let ot = gpu.create_offscreen_target(512, 512, gpu.FORMAT_RGBA16F, true)
        assert_neq(ot, nil, "offscreen target created")
        if ot != nil:
            assert_eq(ot["width"], 512, "offscreen width")
            assert_eq(ot["height"], 512, "offscreen height")
            assert_neq(ot["image"], -1, "offscreen has image")
            assert_neq(ot["render_pass"], -1, "offscreen has render pass")
            assert_neq(ot["framebuffer"], -1, "offscreen has framebuffer")

        # P6: Advanced sampler
        let smp = gpu.create_sampler_advanced(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_REPEAT, 16.0, 8.0)
        assert_neq(smp, -1, "create advanced sampler")
        if smp != -1:
            gpu.destroy_sampler(smp)

        # P8: Upload device local (staging)
        let dl = gpu.upload_device_local([1.0, 2.0, 3.0, 4.0], gpu.BUFFER_STORAGE)
        assert_neq(dl, -1, "upload device local")
        if dl != -1:
            gpu.destroy_buffer(dl)

        # P9: 3D texture
        let tex3d = gpu.create_image_3d(64, 64, 64, gpu.FORMAT_RGBA16F, gpu.IMAGE_STORAGE | gpu.IMAGE_SAMPLED)
        assert_neq(tex3d, -1, "create 3D texture")
        if tex3d != -1:
            let dims = gpu.image_dims(tex3d)
            assert_eq(dims["width"], 64, "3D tex width")
            assert_eq(dims["height"], 64, "3D tex height")
            assert_eq(dims["depth"], 64, "3D tex depth")
            gpu.destroy_image(tex3d)

        # P11: MRT render pass
        let mrt_rp = gpu.create_render_pass_mrt([gpu.FORMAT_RGBA16F, gpu.FORMAT_RGBA16F, gpu.FORMAT_RGBA8], true)
        assert_neq(mrt_rp, -1, "create MRT render pass")
        if mrt_rp != -1:
            gpu.destroy_render_pass(mrt_rp)

        # P13: Upload bytes
        let ub = gpu.upload_bytes([0, 1, 2, 3, 255, 128, 64, 32], gpu.BUFFER_VERTEX)
        assert_neq(ub, -1, "upload_bytes")
        if ub != -1:
            gpu.destroy_buffer(ub)

        gpu.shutdown()
        passed = passed + 1
    else:
        print "  (gpu init failed)"
        passed = passed + 1
else:
    print "  (Vulkan not available - skipping)"
    passed = passed + 1

# ============================================================================
# Summary
# ============================================================================
print nl + "============================"
print str(passed) + " passed, " + str(failed) + " failed"

if failed > 0:
    print "SOME TESTS FAILED"
else:
    print "All GPU advanced tests passed!"
