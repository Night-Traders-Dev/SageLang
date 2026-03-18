gc_disable()
# lod.sage - Level of Detail system
# Selects mesh/rendering mode based on distance from camera

import math
from math3d import v3_sub, v3_length

# LOD levels
let LOD_FULL = 0
let LOD_MEDIUM = 1
let LOD_LOW = 2
let LOD_BILLBOARD = 3
let LOD_POINT = 4
let LOD_INVISIBLE = 5

# Create LOD configuration
proc create_lod_config(distances):
    # distances: array of distance thresholds [full, medium, low, billboard, point]
    let cfg = {}
    cfg["distances"] = distances
    return cfg

# Default LOD for space objects
proc space_lod_config():
    return create_lod_config([50, 200, 1000, 5000, 20000])

# Determine LOD level from distance
proc compute_lod(config, camera_pos, object_pos):
    let dist = v3_length(v3_sub(object_pos, camera_pos))
    let dists = config["distances"]
    if dist < dists[0]:
        return LOD_FULL
    if dist < dists[1]:
        return LOD_MEDIUM
    if dist < dists[2]:
        return LOD_LOW
    if dist < dists[3]:
        return LOD_BILLBOARD
    if dist < dists[4]:
        return LOD_POINT
    return LOD_INVISIBLE

# Batch LOD for array of positions
proc compute_lod_batch(config, camera_pos, positions):
    let results = []
    let i = 0
    while i < len(positions):
        push(results, compute_lod(config, camera_pos, positions[i]))
        i = i + 1
    return results

# Count objects per LOD level
proc lod_stats(lod_array):
    let counts = [0, 0, 0, 0, 0, 0]
    let i = 0
    while i < len(lod_array):
        let level = lod_array[i]
        if level >= 0:
            if level <= 5:
                counts[level] = counts[level] + 1
        i = i + 1
    return counts
