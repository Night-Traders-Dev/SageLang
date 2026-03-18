gc_disable()
# camera_relative.sage - Double-precision camera-relative rendering
# Universe-scale positions stored as 64-bit in Sage, converted to
# float32 camera-relative offsets for GPU rendering.

from math3d import vec3, v3_sub, mat4_identity

# Create a universe position (stored as regular Sage numbers = 64-bit floats)
proc universe_pos(x, y, z):
    return [x, y, z]

# Convert universe positions to camera-relative float32 arrays for GPU
# camera: [x, y, z] in universe coordinates (64-bit)
# positions: array of [x, y, z] universe positions
# Returns: flat float array [rx1, ry1, rz1, rx2, ry2, rz2, ...] (32-bit safe)
proc to_camera_relative(camera, positions):
    let result = []
    let cx = camera[0]
    let cy = camera[1]
    let cz = camera[2]
    let i = 0
    while i < len(positions):
        let p = positions[i]
        push(result, p[0] - cx)
        push(result, p[1] - cy)
        push(result, p[2] - cz)
        i = i + 1
    return result

# Convert a single position to camera-relative
proc relative_pos(camera, pos):
    return vec3(pos[0] - camera[0], pos[1] - camera[1], pos[2] - camera[2])

# Distance between two universe positions (full precision)
proc universe_distance(a, b):
    let dx = b[0] - a[0]
    let dy = b[1] - a[1]
    let dz = b[2] - a[2]
    import math
    return math.sqrt(dx * dx + dy * dy + dz * dz)

# Scale factor for display (logarithmic for extreme distances)
proc log_scale(distance, min_scale, max_scale):
    import math
    if distance < 1.0:
        return max_scale
    let log_dist = math.log(distance) / math.log(10)
    let scale = max_scale - (max_scale - min_scale) * log_dist / 20.0
    if scale < min_scale:
        return min_scale
    return scale

# Astronomical unit conversions
let AU = 149597870700.0
let LIGHT_YEAR = 9460730472580800.0
let PARSEC = 30856775814671900.0
let SOLAR_RADIUS = 696340000.0
let EARTH_RADIUS = 6371000.0
