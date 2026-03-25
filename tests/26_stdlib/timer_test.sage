gc_disable()
# EXPECT: timer_init
# EXPECT: ticks_zero
# EXPECT: frequency_set
# EXPECT: PASS
let PIT_FREQ = 1193182
let ticks = 0
let freq = 100
let divisor = (PIT_FREQ / freq) | 0
print "timer_init"
if ticks == 0:
    print "ticks_zero"
if divisor > 0:
    print "frequency_set"
print "PASS"
