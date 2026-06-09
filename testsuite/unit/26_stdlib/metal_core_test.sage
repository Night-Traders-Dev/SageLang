# EXPECT: heap_init_ok
# EXPECT: heap_alloc_ok
# EXPECT: heap_overflow_ok
# EXPECT: heap_stats_ok
# EXPECT: delay_ok
# EXPECT: PASS
import metal.core as core

# Heap init and alloc
core.heap_init(0, 512)
let p1 = core.heap_alloc(64)
let p2 = core.heap_alloc(64)
if p1 == 0 and p2 == 64:
    print "heap_init_ok"
end

# Alignment: alloc 1 byte, next alloc should still be at 65 (no alignment in bump)
let p3 = core.heap_alloc(1)
let p4 = core.heap_alloc(1)
if p3 == 128 and p4 == 129:
    print "heap_alloc_ok"
end

# Overflow returns nil
let big = core.heap_alloc(1000)
if big == nil:
    print "heap_overflow_ok"
end

# Stats
let st = core.heap_stats()
if st["used"] == 130 and st["total"] == 512 and st["free"] == 382:
    print "heap_stats_ok"
end

# delay_us / delay_ms (just verify they don't crash)
core.delay_us(1)
core.delay_ms(1)
print "delay_ok"

print "PASS"
