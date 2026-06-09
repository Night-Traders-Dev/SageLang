gc_disable()
# -----------------------------------------
# debug_ui.sage - Feature 16: Debug UI Overlay
# Simple text-based debug overlay for GPU applications
# Displays frame stats, custom values, and profiling info
# (Sage-native, no ImGui dependency)
# -----------------------------------------

import gpu

# ============================================================================
# Debug overlay state
# ============================================================================
proc create_debug_ui():
    let ui = {}
    ui["visible"] = true
    ui["entries"] = []
    ui["frame_times"] = []
    ui["max_frame_history"] = 120
    ui["show_fps"] = true
    ui["show_gpu_info"] = true
    ui["custom_values"] = {}
    return ui

# ============================================================================
# Add frame timing
# ============================================================================
proc debug_frame(ui, dt):
    push(ui["frame_times"], dt)
    if len(ui["frame_times"]) > ui["max_frame_history"]:
        # Remove oldest
        let new_times = []
        let i = 1
        while i < len(ui["frame_times"]):
            push(new_times, ui["frame_times"][i])
            i = i + 1
        ui["frame_times"] = new_times

# ============================================================================
# Set custom debug value
# ============================================================================
@inline
proc debug_set(ui, key, value):
    ui["custom_values"][key] = value

# ============================================================================
# Get stats
# ============================================================================
proc debug_fps(ui):
    let times = ui["frame_times"]
    if len(times) == 0:
        return 0
    let total = 0.0
    let i = 0
    while i < len(times):
        total = total + times[i]
        i = i + 1
    let avg = total / len(times)
    if avg < 0.00001:
        return 0
    return 1.0 / avg

@inline
proc debug_frame_time_ms(ui):
    let times = ui["frame_times"]
    if len(times) == 0:
        return 0
    return times[len(times) - 1] * 1000.0

# ============================================================================
# Print debug overlay to console (call each frame or on keypress)
# ============================================================================
proc debug_print(ui):
    if ui["visible"] == false:
        return nil
    let fps = debug_fps(ui)
    let ft = debug_frame_time_ms(ui)
    print "--- Debug ---"
    if ui["show_fps"]:
        print "FPS: " + str(fps) + "  Frame: " + str(ft) + "ms"
    if ui["show_gpu_info"]:
        print "GPU: " + gpu.device_name()
    let keys = dict_keys(ui["custom_values"])
    let i = 0
    while i < len(keys):
        let k = keys[i]
        print "  " + k + ": " + str(ui["custom_values"][k])
        i = i + 1
    print "-------------"

# ============================================================================
# Toggle visibility
# ============================================================================
@inline
proc debug_toggle(ui):
    if ui["visible"]:
        ui["visible"] = false
    else:
        ui["visible"] = true
