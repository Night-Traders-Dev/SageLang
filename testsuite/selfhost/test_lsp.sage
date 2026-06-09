gc_disable()
# -----------------------------------------
# test_lsp.sage - Tests for the self-hosted LSP module
# -----------------------------------------

import lsp

let nl = chr(10)
let dq = chr(34)
let bs = chr(92)
let tab = chr(9)
let passed = 0
let failed = 0

proc assert_eq(actual, expected, msg):
    if actual == expected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg
        print "  expected: " + str(expected)
        print "  actual:   " + str(actual)

proc assert_contains(haystack, needle, msg):
    if contains(haystack, needle):
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (should contain: " + needle + ")"

proc assert_not_nil(val, msg):
    if val != nil:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (was nil)"

proc assert_nil(val, msg):
    if val == nil:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (expected nil, got: " + str(val) + ")"

proc assert_true(val, msg):
    if val == true:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (expected true)"

proc assert_false(val, msg):
    if val == false:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (expected false)"

# =========================================================
# Document & DocumentStore tests (12)
# =========================================================
print "Document & DocumentStore"

let doc1 = lsp.make_document("file:///test.sage", "let x = 1")
assert_eq(doc1["uri"], "file:///test.sage", "Document uri")
assert_eq(doc1["content"], "let x = 1", "Document content")

let store = lsp.DocumentStore()
assert_nil(store.find("file:///unknown.sage"), "find returns nil for unknown uri")

let opened = store.open_doc("file:///a.sage", "let a = 1")
assert_not_nil(opened, "open_doc returns document")
assert_eq(opened["uri"], "file:///a.sage", "opened doc has correct uri")
assert_eq(opened["content"], "let a = 1", "opened doc has correct content")

let found = store.find("file:///a.sage")
assert_not_nil(found, "find returns opened doc")
assert_eq(found["content"], "let a = 1", "found doc content matches")

store.update("file:///a.sage", "let a = 2")
let updated = store.find("file:///a.sage")
assert_eq(updated["content"], "let a = 2", "update changes content")

store.open_doc("file:///a.sage", "let a = 3")
let reopened = store.find("file:///a.sage")
assert_eq(reopened["content"], "let a = 3", "open same uri updates content")

store.close_doc("file:///a.sage")
assert_nil(store.find("file:///a.sage"), "close removes document")

# =========================================================
# json_escape tests (8)
# =========================================================
print "json_escape"

assert_eq(lsp.json_escape(nil), "", "json_escape nil returns empty")
assert_eq(lsp.json_escape("hello"), "hello", "json_escape plain string")
assert_eq(lsp.json_escape("abc"), "abc", "json_escape simple ascii")

let with_dq = "say " + dq + "hi" + dq
let escaped_dq = lsp.json_escape(with_dq)
assert_contains(escaped_dq, bs + dq, "json_escape quotes get escaped")

let with_bs = "path" + bs + "file"
let escaped_bs = lsp.json_escape(with_bs)
assert_contains(escaped_bs, bs + bs, "json_escape backslash gets escaped")

let with_nl = "line1" + nl + "line2"
let escaped_nl = lsp.json_escape(with_nl)
assert_contains(escaped_nl, bs + "n", "json_escape newline becomes backslash-n")

let with_tab = "col1" + tab + "col2"
let escaped_tab = lsp.json_escape(with_tab)
assert_contains(escaped_tab, bs + "t", "json_escape tab becomes backslash-t")

let mixed = dq + bs + nl
let escaped_mixed = lsp.json_escape(mixed)
assert_contains(escaped_mixed, bs + dq, "json_escape mixed has escaped quote")

# =========================================================
# json_get_string tests (10)
# =========================================================
print "json_get_string"

let json1 = "{" + dq + "name" + dq + ":" + dq + "sage" + dq + "}"
assert_eq(lsp.json_get_string(json1, "name"), "sage", "json_get_string simple value")

