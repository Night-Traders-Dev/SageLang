gc_disable()
# -----------------------------------------
# deferred.sage - P11: Deferred Rendering (G-Buffer)
# + P12: SSAO + SSR screen-space effects
# G-buffer management and deferred lighting pass
# -----------------------------------------

import gpu

# ============================================================================
# G-Buffer creation (Position, Normal, Albedo+Metallic, Emission+Roughness)
# ============================================================================
proc create_gbuffer(width, height):
    let gb = {}
    gb["width"] = width
    gb["height"] = height

    # 4 color attachments + depth
    # 0: Position (RGBA16F) - world position + depth
    # 1: Normal (RGBA16F) - world normal + metallic
    # 2: Albedo (RGBA8) - albedo.rgb + roughness
    # 3: Emission (RGBA16F) - emission.rgb + ao

    let pos_img = gpu.create_image(width, height, 1, gpu.FORMAT_RGBA16F, gpu.IMAGE_COLOR_ATTACH | gpu.IMAGE_SAMPLED)
    let norm_img = gpu.create_image(width, height, 1, gpu.FORMAT_RGBA16F, gpu.IMAGE_COLOR_ATTACH | gpu.IMAGE_SAMPLED)
    let albedo_img = gpu.create_image(width, height, 1, gpu.FORMAT_RGBA8, gpu.IMAGE_COLOR_ATTACH | gpu.IMAGE_SAMPLED)
    let emission_img = gpu.create_image(width, height, 1, gpu.FORMAT_RGBA16F, gpu.IMAGE_COLOR_ATTACH | gpu.IMAGE_SAMPLED)
    let depth_img = gpu.create_depth_buffer(width, height)

    gb["position"] = pos_img
    gb["normal"] = norm_img
    gb["albedo"] = albedo_img
    gb["emission"] = emission_img
    gb["depth"] = depth_img

    # MRT render pass
    let formats = [gpu.FORMAT_RGBA16F, gpu.FORMAT_RGBA16F, gpu.FORMAT_RGBA8, gpu.FORMAT_RGBA16F]
    gb["render_pass"] = gpu.create_render_pass_mrt(formats, true)

    # Framebuffer
    let views = [pos_img, norm_img, albedo_img, emission_img, depth_img]
    gb["framebuffer"] = gpu.create_framebuffer(gb["render_pass"], views, width, height)

    return gb

# ============================================================================
# SSAO parameters
# ============================================================================
proc create_ssao_context(width, height):
    let ssao = {}
    ssao["width"] = width
    ssao["height"] = height
    ssao["target"] = gpu.create_offscreen_target(width, height, gpu.FORMAT_R8, false)
    ssao["blur_target"] = gpu.create_offscreen_target(width, height, gpu.FORMAT_R8, false)
    ssao["kernel_size"] = 32
    ssao["radius"] = 0.5
    ssao["bias"] = 0.025
    ssao["power"] = 2.0

    # Generate SSAO kernel (hemisphere samples)
    let kernel = []
    let i = 0
    while i < 32:
        let scale = i / 32.0
        scale = 0.1 + scale * scale * 0.9
        push(kernel, scale)
        i = i + 1
    ssao["kernel_scales"] = kernel
    return ssao

# ============================================================================
# SSR parameters
# ============================================================================
proc create_ssr_context(width, height):
    let ssr = {}
    ssr["width"] = width
    ssr["height"] = height
    ssr["target"] = gpu.create_offscreen_target(width, height, gpu.FORMAT_RGBA16F, false)
    ssr["max_steps"] = 64
    ssr["max_distance"] = 50.0
    ssr["thickness"] = 0.1
    ssr["stride"] = 2
    return ssr

# Pack SSAO params for uniform (8 floats = 32 bytes)
proc pack_ssao_params(ssao):
    let data = []
    push(data, ssao["radius"])
    push(data, ssao["bias"])
    push(data, ssao["power"])
    push(data, ssao["kernel_size"])
    push(data, ssao["width"])
    push(data, ssao["height"])
    push(data, 0.0)
    push(data, 0.0)
    return data

# Pack SSR params for uniform (8 floats = 32 bytes)
proc pack_ssr_params(ssr):
    let data = []
    push(data, ssr["max_steps"])
    push(data, ssr["max_distance"])
    push(data, ssr["thickness"])
    push(data, ssr["stride"])
    push(data, ssr["width"])
    push(data, ssr["height"])
    push(data, 0.0)
    push(data, 0.0)
    return data
