import os.linux.syscalls as syscalls
import assert

proc test_sigprocmask_constants():
    assert.assert_equal(syscalls.SIG_BLOCK, 0, "SIG_BLOCK should be 0")
    assert.assert_equal(syscalls.SIG_UNBLOCK, 1, "SIG_UNBLOCK should be 1")
    assert.assert_equal(syscalls.SIG_SETMASK, 2, "SIG_SETMASK should be 2")

proc test_sigprocmask_desc():
    let desc = syscalls.sigprocmask(syscalls.SIG_BLOCK, 1024)
    assert.assert_equal(desc["arch"], "x86_64", "arch should be x86_64")
    assert.assert_equal(desc["nr"], syscalls.SYS_RT_SIGPROCMASK, "nr should be SYS_RT_SIGPROCMASK")
    assert.assert_equal(len(desc["args"]), 4, "nargs should be 4")
    assert.assert_equal(desc["args"][0], syscalls.SIG_BLOCK, "arg 0 should be SIG_BLOCK")
    assert.assert_equal(desc["args"][1], 1024, "arg 1 should be 1024")
    assert.assert_equal(desc["args"][2], nil, "arg 2 should be nil")
    assert.assert_equal(desc["args"][3], 8, "arg 3 should be 8")

test_sigprocmask_constants()
test_sigprocmask_desc()
print "sigprocmask test passed!"
