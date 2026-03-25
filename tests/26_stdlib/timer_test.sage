gc_disable()
# EXPECT: timer_created
# EXPECT: ticks_zero
# EXPECT: PASS

import os.kernel.timer

# Initialize timer at 100 Hz
timer.init(100)

# Check timer is ready
let freq = timer.get_frequency()
if freq == 100
    print "timer_created"
end

# Check initial tick count is 0
let ticks = timer.get_ticks()
if ticks == 0
    print "ticks_zero"
end

print "PASS"
