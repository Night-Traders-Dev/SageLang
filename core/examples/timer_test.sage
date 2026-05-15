## Test script for metal.timer improvements

import metal.timer as timer

proc test_timer():
    print "Testing metal.timer..."

    # Test periodic init
    print "Initializing periodic timer at 100Hz..."
    timer.timer_init_periodic(100)

    # Test oneshot init
    print "Initializing oneshot timer at 50Hz..."
    timer.timer_init_oneshot(50)

    # Test remaining time (expect 0 in stub mode)
    let rem = timer.timer_remaining_ms()
    print "Remaining ms: " + str(rem)

    # Test delay_us
    print "Testing delay_us(100)..."
    timer.delay_us(100)

    # Test cancel
    print "Canceling timer..."
    timer.timer_cancel_safe()

    print "Timer test complete."

test_timer()
