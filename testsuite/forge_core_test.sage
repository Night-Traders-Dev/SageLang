import metal.core as core

proc test_primitives():
    print "Testing memory barriers..."
    core.dmb()
    core.dsb()
    core.isb()
    core.fence()

    print "Testing cpu_id..."
    let id = core.cpu_id()
    print "CPU ID: " + str(id)

    print "Testing critical section..."
    core.critical_section_enter()
    core.critical_section_exit()

    print "Testing spin lock..."
    let lock = mem_alloc(4)
    mem_write(lock, 0, "int", 0)
    core.spin_lock(lock)
    core.spin_unlock(lock)

    print "All primitives tested successfully!"

test_primitives()
