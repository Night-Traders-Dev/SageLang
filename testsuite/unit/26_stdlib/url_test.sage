gc_disable()
# EXPECT: https
# EXPECT: example.com
# EXPECT: 443
# EXPECT: /path/to
# EXPECT: key=val
# EXPECT: frag
# EXPECT: hello%20world
# EXPECT: hello world
# EXPECT: val
# EXPECT: https://example.com/path/to?key=val#frag

import net.url

let u = url.parse("https://example.com/path/to?key=val#frag")
print u["scheme"]
print u["host"]
print u["port"]
print u["path"]
print u["query"]
print u["fragment"]

print url.encode("hello world")
print url.decode("hello%20world")

let params = url.parse_query("key=val&name=test")
print params["key"]

print url.build(u)
