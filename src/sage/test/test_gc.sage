gc_disable()
# Tests for the self-hosted GC module
import gc

let nl = chr(10)
let passed = 0
let failed = 0

proc assert_eq(actual, expected, msg):
    if actual == expected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg
        print "  expected: " + str(expected)
        print "  actual:   " + str(actual)

proc assert_true(val, msg):
    if val == true:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (expected true, got " + str(val) + ")"

proc assert_false(val, msg):
    if val == false:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (expected false, got " + str(val) + ")"

print "Self-hosted GC Tests"
print "====================="

# ============================================================================
# Constants
# ============================================================================
print nl + "--- Constants ---"

assert_eq(gc.MIN_TRIGGER_BYTES, 65536, "MIN_TRIGGER_BYTES")
assert_eq(gc.MIN_TRIGGER_OBJECTS, 256, "MIN_TRIGGER_OBJECTS")

# ============================================================================
# make_stats
# ============================================================================
print nl + "--- make_stats ---"

let stats = gc.make_stats()
assert_eq(stats["bytes_allocated"], 0, "initial bytes_allocated")
assert_eq(stats["current_bytes"], 0, "initial current_bytes")
assert_eq(stats["num_objects"], 0, "initial num_objects")
assert_eq(stats["collections"], 0, "initial collections")
assert_eq(stats["enabled"], true, "initial enabled")
assert_eq(stats["pin_count"], 0, "initial pin_count")

# stats_to_string
let s = gc.stats_to_string(stats)
assert_eq(type(s), "string", "stats_to_string returns string")
assert_true(contains(s, "Garbage Collector"), "stats string has header")
assert_true(contains(s, "yes"), "stats string shows enabled=yes")

# ============================================================================
# GCController - enable/disable
# ============================================================================
print nl + "--- GCController enable/disable ---"

let ctrl = gc.GCController()
assert_false(ctrl.is_enabled, "controller starts disabled")

ctrl.enable()
assert_true(ctrl.is_enabled, "enable sets is_enabled")

ctrl.disable()
assert_false(ctrl.is_enabled, "disable clears is_enabled")

# ============================================================================
# GCController - pin/unpin
# ============================================================================
print nl + "--- GCController pin/unpin ---"

let ctrl2 = gc.GCController()
ctrl2.enable()
assert_eq(ctrl2.pin_depth, 0, "initial pin_depth 0")
assert_true(ctrl2.should_collect(), "should_collect when enabled, unpinned")

ctrl2.pin()
assert_eq(ctrl2.pin_depth, 1, "pin_depth after pin")
assert_true(ctrl2.is_pinned(), "is_pinned after pin")
assert_false(ctrl2.should_collect(), "should_collect false when pinned")

ctrl2.pin()
assert_eq(ctrl2.pin_depth, 2, "nested pin_depth")

ctrl2.unpin()
assert_eq(ctrl2.pin_depth, 1, "pin_depth after one unpin")
assert_true(ctrl2.is_pinned(), "still pinned after one unpin")

ctrl2.unpin()
assert_eq(ctrl2.pin_depth, 0, "pin_depth after full unpin")
assert_false(ctrl2.is_pinned(), "not pinned after full unpin")
assert_true(ctrl2.should_collect(), "should_collect after full unpin")

# Unpin below zero should stay at 0
ctrl2.unpin()
assert_eq(ctrl2.pin_depth, 0, "pin_depth stays at 0")

# ============================================================================
# GCController - should_collect
# ============================================================================
print nl + "--- GCController should_collect ---"

let ctrl3 = gc.GCController()
assert_false(ctrl3.should_collect(), "disabled controller should not collect")

ctrl3.enable()
assert_true(ctrl3.should_collect(), "enabled controller should collect")

ctrl3.pin()
assert_false(ctrl3.should_collect(), "pinned controller should not collect")

ctrl3.unpin()
ctrl3.disable()
assert_false(ctrl3.should_collect(), "disabled again should not collect")

# ============================================================================
# GCController - get_stats (returns dict)
# ============================================================================
print nl + "--- GCController get_stats ---"

let ctrl4 = gc.GCController()
ctrl4.enable()
ctrl4.collection_count = 5
ctrl4.total_allocated = 1000
ctrl4.total_freed = 300

let st = ctrl4.get_stats()
assert_eq(st["collections"], 5, "stats collections")
assert_eq(st["bytes_allocated"], 1000, "stats bytes_allocated")
assert_eq(st["current_bytes"], 700, "stats current_bytes")
assert_true(st["enabled"], "stats enabled")
assert_eq(st["pin_count"], 0, "stats pin_count")

# ============================================================================
# compute_thresholds
# ============================================================================
print nl + "--- compute_thresholds ---"

# First collection (collection_num == 0)
let t0 = gc.compute_thresholds(1000, 100, 0, 0, 0)
assert_eq(t0["next_gc_bytes"], 1000 + 65536, "first collection byte threshold")
assert_eq(t0["next_gc_objects"], 100 + 256, "first collection object threshold")

# Normal collection, moderate reclamation
let t1 = gc.compute_thresholds(10000, 500, 5000, 250, 1)
assert_true(t1["next_gc_bytes"] >= gc.MIN_TRIGGER_BYTES, "normal threshold >= min bytes")
assert_true(t1["next_gc_objects"] >= gc.MIN_TRIGGER_OBJECTS, "normal threshold >= min objects")

# Low reclamation (should shrink padding)
let t2 = gc.compute_thresholds(80000, 1000, 100, 10, 2)
assert_true(t2["next_gc_bytes"] >= gc.MIN_TRIGGER_BYTES, "low reclaim threshold >= min")

# High reclamation (should grow padding)
let t3 = gc.compute_thresholds(50000, 400, 60000, 500, 3)
assert_true(t3["next_gc_bytes"] > 50000, "high reclaim next > live")

# Very small live data
let t4 = gc.compute_thresholds(100, 10, 50, 5, 1)
assert_true(t4["next_gc_bytes"] >= gc.MIN_TRIGGER_BYTES, "small live meets min bytes")
assert_true(t4["next_gc_objects"] >= gc.MIN_TRIGGER_OBJECTS, "small live meets min objects")

# ============================================================================
# Module-level controller
# ============================================================================
print nl + "--- module controller ---"

assert_false(gc.controller.is_enabled, "module controller starts disabled")
gc.controller.enable()
assert_true(gc.controller.is_enabled, "module controller enabled")
gc.controller.disable()

# ============================================================================
# Summary
# ============================================================================
print nl + "====================="
print str(passed) + " passed, " + str(failed) + " failed"

if failed > 0:
    print "SOME TESTS FAILED"
else:
    print "All GC tests passed!"
