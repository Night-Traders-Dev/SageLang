import os.linux.syscalls as sys
import assert

proc test_signal_constants():
    print "Testing signal constants..."
    assert.assert_equal(sys.SIG_DFL, 0, "SIG_DFL should be 0")
    assert.assert_equal(sys.SIG_IGN, 1, "SIG_IGN should be 1")
    assert.assert_equal(sys.SIGHUP, 1, "SIGHUP should be 1")
    assert.assert_equal(sys.SIGINT, 2, "SIGINT should be 2")
    assert.assert_equal(sys.SIGQUIT, 3, "SIGQUIT should be 3")
    assert.assert_equal(sys.SIGKILL, 9, "SIGKILL should be 9")
    assert.assert_equal(sys.SIGTERM, 15, "SIGTERM should be 15")
    print "Signal constants OK"

proc test_signal_helpers():
    print "Testing signal helpers..."

    let desc_ign = sys.signal_ignore(sys.SIGINT)
    assert.assert_equal(desc_ign["nr"], sys.SYS_RT_SIGACTION, "signal_ignore should use rt_sigaction")
    assert.assert_equal(desc_ign["args"][0], sys.SIGINT, "signal_ignore should target SIGINT")

    let desc_def = sys.signal_default(sys.SIGTERM)
    assert.assert_equal(desc_def["args"][0], sys.SIGTERM, "signal_default should target SIGTERM")

    print "Signal helpers OK"

proc test_handler_stubs():
    print "Testing handler stubs..."

    let hup = sys.sighup_handler(sys.SIGHUP)
    assert.assert_equal(hup["nr"], sys.SYS_EXIT, "sighup_handler should return exit syscall")
    assert.assert_equal(hup["args"][0], 128 + sys.SIGHUP, "sighup_handler exit code should be 128 + SIGHUP")

    let usr1 = sys.sigusr1_handler(sys.SIGUSR1)
    assert.assert_equal(usr1["args"][0], 128 + sys.SIGUSR1, "sigusr1_handler exit code should be 128 + SIGUSR1")

    print "Handler stubs OK"

proc main():
    test_signal_constants()
    test_signal_helpers()
    test_handler_stubs()
    print "All signal tests passed!"

main()