assert_nil(lsp.json_get_string(json1, "missing"), "json_get_string missing key")
assert_nil(lsp.json_get_string(nil, "name"), "json_get_string nil json")
assert_nil(lsp.json_get_string(json1, nil), "json_get_string nil key")

let json2 = "{" + dq + "msg" + dq + ":" + dq + "say " + bs + dq + "hi" + bs + dq + dq + "}"
let val2 = lsp.json_get_string(json2, "msg")
assert_not_nil(val2, "json_get_string escaped quotes returns value")
assert_contains(val2, "hi", "json_get_string escaped quotes contains hi")

let json3 = "{" + dq + "path" + dq + ":" + dq + "a" + bs + bs + "b" + dq + "}"
let val3 = lsp.json_get_string(json3, "path")
assert_not_nil(val3, "json_get_string escaped backslash returns value")

let json4 = "{" + dq + "a" + dq + ":" + dq + "1" + dq + "," + dq + "b" + dq + ":" + dq + "2" + dq + "}"
assert_eq(lsp.json_get_string(json4, "a"), "1", "json_get_string first of multiple keys")
assert_eq(lsp.json_get_string(json4, "b"), "2", "json_get_string second of multiple keys")

# =========================================================
# json_get_int tests (6)
# =========================================================
print "json_get_int"

let json_int1 = "{" + dq + "id" + dq + ":42}"
assert_eq(lsp.json_get_int(json_int1, "id", -1), 42, "json_get_int extract integer")

assert_eq(lsp.json_get_int(json_int1, "missing", 99), 99, "json_get_int missing returns default")
assert_eq(lsp.json_get_int(nil, "id", 99), 99, "json_get_int nil json returns default")
assert_eq(lsp.json_get_int(json_int1, nil, 99), 99, "json_get_int nil key returns default")

let json_neg = "{" + dq + "val" + dq + ":-7}"
assert_eq(lsp.json_get_int(json_neg, "val", 0), -7, "json_get_int negative number")

let json_int2 = "{" + dq + "line" + dq + ":0," + dq + "col" + dq + ":5}"
assert_eq(lsp.json_get_int(json_int2, "col", -1), 5, "json_get_int second key")

# =========================================================
# json_get_object tests (8)
# =========================================================
print "json_get_object"

let json_obj1 = "{" + dq + "pos" + dq + ":{" + dq + "line" + dq + ":1}}"
let obj1 = lsp.json_get_object(json_obj1, "pos")
assert_not_nil(obj1, "json_get_object extracts object")
assert_contains(obj1, "line", "json_get_object contains inner key")

assert_nil(lsp.json_get_object(json_obj1, "missing"), "json_get_object missing key")
assert_nil(lsp.json_get_object(nil, "pos"), "json_get_object nil json")
assert_nil(lsp.json_get_object(json_obj1, nil), "json_get_object nil key")

let json_nested = "{" + dq + "outer" + dq + ":{" + dq + "inner" + dq + ":{" + dq + "x" + dq + ":1}}}"
let outer = lsp.json_get_object(json_nested, "outer")
assert_not_nil(outer, "json_get_object nested outer")
let inner = lsp.json_get_object(outer, "inner")
assert_not_nil(inner, "json_get_object nested inner")
assert_contains(inner, "x", "json_get_object nested inner contains x")

# =========================================================
# extract_id tests (6)
# =========================================================
print "extract_id"

let json_numid = "{" + dq + "id" + dq + ":1," + dq + "method" + dq + ":" + dq + "init" + dq + "}"
assert_eq(lsp.extract_id(json_numid), "1", "extract_id numeric id")

let json_numid2 = "{" + dq + "id" + dq + ":42}"
assert_eq(lsp.extract_id(json_numid2), "42", "extract_id numeric id 42")

let json_strid = "{" + dq + "id" + dq + ":" + dq + "abc" + dq + "}"
assert_eq(lsp.extract_id(json_strid), "abc", "extract_id string id")

