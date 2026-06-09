gc_disable()
# -----------------------------------------
# pbr.sage - P5: Physically Based Rendering + IBL
# Material definitions for metallic-roughness PBR workflow
# -----------------------------------------

import gpu

# ============================================================================
# PBR Material parameters
# ============================================================================
proc create_pbr_material(albedo, metallic, roughness, ao):
    let mat = {}
    mat["albedo"] = albedo
    mat["metallic"] = metallic
    mat["roughness"] = roughness
    mat["ao"] = ao
    mat["emission"] = [0.0, 0.0, 0.0]
    mat["normal_map"] = -1
    mat["albedo_map"] = -1
    mat["metallic_roughness_map"] = -1
    return mat

# Pack PBR material data for uniform buffer (16 floats = 64 bytes)
proc pack_pbr_material(mat):
    let data = []
    # albedo (vec4 aligned)
    push(data, mat["albedo"][0])
    push(data, mat["albedo"][1])
    push(data, mat["albedo"][2])
    push(data, 1.0)
    # metallic, roughness, ao, pad
    push(data, mat["metallic"])
    push(data, mat["roughness"])
    push(data, mat["ao"])
    push(data, 0.0)
    # emission + pad
    push(data, mat["emission"][0])
    push(data, mat["emission"][1])
    push(data, mat["emission"][2])
    push(data, 0.0)
    # reserved
    push(data, 0.0)
    push(data, 0.0)
    push(data, 0.0)
    push(data, 0.0)
    return data

# ============================================================================
# Light definitions
# ============================================================================
proc create_point_light(position, color, intensity):
    let light = {}
    light["position"] = position
    light["color"] = color
    light["intensity"] = intensity
    light["radius"] = 50.0
    return light

proc create_directional_light(direction, color, intensity):
    let light = {}
    light["direction"] = direction
    light["color"] = color
    light["intensity"] = intensity
    return light

# Pack light data for uniform (12 floats = 48 bytes)
proc pack_point_light(light):
    let data = []
    push(data, light["position"][0])
    push(data, light["position"][1])
    push(data, light["position"][2])
    push(data, light["intensity"])
    push(data, light["color"][0])
    push(data, light["color"][1])
    push(data, light["color"][2])
    push(data, light["radius"])
    return data

# ============================================================================
# IBL (Image-Based Lighting) helpers
# ============================================================================
proc create_ibl_context():
    let ibl = {}
    ibl["irradiance_map"] = -1
    ibl["prefiltered_map"] = -1
    ibl["brdf_lut"] = -1
    return ibl

# Generate BRDF LUT (256x256 RGBA16F)
proc create_brdf_lut():
    return gpu.create_image(256, 256, 1, gpu.FORMAT_RG16F, gpu.IMAGE_STORAGE | gpu.IMAGE_SAMPLED)

# ============================================================================
# Presets
# ============================================================================
proc pbr_gold():
    return create_pbr_material([1.0, 0.765, 0.336], 1.0, 0.3, 1.0)

proc pbr_silver():
    return create_pbr_material([0.972, 0.960, 0.915], 1.0, 0.2, 1.0)

proc pbr_copper():
    return create_pbr_material([0.955, 0.637, 0.538], 1.0, 0.4, 1.0)

proc pbr_plastic_red():
    return create_pbr_material([0.8, 0.1, 0.1], 0.0, 0.5, 1.0)

proc pbr_plastic_white():
    return create_pbr_material([0.9, 0.9, 0.9], 0.0, 0.4, 1.0)

proc pbr_rubber():
    return create_pbr_material([0.05, 0.05, 0.05], 0.0, 0.9, 1.0)

proc pbr_ceramic():
    return create_pbr_material([0.95, 0.95, 0.92], 0.0, 0.15, 1.0)

proc pbr_emissive(color, strength):
    let mat = create_pbr_material(color, 0.0, 0.5, 1.0)
    mat["emission"] = [color[0] * strength, color[1] * strength, color[2] * strength]
    return mat
