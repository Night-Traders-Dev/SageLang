gc_disable()
# -----------------------------------------
# camera.sage - Interactive FPS/Orbit camera
# Uses gpu input system for WASD + mouse look
# -----------------------------------------

import gpu
import math
from graphics.math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_cross, mat4_look_at

# ============================================================================
# Create an interactive camera
# ============================================================================
proc create_camera(pos_x, pos_y, pos_z):
    let cam = {}
    cam["pos"] = vec3(pos_x, pos_y, pos_z)
    cam["yaw"] = -1.5708
    cam["pitch"] = 0.0
    cam["speed"] = 5.0
    cam["sensitivity"] = 0.003
    cam["last_mx"] = 0
    cam["last_my"] = 0
    cam["first_mouse"] = true
    cam["captured"] = false
    return cam

# ============================================================================
# Update camera from input (call once per frame)
# Returns view matrix
# ============================================================================
proc update_camera(cam, dt):
    # Mouse look (only when captured)
    if cam["captured"]:
        let mp = gpu.mouse_pos()
        if mp != nil:
            let mx = mp["x"]
            let my = mp["y"]
            if cam["first_mouse"]:
                cam["last_mx"] = mx
                cam["last_my"] = my
                cam["first_mouse"] = false
            let dx = mx - cam["last_mx"]
            let dy = cam["last_my"] - my
            cam["last_mx"] = mx
            cam["last_my"] = my
            cam["yaw"] = cam["yaw"] + dx * cam["sensitivity"]
            cam["pitch"] = cam["pitch"] + dy * cam["sensitivity"]
            # Clamp pitch
            if cam["pitch"] > 1.5:
                cam["pitch"] = 1.5
            if cam["pitch"] < -1.5:
                cam["pitch"] = -1.5

    # Compute front/right vectors
    let cy = math.cos(cam["yaw"])
    let sy = math.sin(cam["yaw"])
    let cp = math.cos(cam["pitch"])
    let sp = math.sin(cam["pitch"])
    let front = vec3(cy * cp, sp, sy * cp)
    let right = v3_normalize(v3_cross(front, vec3(0.0, 1.0, 0.0)))
    let up = vec3(0.0, 1.0, 0.0)

    # WASD movement
    let move_speed = cam["speed"] * dt
    if gpu.key_pressed(gpu.KEY_W):
        cam["pos"] = v3_add(cam["pos"], v3_scale(front, move_speed))
    if gpu.key_pressed(gpu.KEY_S):
        cam["pos"] = v3_add(cam["pos"], v3_scale(front, 0 - move_speed))
    if gpu.key_pressed(gpu.KEY_A):
        cam["pos"] = v3_add(cam["pos"], v3_scale(right, 0 - move_speed))
    if gpu.key_pressed(gpu.KEY_D):
        cam["pos"] = v3_add(cam["pos"], v3_scale(right, move_speed))
    if gpu.key_pressed(gpu.KEY_SPACE):
        cam["pos"] = v3_add(cam["pos"], v3_scale(up, move_speed))
    if gpu.key_pressed(gpu.KEY_SHIFT):
        cam["pos"] = v3_add(cam["pos"], v3_scale(up, 0 - move_speed))

    # Scroll wheel for speed
    let scroll = gpu.scroll_delta()
    if scroll != nil:
        cam["speed"] = cam["speed"] + scroll["y"] * 0.5
        if cam["speed"] < 0.5:
            cam["speed"] = 0.5
        if cam["speed"] > 100.0:
            cam["speed"] = 100.0

    # Toggle capture with right mouse button
    if gpu.key_just_pressed(gpu.KEY_ESCAPE):
        if cam["captured"]:
            cam["captured"] = false
            gpu.set_cursor_mode(gpu.CURSOR_NORMAL)
        else:
            cam["captured"] = true
            cam["first_mouse"] = true
            gpu.set_cursor_mode(gpu.CURSOR_DISABLED)

    if gpu.mouse_button(gpu.MOUSE_RIGHT):
        if cam["captured"] == false:
            cam["captured"] = true
            cam["first_mouse"] = true
            gpu.set_cursor_mode(gpu.CURSOR_DISABLED)

    # Build view matrix
    let target = v3_add(cam["pos"], front)
    return mat4_look_at(cam["pos"], target, up)

# ============================================================================
# Camera position getter
# ============================================================================
proc camera_position(cam):
    return cam["pos"]
