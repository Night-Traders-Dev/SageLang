import arrays
import agent.sandbox
import strings
import utils
import assert

proc test_unique_structural():
    print "Testing structural unique()..."
    # Dictionary values that stringify to "<dict>" but have different structure/contents
    let d1 = {"x": 1}
    let d2 = {"x": 2}
    let d3 = {"x": 1}
    
    let dicts = [d1, d2, d3]
    let uniq_dicts = arrays.unique(dicts)
    
    assert.assert_true(len(uniq_dicts) == 2, "Uniqueness check should keep exactly 2 unique dictionaries")
    assert.assert_true(uniq_dicts[0] == d1, "First unique dict should be d1")
    assert.assert_true(uniq_dicts[1] == d2, "Second unique dict should be d2")

proc test_safe_whitespaces():
    print "Testing module-loading guard with tab/whitespace separators..."
    
    # Payload using tab
    let code_tab = "import" + chr(9) + "tcp"
    let res_tab = sandbox.is_safe(code_tab)
    assert.assert_false(res_tab["safe"], "import with tab should be unsafe")
    
    # Payload using from ... import with tab
    let code_from_tab = "from io import" + chr(9) + "readfile"
    let res_from_tab = sandbox.is_safe(code_from_tab)
    assert.assert_false(res_from_tab["safe"], "from-import with tab should be unsafe")
    
    # Comments containing "import" should be safe
    let code_comment = "# This is a comment containing import\nlet x = 1"
    let res_comment = sandbox.is_safe(code_comment)
    assert.assert_true(res_comment["safe"], "import inside comment should be safe")
    
    # String literal containing "import" should be safe
    let code_string = "let s = \"import tcp\""
    let res_string = sandbox.is_safe(code_string)
    assert.assert_true(res_string["safe"], "import inside string literal should be safe")

proc test_repeat_no_hang():
    print "Testing string repeat O(log N) no-hang/corrupt..."
    let repeated = strings.repeat("ab", 5)
    assert.assert_true(repeated == "ababababab", "strings.repeat should yield correctly")

proc test_repeat_value_no_hang():
    print "Testing repeat_value O(log N) no-hang..."
    let repeated = utils.repeat_value(42, 5)
    assert.assert_true(len(repeated) == 5, "repeat_value should yield correct length")
    assert.assert_true(repeated[0] == 42, "repeat_value elements should be correct")

proc run_all_tests():
    test_unique_structural()
    test_safe_whitespaces()
    test_repeat_no_hang()
    test_repeat_value_no_hang()
    print "All P1 fixes tests passed successfully!"

run_all_tests()
