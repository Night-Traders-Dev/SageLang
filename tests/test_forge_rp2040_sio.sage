import metal.core as core
import assert

## Test RP2040 SIO inter-core FIFO functions.
proc test_rp2040_sio_fifo():
    print "Testing RP2040 SIO Inter-Core FIFO..."

    # Initially FIFO is empty and ready
    core.mmio_write32(core.SIO_FIFO_ST, 2) # Bit 1 = RDY
    assert.assert_false(core.sio_fifo_rx_valid(), "FIFO RX should not be valid initially")
    assert.assert_true(core.sio_fifo_tx_ready(), "FIFO TX should be ready initially")

    # Simulate pushing data
    core.sio_fifo_push(3735928559) # 0xDEADBEEF
    assert.assert_equal(3735928559, core.mmio_read32(core.SIO_FIFO_WR), "SIO_FIFO_WR should hold pushed value")

    # Set RX valid flag for reading
    core.mmio_write32(core.SIO_FIFO_ST, 3) # Bit 0 = VLD, Bit 1 = RDY
    core.mmio_write32(core.SIO_FIFO_RD, 3405691582) # 0xCAFEBABE
    assert.assert_true(core.sio_fifo_rx_valid(), "FIFO RX should be valid")

    let val = core.sio_fifo_pop()
    assert.assert_equal(3405691582, val, "sio_fifo_pop should return read data")

    # Drain test
    core.mmio_write32(core.SIO_FIFO_ST, 1) # VLD set
    core.sio_fifo_drain()
    core.mmio_write32(core.SIO_FIFO_ST, 0) # Clear
    assert.assert_false(core.sio_fifo_rx_valid(), "FIFO RX should be clear after drain")

    print "RP2040 SIO FIFO tests passed."

## Test RP2040 SIO hardware spinlocks.
proc test_rp2040_sio_spinlock():
    print "Testing RP2040 SIO Hardware Spinlocks..."

    # Lock index 5
    let lock_num = 5
    let lock_addr = core.SIO_SPINLOCK_BASE + (lock_num * 4)

    # Set non-zero in simulated MMIO to simulate available lock
    core.mmio_write32(lock_addr, 1)

    let locked = core.sio_hw_spinlock(lock_num)
    assert.assert_true(locked, "sio_hw_spinlock should acquire available lock")

    # Release lock
    core.sio_hw_spinunlock(lock_num)
    assert.assert_equal(0, core.mmio_read32(lock_addr), "sio_hw_spinunlock should clear lock register")

    print "RP2040 SIO Hardware Spinlock tests passed."

## Entry point for RP2040 SIO test suite.
proc main():
    test_rp2040_sio_fifo()
    test_rp2040_sio_spinlock()
    print "All RP2040 SIO tests passed!"

main()
