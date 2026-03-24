# SageLang Networking Guide

This guide covers the high-level networking library suite (`lib/net/`) and the native networking modules (`socket`, `tcp`, `http`, `ssl`).

## Architecture

```text
Layer 3:  Sage Net Libraries (lib/net/*.sage)
            |
Layer 2:  Native C Modules (socket, tcp, http, ssl)
            |
Layer 1:  System Libraries (POSIX sockets, libcurl, OpenSSL)
```

**Native modules** (`socket`, `tcp`, `http`, `ssl`) are C-implemented and provide direct access to system networking. They are imported without a prefix:

```sage
import socket   # Low-level POSIX sockets
import tcp      # High-level TCP client/server
import http     # HTTP/HTTPS client via libcurl
import ssl      # OpenSSL bindings
```

**Library modules** (`lib/net/`) provide higher-level abstractions for common networking tasks. They are imported with the `net.` prefix:

```sage
import net.url        # URL parsing and encoding
import net.headers    # HTTP header utilities
import net.request    # HTTP request builder
import net.server     # TCP/HTTP server framework
import net.websocket  # WebSocket protocol
import net.mime       # MIME type lookup
import net.dns        # DNS message parsing
import net.ip         # IP address utilities
```

---

## URL Parsing and Encoding (`net.url`)

### Parsing URLs

```sage
import net.url

let u = url.parse("https://user:pass@api.example.com:8443/v1/users?page=2&limit=10#results")
print u["scheme"]    # https
print u["userinfo"]  # user:pass
print u["host"]      # api.example.com
print u["port"]      # 8443
print u["path"]      # /v1/users
print u["query"]     # page=2&limit=10
print u["fragment"]  # results
```

### Building URLs

```sage
let u = {}
u["scheme"] = "https"
u["host"] = "example.com"
u["port"] = 443
u["path"] = "/api/data"
u["query"] = "format=json"
u["fragment"] = ""
u["userinfo"] = ""
print url.build(u)   # https://example.com/api/data?format=json
```

### Query Strings

```sage
let params = url.parse_query("name=John+Doe&age=30&city=New+York")
print params["name"]  # John Doe
print params["city"]  # New York

let qs = url.build_query(params)
print qs  # name=John%20Doe&age=30&city=New%20York
```

### Percent Encoding

```sage
print url.encode("hello world!")  # hello%20world%21
print url.decode("hello%20world") # hello world
```

### Resolving Relative URLs

```sage
print url.resolve("https://example.com/docs/api.html", "/about")
# https://example.com/about

print url.resolve("https://example.com/docs/api.html", "guide.html")
# https://example.com/docs/guide.html
```

---

## HTTP Headers (`net.headers`)

### Parsing and Querying

```sage
import net.headers

let raw = "Content-Type: application/json" + chr(13) + chr(10) + "Content-Length: 42" + chr(13) + chr(10)
let h = headers.parse(raw)

print headers.get(h, "Content-Type")     # application/json
print headers.content_type(h)            # application/json
print headers.content_length(h)          # 42
print headers.is_json(h)                 # true
print headers.has(h, "Authorization")    # false
```

### Header Constants

```sage
print headers.CONTENT_TYPE    # Content-Type
print headers.TYPE_JSON       # application/json
print headers.TYPE_HTML       # text/html
```

---

## HTTP Request Builder (`net.request`)

### Quick Requests

```sage
import net.request

let resp = request.get("https://httpbin.org/get")
print resp["status"]  # 200
print resp["body"]

let resp2 = request.post("https://httpbin.org/post", "hello")
```

### Fluent Builder

```sage
let req = request.create("POST", "https://api.example.com/data")
request.set_json(req, "{}")
request.set_bearer(req, "my-token")
request.set_timeout(req, 10)
let resp = request.send(req)
```

### Response Helpers

```sage
print request.is_ok(resp)           # true for 2xx
print request.is_redirect(resp)     # true for 3xx
print request.is_client_error(resp) # true for 4xx
print request.is_server_error(resp) # true for 5xx
print request.status_text(404)      # Not Found
```

---

## HTTP Server Framework (`net.server`)

### Basic Server

```sage
import net.server

proc hello(req):
    return server.response_json("{" + chr(34) + "message" + chr(34) + ": " + chr(34) + "Hello!" + chr(34) + "}")

proc not_found(req):
    return server.response_not_found("Not found: " + req["path"])

let srv = server.create_server("0.0.0.0", 8080)
server.get_route(srv["router"], "/", hello)
server.post_route(srv["router"], "/data", hello)
server.set_not_found(srv["router"], not_found)
server.listen_and_serve(srv)
```

### Request Parsing

```sage
let raw_http = "POST /api/users?admin=true HTTP/1.1" + chr(13) + chr(10) + "Content-Type: application/json" + chr(13) + chr(10) + chr(13) + chr(10) + "{}"
let req = server.parse_request(raw_http)
print req["method"]                   # POST
print req["path"]                     # /api/users
print req["query"]                    # admin=true
print req["headers"]["content-type"]  # application/json
print req["body"]                     # {}
```

### Response Builders

```sage
server.response_ok(body, content_type)   # 200
server.response_json(body)               # 200 application/json
server.response_html(body)               # 200 text/html
server.response_text(body)               # 200 text/plain
server.response_not_found(msg)           # 404
server.response_redirect(url)            # 302
server.response_error(code, msg)         # custom error
```

---

## WebSocket Protocol (`net.websocket`)

### Building Frames

