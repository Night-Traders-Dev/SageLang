gc_disable()
# -----------------------------------------
# taa.sage - P14: Temporal Anti-Aliasing
# Jitter, history buffer, and velocity buffer management
# -----------------------------------------

import gpu
import math

# ============================================================================
# Halton sequence for sub-pixel jitter
# ============================================================================
proc floor_int(x):
    # Sage division is float, so we need to truncate
    if x >= 0:
        return x - (x - (x / 1) * 1)
    return x - (x - (x / 1) * 1) - 1

proc halton(index, base):
    let result = 0.0
    let f = 1.0 / base
    let i = index
    while i > 0:
        let q = math.floor(i / base)
        let rem = i - q * base
        result = result + f * rem
        i = q
        f = f / base
    return result

proc halton_2d(index):
    let x = halton(index + 1, 2) - 0.5
    let y = halton(index + 1, 3) - 0.5
    return [x, y]

# ============================================================================
# TAA context
# ============================================================================
proc create_taa(width, height):
    let taa = {}
    taa["width"] = width
    taa["height"] = height
    taa["frame_index"] = 0
    taa["jitter_scale"] = 1.0

    # History buffer (previous frame result)
    taa["history"] = gpu.create_image(width, height, 1, gpu.FORMAT_RGBA16F, gpu.IMAGE_SAMPLED | gpu.IMAGE_STORAGE | gpu.IMAGE_COLOR_ATTACH)

    # Current frame buffer
    taa["current"] = gpu.create_image(width, height, 1, gpu.FORMAT_RGBA16F, gpu.IMAGE_SAMPLED | gpu.IMAGE_STORAGE | gpu.IMAGE_COLOR_ATTACH)

    # Velocity buffer (motion vectors)
    taa["velocity"] = gpu.create_image(width, height, 1, gpu.FORMAT_RG16F, gpu.IMAGE_COLOR_ATTACH | gpu.IMAGE_SAMPLED)

    # Pre-generate 16 jitter offsets
    taa["jitter_count"] = 16
    taa["jitters"] = []
    let i = 0
    while i < 16:
        push(taa["jitters"], halton_2d(i))
        i = i + 1

    # TAA blend factor
    taa["blend_factor"] = 0.1

    return taa

# ============================================================================
# Get current frame jitter (apply to projection matrix)
# ============================================================================
proc taa_jitter(taa):
    let idx = taa["frame_index"] - (taa["frame_index"] / taa["jitter_count"]) * taa["jitter_count"]
    let j = taa["jitters"][idx]
    let sx = j[0] * taa["jitter_scale"] / taa["width"]
    let sy = j[1] * taa["jitter_scale"] / taa["height"]
    return [sx, sy]

# Apply jitter to projection matrix (modify m[12] and m[13])
proc taa_jitter_projection(proj, taa):
    let j = taa_jitter(taa)
    let result = []
    let i = 0
    while i < 16:
        push(result, proj[i])
        i = i + 1
    result[8] = result[8] + j[0] * 2.0
    result[9] = result[9] + j[1] * 2.0
    return result

# Advance TAA frame
proc taa_advance(taa):
    taa["frame_index"] = taa["frame_index"] + 1
    # Swap history/current
    let tmp = taa["history"]
    taa["history"] = taa["current"]
    taa["current"] = tmp

# Pack TAA params for uniform (8 floats = 32 bytes)
proc pack_taa_params(taa):
    let j = taa_jitter(taa)
    let data = []
    push(data, j[0])
    push(data, j[1])
    push(data, taa["blend_factor"])
    push(data, taa["frame_index"])
    push(data, taa["width"])
    push(data, taa["height"])
    push(data, 0.0)
    push(data, 0.0)
    return data
