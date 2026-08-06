import metal.timer
import assert

proc test_timer_modes():
    print "Testing hardware timer mode configurations..."

    # Check that default mode is periodic (or whatever is initialized)
    let default_mode = timer.timer_get_mode()
    assert.assert_true(default_mode == timer.TIMER_MODE_PERIODIC, "Default timer mode should be TIMER_MODE_PERIODIC")

    # Change mode to one-shot
    timer.timer_init_oneshot(1000)
    let oneshot_mode = timer.timer_get_mode()
    assert.assert_true(oneshot_mode == timer.TIMER_MODE_ONESHOT, "Timer mode should change to TIMER_MODE_ONESHOT")

    # Change mode back to periodic
    timer.timer_init_periodic(1000)
    let periodic_mode = timer.timer_get_mode()
    assert.assert_true(periodic_mode == timer.TIMER_MODE_PERIODIC, "Timer mode should change back to TIMER_MODE_PERIODIC")

    # Verify constants
    assert.assert_equal(timer.TIMER_MODE_ONESHOT, 0, "TIMER_MODE_ONESHOT should be 0")
    assert.assert_equal(timer.TIMER_MODE_PERIODIC, 1, "TIMER_MODE_PERIODIC should be 1")

    print "Hardware timer mode test passed successfully!"

test_timer_modes()
