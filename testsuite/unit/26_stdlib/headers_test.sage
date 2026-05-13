gc_disable()
# EXPECT: text/html
# EXPECT: 42
# EXPECT: true
# EXPECT: text/html
# EXPECT: true
# EXPECT: image/png
# EXPECT: application/json

import net.headers

let raw = "Content-Type: text/html" + chr(13) + chr(10) + "Content-Length: 42" + chr(13) + chr(10)
let h = headers.parse(raw)
print headers.get(h, "Content-Type")
print headers.get(h, "Content-Length")
print headers.has(h, "content-type")
print headers.content_type(h)

print headers.is_html(h)

print headers.TYPE_PNG
print headers.TYPE_JSON
