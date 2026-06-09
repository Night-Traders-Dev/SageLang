gc_disable()
# Tests for the self-hosted heartbeat module
import heartbeat

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

print "Self-hosted Heartbeat Tests"
print "============================"

# ============================================================================
# HeartbeatSystem - basic lifecycle
# ============================================================================
print nl + "--- HeartbeatSystem lifecycle ---"

let hb = heartbeat.HeartbeatSystem("test-hb")
assert_eq(hb.name, "test-hb", "name set")
assert_false(hb.is_alive(), "not alive before start")
assert_eq(hb.get_total_calls(), 0, "zero calls initially")
assert_eq(hb.get_report_count(), 0, "zero reports initially")

hb.start()
assert_true(hb.is_alive(), "alive after start")

hb.stop()
assert_false(hb.is_alive(), "not alive after stop")

# ============================================================================
# HeartbeatSystem - update counting
# ============================================================================
print nl + "--- HeartbeatSystem update ---"

let hb2 = heartbeat.HeartbeatSystem("counter")
hb2.start()
hb2.set_interval(10)

# Call update 9 times - no report
let i = 0
while i < 9:
    let reported = hb2.update()
    assert_false(reported, "no report at call " + str(i + 1))
    i = i + 1

assert_eq(hb2.get_total_calls(), 9, "9 total calls")
assert_eq(hb2.get_report_count(), 0, "0 reports after 9 calls")

# 10th call triggers report
let r10 = hb2.update()
assert_true(r10, "report on 10th call")
assert_eq(hb2.get_total_calls(), 10, "10 total calls")
assert_eq(hb2.get_report_count(), 1, "1 report after 10 calls")

# Next 10 calls trigger another report
i = 0
while i < 10:
    hb2.update()
    i = i + 1
assert_eq(hb2.get_total_calls(), 20, "20 total calls")
assert_eq(hb2.get_report_count(), 2, "2 reports after 20 calls")

hb2.stop()

# ============================================================================
# HeartbeatSystem - update when stopped returns false
# ============================================================================
print nl + "--- HeartbeatSystem stopped update ---"

let hb3 = heartbeat.HeartbeatSystem("stopped")
assert_false(hb3.update(), "update returns false when not started")

hb3.start()
hb3.stop()
assert_false(hb3.update(), "update returns false after stop")

# ============================================================================
# HeartbeatSystem - set_interval
# ============================================================================
print nl + "--- HeartbeatSystem set_interval ---"

let hb4 = heartbeat.HeartbeatSystem("interval")
hb4.start()
hb4.set_interval(3)

hb4.update()
hb4.update()
let r3 = hb4.update()
assert_true(r3, "report at interval 3")

# Invalid interval (0 or negative) - should not change
hb4.set_interval(0)
assert_eq(hb4.report_interval, 3, "set_interval(0) no-op")
hb4.set_interval(-1)
assert_eq(hb4.report_interval, 3, "set_interval(-1) no-op")
hb4.stop()

# ============================================================================
# HeartbeatSystem - to_string
# ============================================================================
print nl + "--- HeartbeatSystem to_string ---"

let hb5 = heartbeat.HeartbeatSystem("str-test")
let s1 = hb5.to_string()
assert_true(contains(s1, "str-test"), "to_string has name")
assert_true(contains(s1, "stopped"), "to_string shows stopped")

hb5.start()
let s2 = hb5.to_string()
assert_true(contains(s2, "running"), "to_string shows running")
hb5.stop()

# ============================================================================
# HealthCheck - basic operations
# ============================================================================
print nl + "--- HealthCheck basic ---"

let hc = heartbeat.HealthCheck()
assert_eq(hc.check_count, 0, "initial check_count")

hc.register("db", true)
hc.register("cache", true)
hc.register("api", false)
assert_eq(hc.check_count, 3, "3 checks registered")

assert_true(hc.get("db"), "db is healthy")
assert_true(hc.get("cache"), "cache is healthy")
assert_false(hc.get("api"), "api is unhealthy")
assert_eq(hc.get("nonexistent"), nil, "unknown returns nil")

# ============================================================================
# HealthCheck - all_healthy
# ============================================================================
print nl + "--- HealthCheck all_healthy ---"

assert_false(hc.all_healthy(), "not all healthy when api is down")

hc.update("api", true)
assert_true(hc.all_healthy(), "all healthy after api fixed")

hc.update("cache", false)
assert_false(hc.all_healthy(), "not all healthy when cache down")

# ============================================================================
# HealthCheck - unhealthy_checks
# ============================================================================
print nl + "--- HealthCheck unhealthy_checks ---"

let unhealthy = hc.unhealthy_checks()
assert_eq(len(unhealthy), 1, "one unhealthy check")
assert_eq(unhealthy[0], "cache", "cache is the unhealthy one")

hc.update("cache", true)
let unhealthy2 = hc.unhealthy_checks()
assert_eq(len(unhealthy2), 0, "no unhealthy after fix")

# ============================================================================
# HealthCheck - update returns
# ============================================================================
print nl + "--- HealthCheck update returns ---"

let hc2 = heartbeat.HealthCheck()
hc2.register("x", true)
assert_true(hc2.update("x", false), "update known returns true")
assert_false(hc2.update("unknown", true), "update unknown returns false")

# ============================================================================
# Summary
# ============================================================================
print nl + "============================"
print str(passed) + " passed, " + str(failed) + " failed"

if failed > 0:
    print "SOME TESTS FAILED"
else:
    print "All heartbeat tests passed!"
