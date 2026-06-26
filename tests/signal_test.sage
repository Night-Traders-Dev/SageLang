import os.linux.syscalls as sys
import assert

proc test_signal_constants():
    assert.assert_equal(sys.SIG_DFL, 0, "SIG_DFL should be 0")
    assert.assert_equal(sys.SIG_IGN, 1, "SIG_IGN should be 1")
    print "Signal constants test passed"

proc test_signal_helpers():
    let ignore_desc = sys.signal_ignore(sys.SIGINT)
    assert.assert_not_nil(ignore_desc, "signal_ignore should return a descriptor")
    assert.assert_equal(ignore_desc["nr"], sys.SYS_RT_SIGACTION, "Should use SYS_RT_SIGACTION")

    let default_desc = sys.signal_default(sys.SIGTERM)
    assert.assert_not_nil(default_desc, "signal_default should return a descriptor")

    print "Signal helpers test passed"

proc test_handler_stubs():
    let res = sys.sigquit_handler(sys.SIGQUIT)
    assert.assert_equal(res["nr"], sys.SYS_EXIT, "sigquit_handler should return exit syscall")
    assert.assert_equal(res["args"][0], 128 + sys.SIGQUIT, "Exit code should be 128 + SIGQUIT")
    print "Handler stubs test passed"

proc main():
    test_signal_constants()
    test_signal_helpers()
    test_handler_stubs()
    print "All signal tests passed"

main()
