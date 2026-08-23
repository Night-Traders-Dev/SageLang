# EXPECT: barriers_ok
# EXPECT: cpu_id_ok
# EXPECT: critical_section_ok
# EXPECT: spin_lock_ok
# EXPECT: PASS
import metal.core as core

# Test memory barriers
core.dmb()
core.dsb()
core.isb()
core.fence()
print "barriers_ok"

# Test cpu_id
let cid = core.cpu_id()
if cid == 0:
    print "cpu_id_ok"

# Test critical section enter/exit
core.critical_section_enter()
core.critical_section_exit()
print "critical_section_ok"

# Test spin lock acquire and release
let lock_addr = 0x1000
core.spin_lock(lock_addr)
core.spin_unlock(lock_addr)
print "spin_lock_ok"

print "PASS"
