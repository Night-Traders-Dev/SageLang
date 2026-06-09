gc_disable()
# EXPECT: GET
# EXPECT: https://example.com
# EXPECT: OK
# EXPECT: Not Found
# EXPECT: true
# EXPECT: true
# EXPECT: false

import net.request

let req = request.create("GET", "https://example.com")
print req["method"]
print req["url"]

print request.status_text(200)
print request.status_text(404)

# Test response classification helpers with mock response
let mock_ok = {}
mock_ok["status"] = 200
print request.is_ok(mock_ok)

let mock_err = {}
mock_err["status"] = 500
print request.is_server_error(mock_err)
print request.is_ok(mock_err)
