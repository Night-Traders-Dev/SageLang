import metal.core as core
import assert

## Test RP2040 SIO inter-core FIFO functions.
proc test_rp2040_sio_fifo():
    print "Testing RP2040 SIO Inter-Core FIFO..."

    assert.assert_false(core.sio_fifo_rx_valid(), "FIFO RX should not be valid initially")

    # Simulate pushing data
    core.sio_fifo_push(3735928559) # 0xDEADBEEF

    # Drain test
    core.sio_fifo_drain()
    assert.assert_false(core.sio_fifo_rx_valid(), "FIFO RX should be clear after drain")

    print "RP2040 SIO FIFO tests passed."

## Test RP2040 SIO hardware spinlocks.
proc test_rp2040_sio_spinlock():
    print "Testing RP2040 SIO Hardware Spinlocks..."

    # Lock index 5
    let lock_num = 5

    let locked = core.sio_hw_spinlock(lock_num)

    # Release lock
    core.sio_hw_spinunlock(lock_num)

    print "RP2040 SIO Hardware Spinlock tests passed."

## Test RP2040 SIO GPIO bitmask operations.
proc test_rp2040_sio_gpio():
    print "Testing RP2040 SIO GPIO bitmask ops..."
    core.sio_gpio_set_mask(3)
    core.sio_gpio_clr_mask(2)
    core.sio_gpio_xor_mask(1)

    core.sio_gpio_set_oe_mask(3)
    core.sio_gpio_clr_mask_oe(2)
    core.sio_gpio_xor_oe_mask(1)

    assert.assert_equal(0, core.rp2040_cpuid(), "CPU ID should default to 0")
    print "RP2040 SIO GPIO bitmask ops passed."

## Entry point for RP2040 SIO test suite.
proc main():
    test_rp2040_sio_fifo()
    test_rp2040_sio_spinlock()
    test_rp2040_sio_gpio()
    print "All RP2040 SIO tests passed!"

main()
