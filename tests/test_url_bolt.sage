import net.url as url
import assert

proc test_encode():
    assert.assert_equal(url.encode("abc"), "abc", "Simple encode failed")
    assert.assert_equal(url.encode(" "), "%20", "Space encode failed")
    assert.assert_equal(url.encode("!"), "%21", "Symbol encode failed")
    print "test_encode passed"

proc test_parse():
    let u = url.parse("http://user:pass@example.com:8080/path?q=v#f")
    assert.assert_equal(u["scheme"], "http", "scheme failed")
    assert.assert_equal(u["userinfo"], "user:pass", "userinfo failed")
    assert.assert_equal(u["host"], "example.com", "host failed")
    assert.assert_equal(u["port"], 8080, "port failed")
    assert.assert_equal(u["path"], "/path", "path failed")
    assert.assert_equal(u["query"], "q=v", "query failed")
    assert.assert_equal(u["fragment"], "f", "fragment failed")
    print "test_parse passed"

proc test_build():
    let u = {
        "scheme": "https",
        "userinfo": "",
        "host": "google.com",
        "port": 443,
        "path": "/search",
        "query": "q=sage",
        "fragment": ""
    }
    assert.assert_equal(url.build(u), "https://google.com/search?q=sage", "build failed")
    print "test_build passed"

proc test_query():
    let q = "a=1&b=2"
    let p = url.parse_query(q)
    assert.assert_equal(p["a"], "1", "parse_query a failed")
    assert.assert_equal(p["b"], "2", "parse_query b failed")

    let b = url.build_query(p)
    # Note: dict order is not guaranteed, but for 2 elements it usually is consistent or we can check both
    if b != "a=1&b=2" and b != "b=2&a=1":
        print "ERROR: build_query failed: " + b
        exit(1)
    print "test_query passed"

proc test_resolve():
    assert.assert_equal(url.resolve("http://a/b/c", "d"), "http://a/b/d", "resolve relative failed")
    assert.assert_equal(url.resolve("http://a/b/c", "/d"), "http://a/d", "resolve absolute path failed")
    print "test_resolve passed"

test_encode()
test_parse()
test_build()
test_query()
test_resolve()
