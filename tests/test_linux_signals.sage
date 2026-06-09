import os.linux.syscalls as sys
import assert

proc test_signal_constants():
    assert.assert_equal(sys.SYS_RT_SIGACTION, 13, "SYS_RT_SIGACTION should be 13")
    assert.assert_equal(sys.ARM64_SYS_RT_SIGACTION, 134, "ARM64_SYS_RT_SIGACTION should be 134")
    assert.assert_equal(sys.RV64_SYS_RT_SIGACTION, 134, "RV64_SYS_RT_SIGACTION should be 134")
end

proc test_signal_descriptors():
    let desc = sys.sys_rt_sigaction_desc(sys.SIGINT, 0x1234, nil, 8)
    assert.assert_equal(desc["nr"], sys.SYS_RT_SIGACTION, "nr should be SYS_RT_SIGACTION")
    assert.assert_equal(desc["args"][0], sys.SIGINT, "arg0 should be SIGINT")
    assert.assert_equal(desc["args"][1], 0x1234, "arg1 should be handler address")
end

proc test_signal_helper():
    let handler_addr = 0x5678
    let desc = sys.signal(sys.SIGTERM, handler_addr)
    assert.assert_equal(desc["nr"], sys.SYS_RT_SIGACTION, "nr should be SYS_RT_SIGACTION")
    assert.assert_equal(desc["args"][0], sys.SIGTERM, "arg0 should be SIGTERM")
    
    # arg1 should be a pointer to a sigaction struct, not the handler itself
    let sa_ptr = desc["args"][1]
    assert.assert_true(sa_ptr != handler_addr, "arg1 should be a struct pointer, not the handler address")
    
    # Verify the first field of the struct is indeed the handler address
    # We need to define the type to use struct_get
    let sigaction_t = struct_def([
        ["sa_handler", "long"],
        ["sa_flags", "long"],
        ["sa_restorer", "long"],
        ["sa_mask", "long"]
    ])
    let sa_handler = struct_get(sa_ptr, sigaction_t, "sa_handler")
    assert.assert_equal(sa_handler, handler_addr, "sa_handler in struct should match")
end

proc test_syscall_table():
    let table = sys.build_syscall_table()
    let found = false
    let i = 0
    while i < len(table):
        if table[i]["name"] == "rt_sigaction":
            found = true
            assert.assert_equal(table[i]["nr"], sys.SYS_RT_SIGACTION, "Table nr should match")
        end
        i = i + 1
    end
    assert.assert_true(found, "rt_sigaction should be in syscall table")
end

test_signal_constants()
test_signal_descriptors()
test_signal_helper()
test_syscall_table()
print "All signal tests passed!"
