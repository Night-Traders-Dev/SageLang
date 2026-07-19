import metal.timer as timer
import assert

let triggered_oneshot = 0
let triggered_periodic = 0

## Callback for oneshot timer test
proc oneshot_callback():
    triggered_oneshot = triggered_oneshot + 1

## Callback for periodic timer test
proc periodic_callback():
    triggered_periodic = triggered_periodic + 1

## Main test routine for software timers
proc test_software_timers():
    print "Testing metal.timer software timers..."

    # Reset/clear software timers
    timer.timer_clear_software()

    # 1. Test One-Shot Timer
    let t1 = timer.timer_create_software(timer.TIMER_MODE_ONESHOT, 5, oneshot_callback)
    assert.assert_true(t1 > 0, "Should return a valid timer ID")

    # Tick timer by 4ms (not expired yet)
    let idx_i = 0
    while idx_i < 4:
        timer.timer_tick_software()
        idx_i = idx_i + 1
    assert.assert_equal(triggered_oneshot, 0, "One-shot should not trigger before 5ms")

    # Tick 5th ms
    timer.timer_tick_software()
    assert.assert_equal(triggered_oneshot, 1, "One-shot should trigger at 5ms")

    # Tick again (should not trigger again)
    timer.timer_tick_software()
    assert.assert_equal(triggered_oneshot, 1, "One-shot should trigger only once")

    # 2. Test Periodic Timer
    timer.timer_create_software(timer.TIMER_MODE_PERIODIC, 3, periodic_callback)

    let idx_j = 0
    while idx_j < 2:
        timer.timer_tick_software()
        idx_j = idx_j + 1
    assert.assert_equal(triggered_periodic, 0, "Periodic should not trigger before 3ms")

    # 3rd ms
    timer.timer_tick_software()
    assert.assert_equal(triggered_periodic, 1, "Periodic should trigger at 3ms")

    # Tick 3 more times
    let idx_k = 0
    while idx_k < 3:
        timer.timer_tick_software()
        idx_k = idx_k + 1
    assert.assert_equal(triggered_periodic, 2, "Periodic should trigger again at 6ms")

    # 3. Test Canceling
    let triggered_canceled = 0
    proc canceled_callback():
        triggered_canceled = triggered_canceled + 1

    let t3 = timer.timer_create_software(timer.TIMER_MODE_ONESHOT, 2, canceled_callback)
    let canceled = timer.timer_cancel_software(t3)
    assert.assert_true(canceled, "Should successfully cancel active timer")

    # Tick past expiration
    timer.timer_tick_software()
    timer.timer_tick_software()
    assert.assert_equal(triggered_canceled, 0, "Canceled timer should not trigger")

    # 4. Test Clearing
    timer.timer_clear_software()
    timer.timer_create_software(timer.TIMER_MODE_ONESHOT, 1, oneshot_callback)
    timer.timer_clear_software()
    timer.timer_tick_software()
    assert.assert_equal(triggered_oneshot, 1, "Cleared timer should not trigger")

    print "Software timer tests passed!"

test_software_timers()
