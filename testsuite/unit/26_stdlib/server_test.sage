gc_disable()
# EXPECT: GET
# EXPECT: /api/test
# EXPECT: q=sage
# EXPECT: text/html
# EXPECT: true

import net.server

# Parse a raw HTTP request
let raw = "GET /api/test?q=sage HTTP/1.1" + chr(13) + chr(10) + "Host: localhost" + chr(13) + chr(10) + "Accept: text/html" + chr(13) + chr(10) + chr(13) + chr(10)
let req = server.parse_request(raw)
print req["method"]
print req["path"]
print req["query"]
print req["headers"]["accept"]

# Test router
let router = server.create_router()

proc handler(r):
    return server.response_text("hello")

server.get_route(router, "GET", handler)

# Test response building
let resp = server.response_json("{}")
let has_json = false
for i in range(len(resp)):
    if i + 15 < len(resp):
        let sub = resp[i] + resp[i+1] + resp[i+2] + resp[i+3] + resp[i+4] + resp[i+5] + resp[i+6] + resp[i+7] + resp[i+8] + resp[i+9] + resp[i+10] + resp[i+11] + resp[i+12] + resp[i+13] + resp[i+14] + resp[i+15]
        if sub == "application/json":
            has_json = true
            i = len(resp)
print has_json
