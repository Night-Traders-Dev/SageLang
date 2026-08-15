import metal.core as core
import assert

proc test_metal_core_barriers():
    print "Testing metal.core barriers and CPU synchronization..."

    # Memory barriers (no side-effect / no crash)
    core.dmb()
    core.dsb()
    core.isb()
    core.fence()

    # cpu_id
    let cid = core.cpu_id()
    assert.assert_equal(0, cid, "cpu_id should return 0 in default simulation")

    # Critical section enter and exit
    core.critical_section_enter()
    core.critical_section_exit()

    # Spin lock acquire and release
    let lock_ptr = 0x2000
    core.spin_lock(lock_ptr)
    assert.assert_equal(1, core.mmio_read32(lock_ptr), "spin_lock should set lock state to 1")
    core.spin_unlock(lock_ptr)
    assert.assert_equal(0, core.mmio_read32(lock_ptr), "spin_unlock should set lock state to 0")

    print "Metal core barrier tests OK"

proc main():
    test_metal_core_barriers()
    print "All Forge metal core tests passed!"

main()