let json_strid2 = "{" + dq + "id" + dq + ":" + dq + "req-1" + dq + "}"
assert_eq(lsp.extract_id(json_strid2), "req-1", "extract_id string id with dash")

let json_noid = "{" + dq + "method" + dq + ":" + dq + "init" + dq + "}"
assert_eq(lsp.extract_id(json_noid), "", "extract_id no id returns empty")

let json_noid2 = "{}"
assert_eq(lsp.extract_id(json_noid2), "", "extract_id empty json returns empty")

# =========================================================
# make_response, make_notification, make_error_response (8)
# =========================================================
print "make_response / make_notification / make_error_response"

let resp1 = lsp.make_response("1", "null")
assert_contains(resp1, "jsonrpc", "make_response has jsonrpc")
assert_contains(resp1, "2.0", "make_response has 2.0")
assert_contains(resp1, "null", "make_response has result null")

let resp2 = lsp.make_response("abc", dq + "ok" + dq)
assert_contains(resp2, "abc", "make_response string id present")

let notif = lsp.make_notification("textDocument/publishDiagnostics", "{}")
assert_contains(notif, "jsonrpc", "make_notification has jsonrpc")
assert_contains(notif, "textDocument/publishDiagnostics", "make_notification has method")
assert_contains(notif, "params", "make_notification has params")

let err = lsp.make_error_response("1", -32601, "Method not found")
assert_contains(err, "error", "make_error_response has error")

# =========================================================
# get_completions tests (4)
# =========================================================
print "get_completions"

let completions = lsp.get_completions()
assert_true(len(completions) > 0, "get_completions returns non-empty array")

let found_let = false
let found_str = false
let i = 0
while i < len(completions):
    let item = completions[i]
    if item["label"] == "let":
        found_let = true
    if item["label"] == "str":
        found_str = true
    i = i + 1

assert_true(found_let, "get_completions contains let")
assert_true(found_str, "get_completions contains str")

let sample_item = completions[0]
assert_not_nil(sample_item["label"], "completion item has label")

# =========================================================
# Hover docs tests (6)
# =========================================================
print "Hover docs"

let hover_docs = lsp.build_hover_docs()
let hd_keys = dict_keys(hover_docs)
assert_true(len(hd_keys) > 0, "build_hover_docs returns non-empty dict")

let let_doc = lsp.get_hover_doc("let", hover_docs)
assert_not_nil(let_doc, "get_hover_doc for let")
assert_contains(let_doc, "let", "hover doc for let contains let")

let str_doc = lsp.get_hover_doc("str", hover_docs)
assert_not_nil(str_doc, "get_hover_doc for str")
assert_contains(str_doc, "str", "hover doc for str contains str")

assert_nil(lsp.get_hover_doc("nonexistent_xyz", hover_docs), "get_hover_doc unknown returns nil")

# =========================================================
# get_word_at tests (10)
# =========================================================
print "get_word_at"

let src1 = "let foo = 42"
assert_eq(lsp.get_word_at(src1, 0, 4), "foo", "get_word_at middle of line")
assert_eq(lsp.get_word_at(src1, 0, 0), "let", "get_word_at start of line")
assert_eq(lsp.get_word_at(src1, 0, 10), "42", "get_word_at end number")

assert_eq(lsp.get_word_at(src1, 0, 3), "let", "get_word_at just after word returns word")
assert_nil(lsp.get_word_at(nil, 0, 0), "get_word_at nil content")
assert_nil(lsp.get_word_at(src1, 5, 0), "get_word_at out of bounds line")

let src_multi = "line one" + nl + "line two" + nl + "line three"
assert_eq(lsp.get_word_at(src_multi, 1, 5), "two", "get_word_at multi-line second line")
assert_eq(lsp.get_word_at(src_multi, 2, 5), "three", "get_word_at multi-line third line")

let src_under = "my_var = 10"
assert_eq(lsp.get_word_at(src_under, 0, 2), "my_var", "get_word_at underscore in word")

