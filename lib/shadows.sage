gc_disable()
# -----------------------------------------
# shadows.sage - P7: Shadow Mapping (Cascaded)
# Shadow map generation and sampling utilities
# -----------------------------------------

import gpu
from math3d import mat4_ortho, mat4_look_at, mat4_mul, vec3, v3_add, v3_scale, v3_negate

# ============================================================================
# Shadow map creation
# ============================================================================
proc create_shadow_map(resolution):
    let img = gpu.create_depth_buffer(resolution, resolution)
    return img

# Create depth-only render pass for shadow pass
proc create_shadow_pass():
    let attach = {}
    attach["format"] = gpu.FORMAT_DEPTH32F
    attach["load_op"] = gpu.LOAD_CLEAR
    attach["store_op"] = gpu.STORE_STORE
    attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
    attach["final_layout"] = gpu.LAYOUT_SHADER_READ
    return gpu.create_render_pass([attach])

# Create shadow framebuffer
proc create_shadow_framebuffer(shadow_pass, shadow_map, resolution):
    return gpu.create_framebuffer(shadow_pass, [shadow_map], resolution, resolution)

# ============================================================================
# Cascade shadow map (up to 4 cascades)
# ============================================================================
proc create_cascade_shadows(resolution, cascade_count):
    let csm = {}
    csm["resolution"] = resolution
    csm["cascade_count"] = cascade_count
    csm["shadow_pass"] = create_shadow_pass()
    csm["maps"] = []
    csm["framebuffers"] = []
    csm["light_matrices"] = []
    csm["split_distances"] = []

    let i = 0
    while i < cascade_count:
        let sm = create_shadow_map(resolution)
        push(csm["maps"], sm)
        push(csm["framebuffers"], create_shadow_framebuffer(csm["shadow_pass"], sm, resolution))
        push(csm["light_matrices"], [])
        i = i + 1

    return csm

# Compute light-space matrix for directional light
proc compute_light_matrix(light_dir, bounds_min, bounds_max):
    let center = vec3((bounds_min[0] + bounds_max[0]) / 2, (bounds_min[1] + bounds_max[1]) / 2, (bounds_min[2] + bounds_max[2]) / 2)
    let half_ext = vec3((bounds_max[0] - bounds_min[0]) / 2, (bounds_max[1] - bounds_min[1]) / 2, (bounds_max[2] - bounds_min[2]) / 2)

    let light_pos = v3_add(center, v3_scale(v3_negate(light_dir), 50.0))
    let view = mat4_look_at(light_pos, center, vec3(0.0, 1.0, 0.0))
    let proj = mat4_ortho(0 - half_ext[0], half_ext[0], 0 - half_ext[1], half_ext[1], 0.1, 100.0)
    return mat4_mul(proj, view)

# Pack shadow data for uniform buffer (mat4 + split distances)
proc pack_shadow_data(csm):
    let data = []
    let i = 0
    while i < csm["cascade_count"]:
        let mat = csm["light_matrices"][i]
        let j = 0
        while j < 16:
            push(data, mat[j])
            j = j + 1
        i = i + 1
    return data
