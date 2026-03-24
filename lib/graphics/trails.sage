gc_disable()
# trails.sage - Particle trails and orbit prediction lines
# Ring-buffer trail rendering for comets, projectiles, orbits

import gpu

# Create a trail renderer
proc create_trail(max_points, width):
    let trail = {}
    trail["max_points"] = max_points
    trail["width"] = width
    trail["points"] = []
    trail["head"] = 0
    trail["count"] = 0
    return trail

# Add a point to the trail
proc trail_add_point(trail, x, y, z):
    if trail["count"] < trail["max_points"]:
        push(trail["points"], x)
        push(trail["points"], y)
        push(trail["points"], z)
        trail["count"] = trail["count"] + 1
    else:
        # Ring buffer: overwrite oldest
        let idx = trail["head"] * 3
        trail["points"][idx] = x
        trail["points"][idx + 1] = y
        trail["points"][idx + 2] = z
        trail["head"] = trail["head"] + 1
        if trail["head"] >= trail["max_points"]:
            trail["head"] = 0

# Get trail as ordered vertex array (oldest to newest)
proc trail_get_vertices(trail):
    if trail["count"] == 0:
        return []
    let result = []
    let start = trail["head"]
    let count = trail["count"]
    let max_p = trail["max_points"]
    let i = 0
    while i < count:
        let idx = start + i
        if idx >= max_p:
            idx = idx - max_p
        let base = idx * 3
        push(result, trail["points"][base])
        push(result, trail["points"][base + 1])
        push(result, trail["points"][base + 2])
        i = i + 1
    return result

# Get trail vertex count
proc trail_vertex_count(trail):
    return trail["count"]

# Clear trail
proc trail_clear(trail):
    trail["points"] = []
    trail["head"] = 0
    trail["count"] = 0

# ============================================================================
# Orbit prediction
# ============================================================================

# Predict orbit points using simple Euler integration
# body: {position: [x,y,z], velocity: [x,y,z], mass: n}
# attractor: {position: [x,y,z], mass: n}
# Returns array of [x,y,z] points
proc predict_orbit(body_pos, body_vel, attractor_pos, attractor_mass, steps, dt):
    import math
    let G = 0.00000000006674
    let points = []
    let px = body_pos[0]
    let py = body_pos[1]
    let pz = body_pos[2]
    let vx = body_vel[0]
    let vy = body_vel[1]
    let vz = body_vel[2]

    let i = 0
    while i < steps:
        push(points, px)
        push(points, py)
        push(points, pz)

        let dx = attractor_pos[0] - px
        let dy = attractor_pos[1] - py
        let dz = attractor_pos[2] - pz
        let dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist < 0.001:
            i = steps
            continue

        let force = G * attractor_mass / (dist * dist)
        let ax = dx / dist * force
        let ay = dy / dist * force
        let az = dz / dist * force

        vx = vx + ax * dt
        vy = vy + ay * dt
        vz = vz + az * dt
        px = px + vx * dt
        py = py + vy * dt
        pz = pz + vz * dt

        i = i + 1

    return points
