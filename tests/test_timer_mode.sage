# # ============================================================================
# # Hardware Timer Mode Tracking Verification (Forge Implementation)
# # ============================================================================
# # We enhanced the hardware timer module `core/lib/metal/timer.sage` with
# # hardware timer mode tracking.
# #
# # Implementation details inside core/lib/metal/timer.sage:
# # - Added a state tracking variable `let _timer_mode = TIMER_MODE_PERIODIC`.
# # - Updated `timer_init_periodic(hz)` to set `_timer_mode = TIMER_MODE_PERIODIC`.
# # - Updated `timer_init_oneshot(hz)` to set `_timer_mode = TIMER_MODE_ONESHOT`.
# # - Implemented a new getter function `proc timer_get_mode()` to query active mode.
# # - Cleaned up top-level style/docstring [S003] linter errors.
# #
# # This provides embedded and OS development with essential hardware-accurate
# # state querying for CPU hardware timer modules.

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
