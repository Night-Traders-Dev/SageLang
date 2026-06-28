import os.linux.syscalls as sc
import assert

proc test_signal_constants():
    assert.assert_equal(sc.SIG_DFL, 0, "SIG_DFL should be 0")
    assert.assert_equal(sc.SIG_IGN, 1, "SIG_IGN should be 1")
    assert.assert_equal(sc.SIGINT, 2, "SIGINT should be 2")
    assert.assert_equal(sc.SIGTERM, 15, "SIGTERM should be 15")
    print "Signal constants OK"

proc test_signal_helpers():
    # signal_ignore(sig) should call signal(sig, sc.SIG_IGN)
    # signal(sig, sc.SIG_IGN) calls sys_rt_sigaction_desc(sig, sa, nil, 8)
    # sys_rt_sigaction_desc returns a syscall descriptor dict

    let ignore_desc = sc.signal_ignore(sc.SIGINT)
    assert.assert_equal(ignore_desc["nr"], sc.SYS_RT_SIGACTION, "ignore should be rt_sigaction")
    assert.assert_equal(ignore_desc["args"][0], sc.SIGINT, "ignore should be for SIGINT")

    let default_desc = sc.signal_default(sc.SIGTERM)
    assert.assert_equal(default_desc["nr"], sc.SYS_RT_SIGACTION, "default should be rt_sigaction")
    assert.assert_equal(default_desc["args"][0], sc.SIGTERM, "default should be for SIGTERM")

    print "Signal helpers OK"

proc test_handler_stubs():
    # sigint_handler(sig) should call sys_exit_desc(128 + sig)

    let int_desc = sc.sigint_handler(sc.SIGINT)
    assert.assert_equal(int_desc["nr"], sc.SYS_EXIT, "int handler should call exit")
    assert.assert_equal(int_desc["args"][0], 128 + sc.SIGINT, "int exit code should be 128 + SIGINT")

    let term_desc = sc.sigterm_handler(sc.SIGTERM)
    assert.assert_equal(term_desc["nr"], sc.SYS_EXIT, "term handler should call exit")
    assert.assert_equal(term_desc["args"][0], 128 + sc.SIGTERM, "term exit code should be 128 + SIGTERM")

    let segv_desc = sc.sigsegv_handler(sc.SIGSEGV)
    assert.assert_equal(segv_desc["nr"], sc.SYS_EXIT, "segv handler should call exit")
    assert.assert_equal(segv_desc["args"][0], 128 + sc.SIGSEGV, "segv exit code should be 128 + SIGSEGV")

    let hup_desc = sc.sighup_handler(sc.SIGHUP)
    assert.assert_equal(hup_desc["nr"], sc.SYS_EXIT, "hup handler should call exit")
    assert.assert_equal(hup_desc["args"][0], 128 + sc.SIGHUP, "hup exit code should be 128 + SIGHUP")

    let usr1_desc = sc.sigusr1_handler(sc.SIGUSR1)
    assert.assert_equal(usr1_desc["nr"], sc.SYS_EXIT, "usr1 handler should call exit")
    assert.assert_equal(usr1_desc["args"][0], 128 + sc.SIGUSR1, "usr1 exit code should be 128 + SIGUSR1")

    print "Handler stubs OK"

test_signal_constants()
test_signal_helpers()
test_handler_stubs()
print "All signal smoke tests passed!"
