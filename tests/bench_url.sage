import net.url as url
import sys

proc bench_encode(n):
    let text = ""
    for i in range(n):
        text = text + "a"
    text = text + ":/?#[]@!$&'()*+,;=" # some characters that need encoding

    let start = sys.clock()
    let encoded = url.encode(text)
    let end = sys.clock()
    print "Encode " + str(len(text)) + " chars: " + str(end - start) + "s"
    return end - start

proc bench_decode(n):
    let text = ""
    for i in range(n):
        text = text + "%20"

    let start = sys.clock()
    let decoded = url.decode(text)
    let end = sys.clock()
    print "Decode " + str(len(text)) + " chars: " + str(end - start) + "s"
    return end - start

proc bench_parse(n):
    let base = "http://user:pass@example.com:8080/path/to/resource?query=value#fragment"
    let long_path = ""
    for i in range(n):
        long_path = long_path + "/abcde"
    let raw = base + long_path

    let start = sys.clock()
    let parsed = url.parse(raw)
    let end = sys.clock()
    print "Parse " + str(len(raw)) + " chars: " + str(end - start) + "s"
    return end - start

proc bench_build(n):
    let components = {
        "scheme": "https",
        "userinfo": "user:pass",
        "host": "example.com",
        "port": 8443,
        "path": "/very/long/path/to/somewhere",
        "query": "a=1&b=2&c=3",
        "fragment": "section-1"
    }
    # Make path very long to stress concatenation
    for i in range(n):
        components["path"] = components["path"] + "/subdir"

    let start = sys.clock()
    let built = url.build(components)
    let end = sys.clock()
    print "Build " + str(len(built)) + " chars: " + str(end - start) + "s"
    return end - start

proc bench_query(n):
    let params = {}
    for i in range(n):
        params["key" + str(i)] = "val" + str(i)

    let start_build = sys.clock()
    let q = url.build_query(params)
    let end_build = sys.clock()
    print "Build query (" + str(n) + " params): " + str(end_build - start_build) + "s"

    let start_parse = sys.clock()
    let p = url.parse_query(q)
    let end_parse = sys.clock()
    print "Parse query (" + str(len(q)) + " chars): " + str(end_parse - start_parse) + "s"
    return end_parse - start_build

print "--- Baseline Benchmarks ---"
bench_encode(5000)
bench_decode(5000)
bench_parse(5000)
bench_build(5000)
bench_query(1000)
