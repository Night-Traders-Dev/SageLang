gc_disable()
# -----------------------------------------
# asset_cache.sage - Feature 14: Asset Cache
# Avoids reloading shaders, textures, and meshes
# -----------------------------------------

import gpu

# Global caches
let shader_cache = {}
let texture_cache = {}
let mesh_cache = {}

# ============================================================================
# Shader cache
# ============================================================================
proc load_shader_cached(path, stage):
    let key = path + ":" + str(stage)
    if dict_has(shader_cache, key):
        return shader_cache[key]
    let handle = gpu.load_shader(path, stage)
    if handle >= 0:
        shader_cache[key] = handle
    return handle

proc shader_cache_count():
    return len(dict_keys(shader_cache))

# ============================================================================
# Texture cache
# ============================================================================
proc load_texture_cached(path):
    if dict_has(texture_cache, path):
        return texture_cache[path]
    let handle = gpu.load_texture(path)
    if handle >= 0:
        texture_cache[path] = handle
    return handle

proc texture_cache_count():
    return len(dict_keys(texture_cache))

# ============================================================================
# Mesh cache (keyed by name)
# ============================================================================
proc cache_mesh(name, mesh_data):
    mesh_cache[name] = mesh_data

proc get_cached_mesh(name):
    if dict_has(mesh_cache, name):
        return mesh_cache[name]
    return nil

proc mesh_cache_count():
    return len(dict_keys(mesh_cache))

# ============================================================================
# Clear all caches
# ============================================================================
proc clear_caches():
    # Note: GPU handles are destroyed by gpu.shutdown()
    shader_cache = {}
    texture_cache = {}
    mesh_cache = {}

# Print cache stats
proc print_cache_stats():
    print "Asset Cache:"
    print "  Shaders:  " + str(shader_cache_count())
    print "  Textures: " + str(texture_cache_count())
    print "  Meshes:   " + str(mesh_cache_count())
