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
    let desc = sys.signal(sys.SIGTERM, 0x5678)
    assert.assert_equal(desc["nr"], sys.SYS_RT_SIGACTION, "nr should be SYS_RT_SIGACTION")
    assert.assert_equal(desc["args"][0], sys.SIGTERM, "arg0 should be SIGTERM")
    assert.assert_equal(desc["args"][1], 0x5678, "arg1 should be handler address")
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