```sage
import net.websocket

let frame = websocket.text_frame("Hello, WebSocket!")
let bin = websocket.binary_frame([1, 2, 3, 4])
let close = websocket.close_frame(1000)
let ping = websocket.ping_frame([])
let pong = websocket.pong_frame([])
```

### Parsing Frames

```sage
let parsed = websocket.parse_frame(raw_bytes, 0)
print parsed["fin"]           # true
print parsed["opcode"]        # 1 (text)
print parsed["opcode_name"]   # text
print parsed["length"]        # payload length
print parsed["masked"]        # true (client frames)
let text = websocket.payload_to_string(parsed["payload"])
```

### Upgrade Handshake

```sage
# Client request
let req = websocket.upgrade_request("example.com", "/ws", "dGhlIHNhbXBsZQ==")

# Server response
let resp = websocket.upgrade_response(accept_key)
```

---

## MIME Type Lookup (`net.mime`)

```sage
import net.mime

print mime.lookup("html")          # text/html
print mime.lookup("json")          # application/json
print mime.lookup("png")           # image/png
print mime.lookup("mp4")           # video/mp4
print mime.lookup("wasm")          # application/wasm

print mime.from_filename("style.css")     # text/css
print mime.from_filename("photo.JPEG")    # image/jpeg

print mime.is_text("application/json")    # true
print mime.is_image("image/png")          # true
print mime.category("video/mp4")          # video
```

---

## DNS Message Parsing (`net.dns`)

### Building Queries

```sage
import net.dns

let query = dns.build_query("example.com", dns.TYPE_A, 1234)
# query is a byte array ready to send over UDP port 53
```

### Parsing Responses

```sage
let msg = dns.parse_message(response_bytes)
print msg["header"]["rcode_name"]     # NOERROR
print msg["header"]["ancount"]        # number of answers

for i in range(len(msg["answers"])):
    let rr = msg["answers"][i]
    print rr["name"]                  # example.com
    print rr["type_name"]             # A
    print rr["ttl"]                   # 300
    print rr["address"]               # 93.184.216.34
```

### Record Types

```sage
dns.TYPE_A      # 1 - IPv4 address
dns.TYPE_AAAA   # 28 - IPv6 address
dns.TYPE_CNAME  # 5 - Canonical name
dns.TYPE_MX     # 15 - Mail exchange
dns.TYPE_NS     # 2 - Name server
dns.TYPE_TXT    # 16 - Text record
dns.TYPE_SRV    # 33 - Service locator
dns.TYPE_SOA    # 6 - Start of authority
dns.TYPE_PTR    # 12 - Pointer (reverse DNS)
```

---

## IP Address Utilities (`net.ip`)

### Parsing and Validation

```sage
import net.ip

print ip.is_valid_v4("192.168.1.1")  # true
print ip.is_valid_v4("999.1.1.1")    # false

let n = ip.parse_v4("10.0.0.1")
print ip.to_string_v4(n)             # 10.0.0.1
```

### CIDR Subnets

```sage
let cidr = ip.parse_cidr("192.168.1.0/24")
print cidr["network_str"]      # 192.168.1.0
print cidr["mask_str"]         # 255.255.255.0
print cidr["broadcast_str"]    # 192.168.1.255
print cidr["host_count"]       # 254

print ip.in_subnet("192.168.1.100", "192.168.1.0/24")  # true
print ip.in_subnet("10.0.0.1", "192.168.1.0/24")       # false
```

### Address Classification

```sage
print ip.is_private("10.0.0.1")       # true (RFC 1918)
print ip.is_private("8.8.8.8")        # false
print ip.is_loopback("127.0.0.1")     # true
print ip.is_link_local("169.254.1.1") # true
print ip.is_multicast("224.0.0.1")    # true
print ip.address_class("192.168.1.1") # C
```

### Netmask Conversion

```sage
print ip.mask_to_prefix("255.255.255.0")  # 24
print ip.prefix_to_mask(16)               # 255.255.0.0
```

### Well-Known Addresses

```sage
print ip.LOCALHOST       # 127.0.0.1
print ip.ANY             # 0.0.0.0
print ip.DNS_GOOGLE      # 8.8.8.8
print ip.DNS_CLOUDFLARE  # 1.1.1.1
```

---

## Module Reference

| Module | Import | Key Functions |
|--------|--------|---------------|
| `url` | `import net.url` | `parse`, `build`, `encode`, `decode`, `parse_query`, `build_query`, `resolve` |
| `headers` | `import net.headers` | `parse`, `build`, `get`, `has`, `content_type`, `content_length`, `is_json`, `is_html` |
| `request` | `import net.request` | `create`, `send`, `get`, `post`, `post_json`, `set_header`, `set_bearer`, `is_ok`, `status_text` |
| `server` | `import net.server` | `create_server`, `listen_and_serve`, `parse_request`, `create_router`, `get_route`, `post_route`, `response_json`, `response_html` |
| `websocket` | `import net.websocket` | `text_frame`, `binary_frame`, `close_frame`, `ping_frame`, `parse_frame`, `payload_to_string`, `upgrade_request` |
| `mime` | `import net.mime` | `lookup`, `from_filename`, `is_text`, `is_image`, `category` |
| `dns` | `import net.dns` | `build_query`, `parse_message`, `parse_header`, `encode_name`, `read_name`, `type_name` |
| `ip` | `import net.ip` | `parse_v4`, `to_string_v4`, `is_valid_v4`, `parse_cidr`, `in_subnet`, `is_private`, `is_loopback`, `address_class`, `mask_to_prefix` |
