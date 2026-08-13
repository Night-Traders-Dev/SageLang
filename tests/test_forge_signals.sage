import os.linux.syscalls as sys
import assert

## Test signal constants.
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

## Test signal helpers.
proc test_signal_helpers():
    print "Testing signal helpers..."

    let desc_ign = sys.signal_ignore(sys.SIGINT)
    assert.assert_equal(desc_ign["nr"], sys.SYS_RT_SIGACTION, "signal_ignore should use rt_sigaction")
    assert.assert_equal(desc_ign["args"][0], sys.SIGINT, "signal_ignore should target SIGINT")

    let desc_def = sys.signal_default(sys.SIGTERM)
    assert.assert_equal(desc_def["args"][0], sys.SIGTERM, "signal_default should target SIGTERM")

    print "Signal helpers OK"

## Test default signal handler stubs.
proc test_handler_stubs():
    print "Testing handler stubs..."

    let segv = sys.sigsegv_handler(sys.SIGSEGV)
    assert.assert_equal(segv["nr"], sys.SYS_EXIT, "sigsegv_handler should return exit syscall")
    assert.assert_equal(segv["args"][0], 128 + sys.SIGSEGV, "sigsegv_handler exit code should be 128 + SIGSEGV")

    let hup = sys.sighup_handler(sys.SIGHUP)
    assert.assert_equal(hup["nr"], sys.SYS_EXIT, "sighup_handler should return exit syscall")
    assert.assert_equal(hup["args"][0], 128 + sys.SIGHUP, "sighup_handler exit code should be 128 + SIGHUP")

    let usr1 = sys.sigusr1_handler(sys.SIGUSR1)
    assert.assert_equal(usr1["args"][0], 128 + sys.SIGUSR1, "sigusr1_handler exit code should be 128 + SIGUSR1")

    let quit = sys.sigquit_handler(sys.SIGQUIT)
    assert.assert_equal(quit["args"][0], 128 + sys.SIGQUIT, "sigquit_handler exit code should be 128 + SIGQUIT")

    let kill = sys.sigkill_handler(sys.SIGKILL)
    assert.assert_equal(kill["args"][0], 128 + sys.SIGKILL, "sigkill_handler exit code should be 128 + SIGKILL")

    let pipe = sys.sigpipe_handler(sys.SIGPIPE)
    assert.assert_equal(pipe["args"][0], 128 + sys.SIGPIPE, "sigpipe_handler exit code should be 128 + SIGPIPE")

    let alrm = sys.sigalrm_handler(sys.SIGALRM)
    assert.assert_equal(alrm["args"][0], 128 + sys.SIGALRM, "sigalrm_handler exit code should be 128 + SIGALRM")

    let chld = sys.sigchld_handler(sys.SIGCHLD)
    assert.assert_equal(chld["args"][0], 128 + sys.SIGCHLD, "sigchld_handler exit code should be 128 + SIGCHLD")

    let stop = sys.sigstop_handler(sys.SIGSTOP)
    assert.assert_equal(stop["args"][0], 128 + sys.SIGSTOP, "sigstop_handler exit code should be 128 + SIGSTOP")

    let cont = sys.sigcont_handler(sys.SIGCONT)
    assert.assert_equal(cont["args"][0], 128 + sys.SIGCONT, "sigcont_handler exit code should be 128 + SIGCONT")

    let usr2 = sys.sigusr2_handler(sys.SIGUSR2)
    assert.assert_equal(usr2["args"][0], 128 + sys.SIGUSR2, "sigusr2_handler exit code should be 128 + SIGUSR2")

    print "Handler stubs OK"

## Main entry point.
proc main():
    test_signal_constants()
    test_signal_helpers()
    test_handler_stubs()
    print "All signal tests passed!"

main()