assert_nil(lsp.get_word_at(src1, 0, 50), "get_word_at out of bounds character")

# =========================================================
# is_word_char tests (6)
# =========================================================
print "is_word_char"

assert_true(lsp.is_word_char("a"), "is_word_char lowercase a")
assert_true(lsp.is_word_char("Z"), "is_word_char uppercase Z")
assert_true(lsp.is_word_char("5"), "is_word_char digit 5")
assert_true(lsp.is_word_char("_"), "is_word_char underscore")
assert_false(lsp.is_word_char(" "), "is_word_char space")
assert_false(lsp.is_word_char("("), "is_word_char paren")

# =========================================================
# get_initialize_result tests (4)
# =========================================================
print "get_initialize_result"

let init_result = lsp.get_initialize_result()
assert_contains(init_result, "capabilities", "init result has capabilities")
assert_contains(init_result, "sage-lsp", "init result has sage-lsp")
assert_contains(init_result, "completionProvider", "init result has completionProvider")
assert_contains(init_result, "hoverProvider", "init result has hoverProvider")

# =========================================================
# build_completion_response tests (3)
# =========================================================
print "build_completion_response"

let comp_resp = lsp.build_completion_response("1")
assert_contains(comp_resp, "result", "completion response has result")
assert_contains(comp_resp, "let", "completion response contains let")
assert_contains(comp_resp, "jsonrpc", "completion response has jsonrpc")

# =========================================================
# build_hover_response tests (4)
# =========================================================
print "build_hover_response"

let hover_store = lsp.DocumentStore()
let hdocs = lsp.build_hover_docs()

let hover_null = lsp.build_hover_response("1", "let x = 1", 0, 50, hdocs)
assert_contains(hover_null, "null", "hover response null for out of bounds")

let hover_unknown = lsp.build_hover_response("1", "foobar123xyz", 0, 3, hdocs)
assert_contains(hover_unknown, "null", "hover response null for unknown word")

let hover_let = lsp.build_hover_response("1", "let x = 1", 0, 0, hdocs)
assert_contains(hover_let, "contents", "hover response for let has contents")
assert_contains(hover_let, "markdown", "hover response for let has markdown kind")

# =========================================================
# generate_diagnostics tests (2)
# =========================================================
print "generate_diagnostics"

let diags = lsp.generate_diagnostics("let x = 1", "test.sage")
assert_eq(len(diags), 0, "generate_diagnostics returns empty array")
let diags2 = lsp.generate_diagnostics("", "test.sage")
assert_eq(len(diags2), 0, "generate_diagnostics empty content returns empty array")

# =========================================================
# build_diagnostics_notification tests (3)
# =========================================================
print "build_diagnostics_notification"

let diag_notif = lsp.build_diagnostics_notification("file:///test.sage", "let x = 1")
assert_contains(diag_notif, "publishDiagnostics", "diag notification has method")
assert_contains(diag_notif, "file:///test.sage", "diag notification has uri")
assert_contains(diag_notif, "diagnostics", "diag notification has diagnostics key")

# =========================================================
# build_clear_diagnostics_notification tests (3)
# =========================================================
print "build_clear_diagnostics_notification"

let clear_notif = lsp.build_clear_diagnostics_notification("file:///test.sage")
assert_contains(clear_notif, "publishDiagnostics", "clear diag has method")
assert_contains(clear_notif, "file:///test.sage", "clear diag has uri")
assert_contains(clear_notif, "diagnostics", "clear diag has diagnostics key")

# =========================================================
# make_completion tests (3)
# =========================================================
print "make_completion"

let mc = lsp.make_completion("test_label", 14, "test detail")
assert_eq(mc["label"], "test_label", "make_completion label")
assert_eq(mc["kind"], 14, "make_completion kind")
assert_eq(mc["detail"], "test detail", "make_completion detail")

# =========================================================
# Summary
# =========================================================
print nl + "LSP Tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All LSP tests passed!"
