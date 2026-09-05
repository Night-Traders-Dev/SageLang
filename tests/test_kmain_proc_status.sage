import os.kernel.kmain as kmain
import assert

## Test proc_status_name function in os.kernel.kmain module.
proc test_proc_status_name():
    print "Testing proc_status_name in os.kernel.kmain..."

    # Test all variants
    assert.assert_equal("Idle", kmain.proc_status_name(kmain.ProcStatus["Idle"]), "ProcStatus Idle")
    assert.assert_equal("Ready", kmain.proc_status_name(kmain.ProcStatus["Ready"]), "ProcStatus Ready")
    assert.assert_equal("Running", kmain.proc_status_name(kmain.ProcStatus["Running"]), "ProcStatus Running")
    assert.assert_equal("Blocked", kmain.proc_status_name(kmain.ProcStatus["Blocked"]), "ProcStatus Blocked")
    assert.assert_equal("Zombie", kmain.proc_status_name(kmain.ProcStatus["Zombie"]), "ProcStatus Zombie")
    assert.assert_equal("Terminated", kmain.proc_status_name(kmain.ProcStatus["Terminated"]), "ProcStatus Terminated")

    # Test integer inputs directly
    assert.assert_equal("Idle", kmain.proc_status_name(0), "ProcStatus integer 0")
    assert.assert_equal("Ready", kmain.proc_status_name(1), "ProcStatus integer 1")
    assert.assert_equal("Running", kmain.proc_status_name(2), "ProcStatus integer 2")
    assert.assert_equal("Blocked", kmain.proc_status_name(3), "ProcStatus integer 3")
    assert.assert_equal("Zombie", kmain.proc_status_name(4), "ProcStatus integer 4")
    assert.assert_equal("Terminated", kmain.proc_status_name(5), "ProcStatus integer 5")

    # Test unknown/invalid state
    assert.assert_equal("Unknown", kmain.proc_status_name(-1), "ProcStatus invalid -1")
    assert.assert_equal("Unknown", kmain.proc_status_name(99), "ProcStatus invalid 99")

    print "proc_status_name tests passed successfully!"

## Main test runner.
proc main():
    test_proc_status_name()

main()
