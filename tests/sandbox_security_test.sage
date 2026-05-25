import agent.sandbox
import assert

proc test_sandbox_safety():
    print "Testing improved sandbox safety..."

    # Safe code
    let safe_code = "let x = 1 + 2; print x"
    let safe_res = sandbox.is_safe(safe_code)
    assert.assert_true(safe_res["safe"], "Simple arithmetic should be safe")

    # Code with potential false positives (now should be safe)
    let potential_fp = "let action = 'run'; let important = true"
    let fp_res = sandbox.is_safe(potential_fp)
    assert.assert_true(fp_res["safe"], "'action' and 'important' should not be flagged by 'io' or 'import'")

    # Unsafe code: io.
    let unsafe_io = "io.readfile('/etc/passwd')"
    let unsafe_io_res = sandbox.is_safe(unsafe_io)
    assert.assert_false(unsafe_io_res["safe"], "io. operations should be unsafe")

    # Unsafe code: sys.
    let unsafe_sys = "sys.exec('rm -rf /')"
    let unsafe_sys_res = sandbox.is_safe(unsafe_sys)
    assert.assert_false(unsafe_sys_res["safe"], "sys. operations should be unsafe")

    # Unsafe code: import
    let unsafe_import = "import tcp; let c = tcp.connect('1.2.3.4', 80)"
    let unsafe_import_res = sandbox.is_safe(unsafe_import)
    assert.assert_false(unsafe_import_res["safe"], "import should be unsafe")

    # Unsafe code: import with newline
    let unsafe_import_nl = "import" + chr(10) + "tcp"
    let unsafe_import_nl_res = sandbox.is_safe(unsafe_import_nl)
    assert.assert_false(unsafe_import_nl_res["safe"], "import with newline should be unsafe")

    # Unsafe code: import with tab
    let unsafe_import_tab = "import" + chr(9) + "tcp"
    let unsafe_import_tab_res = sandbox.is_safe(unsafe_import_tab)
    assert.assert_false(unsafe_import_tab_res["safe"], "import with tab should be unsafe")

    # Unsafe code: from io import tab readfile
    let unsafe_import_from_tab = "from io import" + chr(9) + "readfile"
    let unsafe_import_from_tab_res = sandbox.is_safe(unsafe_import_from_tab)
    assert.assert_false(unsafe_import_from_tab_res["safe"], "from import with tab should be unsafe")

    # Safe code: import inside comment
    let safe_import_comment = "# This is a comment containing import tcp\nlet x = 1"
    let safe_import_comment_res = sandbox.is_safe(safe_import_comment)
    assert.assert_true(safe_import_comment_res["safe"], "import in comment should be safe")

    # Safe code: import inside string
    let safe_import_string = "let msg = \"Please import this package\""
    let safe_import_string_res = sandbox.is_safe(safe_import_string)
    assert.assert_true(safe_import_string_res["safe"], "import in string should be safe")

    # Unsafe code: primitives
    let unsafe_prim = "ffi_open('libc.so.6')"
    let unsafe_prim_res = sandbox.is_safe(unsafe_prim)
    assert.assert_false(unsafe_prim_res["safe"], "ffi_open should be unsafe")

    print "✅ Improved sandbox safety tests passed!"

test_sandbox_safety()
