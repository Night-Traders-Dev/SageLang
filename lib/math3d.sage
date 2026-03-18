gc_disable()
# -----------------------------------------
# math3d.sage - 3D Mathematics Library for SageLang
# Vectors, matrices, camera, and projection utilities
# All matrices are column-major flat arrays of 16 floats (matching GLSL/Vulkan)
# -----------------------------------------

import math

let PI = 3.14159265358979323846

proc radians(deg):
    return deg * PI / 180.0

proc degrees(rad):
    return rad * 180.0 / PI

# ============================================================================
# Vector constructors
# ============================================================================
proc vec2(x, y):
    return [x, y]

proc vec3(x, y, z):
    return [x, y, z]

proc vec4(x, y, z, w):
    return [x, y, z, w]

# ============================================================================
# Vec3 operations
# ============================================================================
proc v3_add(a, b):
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]

proc v3_sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]

proc v3_scale(v, s):
    return [v[0] * s, v[1] * s, v[2] * s]

proc v3_negate(v):
    return [0 - v[0], 0 - v[1], 0 - v[2]]

proc v3_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

proc v3_cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

proc v3_length(v):
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])

proc v3_normalize(v):
    let l = v3_length(v)
    if l < 0.000001:
        return [0.0, 0.0, 0.0]
    return [v[0] / l, v[1] / l, v[2] / l]

proc v3_lerp(a, b, t):
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]

proc v3_distance(a, b):
    return v3_length(v3_sub(b, a))

# ============================================================================
# Vec4 operations
# ============================================================================
proc v4_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]

# ============================================================================
# Mat4 constructors (column-major flat array)
# Index: col * 4 + row
# ============================================================================
proc mat4_zero():
    return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

proc mat4_identity():
    return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]

# Access: m[col*4 + row]
proc mat4_get(m, row, col):
    return m[col * 4 + row]

proc mat4_set(m, row, col, val):
    m[col * 4 + row] = val

# ============================================================================
# Mat4 operations
# ============================================================================
proc mat4_mul(a, b):
    let r = mat4_zero()
    let i = 0
    while i < 4:
        let j = 0
        while j < 4:
            let sum = 0.0
            let k = 0
            while k < 4:
                sum = sum + a[k * 4 + i] * b[j * 4 + k]
                k = k + 1
            r[j * 4 + i] = sum
            j = j + 1
        i = i + 1
    return r

proc mat4_mul_vec4(m, v):
    let x = m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12] * v[3]
    let y = m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13] * v[3]
    let z = m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14] * v[3]
    let w = m[3] * v[0] + m[7] * v[1] + m[11] * v[2] + m[15] * v[3]
    return [x, y, z, w]

# ============================================================================
# Transform matrices
# ============================================================================
proc mat4_translate(tx, ty, tz):
    let m = mat4_identity()
    m[12] = tx
    m[13] = ty
    m[14] = tz
    return m

proc mat4_scale(sx, sy, sz):
    let m = mat4_zero()
    m[0] = sx
    m[5] = sy
    m[10] = sz
    m[15] = 1.0
    return m

proc mat4_rotate_x(angle):
    let c = math.cos(angle)
    let s = math.sin(angle)
    let m = mat4_identity()
    m[5] = c
    m[6] = s
    m[9] = 0.0 - s
    m[10] = c
    return m

proc mat4_rotate_y(angle):
    let c = math.cos(angle)
    let s = math.sin(angle)
    let m = mat4_identity()
    m[0] = c
    m[2] = 0.0 - s
    m[8] = s
    m[10] = c
    return m

proc mat4_rotate_z(angle):
    let c = math.cos(angle)
    let s = math.sin(angle)
    let m = mat4_identity()
    m[0] = c
    m[1] = s
    m[4] = 0.0 - s
    m[5] = c
    return m

# ============================================================================
# Projection matrices (Vulkan: Y-flip, depth 0-1)
# ============================================================================
proc mat4_perspective(fov_y, aspect, near, far):
    let f = 1.0 / math.tan(fov_y / 2.0)
    let m = mat4_zero()
    m[0] = f / aspect
    m[5] = 0.0 - f
    m[10] = far / (near - far)
    m[11] = -1.0
    m[14] = (near * far) / (near - far)
    return m

proc mat4_ortho(left, right, bottom, top, near, far):
    let m = mat4_zero()
    m[0] = 2.0 / (right - left)
    m[5] = 2.0 / (top - bottom)
    m[10] = -1.0 / (far - near)
    m[12] = 0.0 - (right + left) / (right - left)
    m[13] = 0.0 - (top + bottom) / (top - bottom)
    m[14] = 0.0 - near / (far - near)
    m[15] = 1.0
    return m

# ============================================================================
# View matrix
# ============================================================================
proc mat4_look_at(eye, center, up):
    let f = v3_normalize(v3_sub(center, eye))
    let s = v3_normalize(v3_cross(f, up))
    let u = v3_cross(s, f)

    let m = mat4_identity()
    m[0] = s[0]
    m[4] = s[1]
    m[8] = s[2]
    m[1] = u[0]
    m[5] = u[1]
    m[9] = u[2]
    m[2] = 0.0 - f[0]
    m[6] = 0.0 - f[1]
    m[10] = 0.0 - f[2]
    m[12] = 0.0 - v3_dot(s, eye)
    m[13] = 0.0 - v3_dot(u, eye)
    m[14] = v3_dot(f, eye)
    return m

# ============================================================================
# Camera helpers
# ============================================================================
proc camera_orbit(angle_x, angle_y, distance, target):
    let cx = math.cos(angle_x)
    let sx = math.sin(angle_x)
    let cy = math.cos(angle_y)
    let sy = math.sin(angle_y)
    let eye = vec3(target[0] + distance * cy * sx, target[1] + distance * sy, target[2] + distance * cy * cx)
    return mat4_look_at(eye, target, vec3(0.0, 1.0, 0.0))

proc camera_fps(pos, yaw, pitch):
    let cy = math.cos(yaw)
    let sy = math.sin(yaw)
    let cp = math.cos(pitch)
    let sp = math.sin(pitch)
    let front = vec3(cy * cp, sp, sy * cp)
    let center = v3_add(pos, front)
    return mat4_look_at(pos, center, vec3(0.0, 1.0, 0.0))

# ============================================================================
# Matrix transpose (for normal matrix)
# ============================================================================
proc mat4_transpose(m):
    let r = mat4_zero()
    let i = 0
    while i < 4:
        let j = 0
        while j < 4:
            r[j * 4 + i] = m[i * 4 + j]
            j = j + 1
        i = i + 1
    return r

# ============================================================================
# To float array (identity — already flat, but useful for documentation)
# ============================================================================
proc mat4_to_floats(m):
    return m

# Push constants helper: pack MVP as 64-byte float array
proc pack_mvp(model, view, proj):
    let mvp = mat4_mul(proj, mat4_mul(view, model))
    return mvp
