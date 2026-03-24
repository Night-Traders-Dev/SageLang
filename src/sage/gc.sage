gc_disable()
# -----------------------------------------
# gc.sage - Concurrent Tri-Color Mark-Sweep GC interface for SageLang
# Port of src/c/gc.c (stats/control API surface)
#
# The actual GC is implemented in C (concurrent tri-color mark-sweep
# with SATB write barriers for sub-millisecond STW pauses).
# This module provides a Sage-level interface for:
#   - Querying GC statistics (including pause timing)
#   - Enabling/disabling collection
#   - Pinning/unpinning (suppress collection during critical sections)
#   - Phase introspection (idle, root_scan, concurrent_mark, remark, sweep)
#   - Debug output
# -----------------------------------------

# -----------------------------------------
# GC configuration constants
# (mirrors GC_MIN_TRIGGER_BYTES / GC_MIN_TRIGGER_OBJECTS from gc.h)
# -----------------------------------------
let MIN_TRIGGER_BYTES = 65536
let MIN_TRIGGER_OBJECTS = 128

# GC phase constants (mirrors gc.h)
let PHASE_IDLE = 0
let PHASE_ROOT_SCAN = 1
let PHASE_CONCURRENT_MARK = 2
let PHASE_REMARK = 3
let PHASE_SWEEP = 4

# Tri-color constants
let COLOR_WHITE = 0
let COLOR_GRAY = 1
let COLOR_BLACK = 2

# -----------------------------------------
# Phase name lookup
# -----------------------------------------
proc phase_name(phase):
    if phase == 0:
        return "idle"
    if phase == 1:
        return "root_scan"
    if phase == 2:
        return "concurrent_mark"
    if phase == 3:
        return "remark"
    if phase == 4:
        return "sweep"
    return "unknown"

# -----------------------------------------
# make_stats - create a GC stats dict
# -----------------------------------------
proc make_stats():
    let s = {}
    s["bytes_allocated"] = 0
    s["current_bytes"] = 0
    s["num_objects"] = 0
    s["collections"] = 0
    s["objects_freed"] = 0
    s["next_gc"] = 0
    s["next_gc_bytes"] = 0
    s["enabled"] = true
    s["pin_count"] = 0
    s["marked_count"] = 0
    s["freed_count"] = 0
    s["phase"] = 0
    s["max_pause_us"] = 0
    s["last_root_scan_us"] = 0
    s["last_remark_us"] = 0
    s["last_sweep_us"] = 0
    s["barrier_active"] = false
    return s

# -----------------------------------------
# stats_to_string - format stats dict as readable string
# -----------------------------------------
proc stats_to_string(stats):
    let nl = chr(10)
    let out = "=== Concurrent GC Statistics ===" + nl
    out = out + "Collections run:        " + str(stats["collections"]) + nl
    out = out + "Objects allocated:      " + str(stats["num_objects"]) + nl
    out = out + "Total bytes allocated:  " + str(stats["bytes_allocated"]) + nl
    out = out + "Current memory usage:   " + str(stats["current_bytes"]) + " bytes" + nl
    out = out + "Marked in last cycle:   " + str(stats["marked_count"]) + nl
    out = out + "Freed in last cycle:    " + str(stats["freed_count"]) + nl
    out = out + "Max STW pause:          " + str(stats["max_pause_us"]) + " us" + nl
    out = out + "Last root scan:         " + str(stats["last_root_scan_us"]) + " us" + nl
    out = out + "Last remark:            " + str(stats["last_remark_us"]) + " us" + nl
    out = out + "Current phase:          " + phase_name(stats["phase"]) + nl
    out = out + "Write barrier active:   "
    if stats["barrier_active"]:
        out = out + "yes"
    else:
        out = out + "no"
    out = out + nl
    out = out + "GC enabled:             "
    if stats["enabled"]:
        out = out + "yes"
    else:
        out = out + "no"
    out = out + nl
    out = out + "=================================" + nl
    return out

# -----------------------------------------
# GCController - manage garbage collection behavior
# -----------------------------------------
class GCController:
    proc init():
        self.is_enabled = false
        self.pin_depth = 0
        self.debug_mode = false
        self.collection_count = 0
        self.total_allocated = 0
        self.total_freed = 0
        self.phase = 0
        self.barrier_active = false
        self.max_pause_us = 0

    proc enable():
        self.is_enabled = true
        if self.debug_mode:
            print "[GC] GC enabled"

    proc disable():
        self.is_enabled = false
        if self.debug_mode:
            print "[GC] GC disabled"

    proc pin():
        self.pin_depth = self.pin_depth + 1

    proc unpin():
        if self.pin_depth > 0:
            self.pin_depth = self.pin_depth - 1

    proc is_pinned():
        return self.pin_depth > 0

    proc should_collect():
        if self.is_enabled == false:
            return false
        if self.pin_depth > 0:
            return false
        if self.phase != 0:
            return false
        return true

    proc enable_debug():
        self.debug_mode = true
        print "[GC] Debug mode enabled"

    proc disable_debug():
        self.debug_mode = false

    proc get_stats():
        let stats = make_stats()
        stats["collections"] = self.collection_count
        stats["bytes_allocated"] = self.total_allocated
        stats["current_bytes"] = self.total_allocated - self.total_freed
        stats["enabled"] = self.is_enabled
        stats["pin_count"] = self.pin_depth
        stats["phase"] = self.phase
        stats["max_pause_us"] = self.max_pause_us
        stats["barrier_active"] = self.barrier_active
        return stats

    proc print_stats():
        let stats = self.get_stats()
        print stats_to_string(stats)

# -----------------------------------------
# Threshold computation (mirrors gc_recompute_thresholds)
# -----------------------------------------
proc compute_thresholds(live_bytes, live_objects, reclaimed_bytes, reclaimed_objects, collection_num):
    let byte_padding = live_bytes / 2
    let object_padding = live_objects / 2
    let min_byte_pad = MIN_TRIGGER_BYTES / 2
    let min_obj_pad = MIN_TRIGGER_OBJECTS / 2
    if byte_padding < min_byte_pad:
        byte_padding = min_byte_pad
    if object_padding < min_obj_pad:
        object_padding = min_obj_pad
    if collection_num == 0:
        byte_padding = MIN_TRIGGER_BYTES
        object_padding = MIN_TRIGGER_OBJECTS
    else:
        if reclaimed_bytes * 8 <= live_bytes:
            byte_padding = byte_padding / 2
            if byte_padding < min_byte_pad:
                byte_padding = min_byte_pad
        if reclaimed_bytes >= live_bytes:
            byte_padding = byte_padding * 2
        if reclaimed_objects * 8 <= live_objects:
            object_padding = object_padding / 2
            if object_padding < min_obj_pad:
                object_padding = min_obj_pad
        if reclaimed_objects >= live_objects:
            object_padding = object_padding * 2
    let next_bytes = live_bytes + byte_padding
    if next_bytes < MIN_TRIGGER_BYTES:
        next_bytes = MIN_TRIGGER_BYTES
    let next_objects = live_objects + object_padding
    if next_objects < MIN_TRIGGER_OBJECTS:
        next_objects = MIN_TRIGGER_OBJECTS
    let result = {}
    result["next_gc_bytes"] = next_bytes
    result["next_gc_objects"] = next_objects
    return result

# -----------------------------------------
# Module-level default controller
# -----------------------------------------
let controller = GCController()
