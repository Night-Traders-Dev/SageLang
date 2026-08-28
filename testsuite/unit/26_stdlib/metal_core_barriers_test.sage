# EXPECT: barriers_ok
# EXPECT: cpu_id_ok
# EXPECT: critical_section_ok
# EXPECT: spin_lock_ok
# EXPECT: PASS
# # Unit test for metal.core memory barriers and critical section helpers
import metal.core as core

proc test_barriers():
    core.dmb()
    core.dsb()
    core.isb()
    core.fence()
    core.cpu_relax()
    core.io_wait()
    print "barriers_ok"

proc test_cpu_id():
    let id = core.cpu_id()
    if id == 0:
        print "cpu_id_ok"

proc test_critical_section():
    core.critical_section_enter()
    core.critical_section_exit()
    print "critical_section_ok"

proc test_spin_lock():
    # Test spin lock with simulated MMIO memory allocation
    let lock_addr = 1024
    core.mmio_write32(lock_addr, 0)
    core.spin_lock(lock_addr)
    core.spin_unlock(lock_addr)
    print "spin_lock_ok"

proc main():
    test_barriers()
    test_cpu_id()
    test_critical_section()
    test_spin_lock()
    print "PASS"

main()
