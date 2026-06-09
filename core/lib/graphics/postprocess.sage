gc_disable()
# -----------------------------------------
# postprocess.sage - P4: HDR + Tone Mapping + Bloom
# Post-processing pipeline for cinematic rendering
# -----------------------------------------

import gpu

# ============================================================================
# Tone mapping modes
# ============================================================================
let TONEMAP_REINHARD = 0
let TONEMAP_ACES = 1
let TONEMAP_UNCHARTED2 = 2
let TONEMAP_EXPOSURE = 3

# ============================================================================
# Create HDR render target (RGBA16F)
# ============================================================================
proc create_hdr_target(width, height):
    return gpu.create_offscreen_target(width, height, gpu.FORMAT_RGBA16F, true)

# ============================================================================
# Create bloom pipeline components
# ============================================================================
proc create_bloom_chain(width, height, levels):
    let chain = []
    let w = width / 2
    let h = height / 2
    let i = 0
    while i < levels:
        let target = gpu.create_offscreen_target(w, h, gpu.FORMAT_RGBA16F, false)
        push(chain, target)
        w = w / 2
        if w < 1:
            w = 1
        h = h / 2
        if h < 1:
            h = 1
        i = i + 1
    return chain

# ============================================================================
# Post-process context
# ============================================================================
proc create_postprocess(width, height):
    let pp = {}
    pp["width"] = width
    pp["height"] = height
    pp["hdr_target"] = create_hdr_target(width, height)
    pp["bloom_chain"] = create_bloom_chain(width, height, 4)
    pp["tonemap_mode"] = TONEMAP_ACES
    pp["exposure"] = 1.0
    pp["bloom_intensity"] = 0.3
    pp["bloom_threshold"] = 1.0
    return pp

# ============================================================================
# Fullscreen quad (for post-processing passes)
# ============================================================================
proc create_fullscreen_quad():
    # Vertex-less fullscreen triangle (3 verts, computed in shader)
    return 3

# ============================================================================
# Apply tone mapping (returns parameters for shader)
# ============================================================================
proc tonemap_params(pp):
    let params = []
    push(params, pp["exposure"])
    push(params, pp["bloom_intensity"])
    push(params, pp["bloom_threshold"])
    push(params, pp["tonemap_mode"])
    return params
