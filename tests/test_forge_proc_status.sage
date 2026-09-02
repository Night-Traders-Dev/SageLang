import os.kernel.kmain as kmain
import assert

proc test_proc_status_names():
    print "Testing ProcStatus enum names..."

    assert.assert_equal("Idle", kmain.proc_status_name(kmain.ProcStatus["Idle"]), "ProcStatus.Idle should map to 'Idle'")
    assert.assert_equal("Ready", kmain.proc_status_name(kmain.ProcStatus["Ready"]), "ProcStatus.Ready should map to 'Ready'")
    assert.assert_equal("Running", kmain.proc_status_name(kmain.ProcStatus["Running"]), "ProcStatus.Running should map to 'Running'")
    assert.assert_equal("Blocked", kmain.proc_status_name(kmain.ProcStatus["Blocked"]), "ProcStatus.Blocked should map to 'Blocked'")
    assert.assert_equal("Zombie", kmain.proc_status_name(kmain.ProcStatus["Zombie"]), "ProcStatus.Zombie should map to 'Zombie'")
    assert.assert_equal("Terminated", kmain.proc_status_name(kmain.ProcStatus["Terminated"]), "ProcStatus.Terminated should map to 'Terminated'")

    assert.assert_equal("Unknown", kmain.proc_status_name(999), "Invalid ProcStatus should return 'Unknown'")

    print "ProcStatus enum name tests passed!"

proc main():
    test_proc_status_names()

main()
