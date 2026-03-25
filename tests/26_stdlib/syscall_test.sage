gc_disable()
# EXPECT: syscall_init
# EXPECT: registered
# EXPECT: dispatch_works
# EXPECT: table_has_entries
# EXPECT: PASS

import os.kernel.syscall

# Initialize the syscall table
syscall.init()

# Verify built-in syscalls were registered
let st = syscall.stats()
if st["total_calls"] == 0
    print "syscall_init"
end

# Register a custom syscall (number 100)
let custom_called = false
proc my_handler(args)
    return 42
end
let ok = syscall.register(100, "custom", my_handler)
if ok
    print "registered"
end

# Dispatch the custom syscall
let result = syscall.dispatch(100, nil)
if result == 42
    print "dispatch_works"
end

# Check the syscall table has entries
let table = syscall.syscall_table()
if len(table) > 5
    print "table_has_entries"
end

print "PASS"
