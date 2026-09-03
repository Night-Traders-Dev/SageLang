import os.kernel.kmain as kmain

## Tests proc_status_name for all ProcStatus variants.
proc test_proc_status():
    let idle_str = kmain.proc_status_name(kmain.ProcStatus["Idle"])
    let ready_str = kmain.proc_status_name(kmain.ProcStatus["Ready"])
    let running_str = kmain.proc_status_name(kmain.ProcStatus["Running"])
    let blocked_str = kmain.proc_status_name(kmain.ProcStatus["Blocked"])
    let zombie_str = kmain.proc_status_name(kmain.ProcStatus["Zombie"])
    let term_str = kmain.proc_status_name(kmain.ProcStatus["Terminated"])
    let unknown_str = kmain.proc_status_name(999)

    print "Idle: " + idle_str
    print "Ready: " + ready_str
    print "Running: " + running_str
    print "Blocked: " + blocked_str
    print "Zombie: " + zombie_str
    print "Terminated: " + term_str
    print "Unknown: " + unknown_str

    let ok = true
    if idle_str != "Idle" or ready_str != "Ready" or running_str != "Running":
        ok = false
    if blocked_str != "Blocked" or zombie_str != "Zombie" or term_str != "Terminated":
        ok = false
    if unknown_str != "Unknown":
        ok = false

    if ok:
        print "proc_status_name tests passed!"
    else:
        print "proc_status_name tests FAILED!"

test_proc_status()
