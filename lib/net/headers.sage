# HTTP header parsing and building utilities

# Parse raw HTTP headers string into a dict
# Input: "Content-Type: text/html\r\nContent-Length: 42\r\n"
# Output: {"content-type": "text/html", "content-length": "42"}
proc parse(raw):
    let result = {}
    let lines = split_lines(raw)
    for i in range(len(lines)):
        let line = lines[i]
        let colon = -1
        for j in range(len(line)):
            if colon < 0 and line[j] == ":":
                colon = j
        if colon > 0:
            let key = ""
            for j in range(colon):
                let c = line[j]
                let code = ord(c)
                if code >= 65 and code <= 90:
                    key = key + chr(code + 32)
                else:
                    key = key + c
            let val = ""
            let start = colon + 1
            # Skip leading whitespace
            while start < len(line) and line[start] == " ":
                start = start + 1
            for j in range(len(line) - start):
                let c = line[start + j]
                if c != chr(13) and c != chr(10):
                    val = val + c
            result[key] = val
    return result

# Build a headers string from a dict
proc build(headers):
    let result = ""
    let keys = dict_keys(headers)
    for i in range(len(keys)):
        result = result + keys[i] + ": " + headers[keys[i]] + chr(13) + chr(10)
    return result

# Split raw text into lines (by \n or \r\n)
proc split_lines(text):
    let lines = []
    let current = ""
    for i in range(len(text)):
        if text[i] == chr(10):
            if len(current) > 0:
                push(lines, current)
            current = ""
        if text[i] != chr(10) and text[i] != chr(13):
            current = current + text[i]
    if len(current) > 0:
        push(lines, current)
    return lines

# Get a header value (case-insensitive)
proc get(headers, name):
    let lower_name = ""
    for i in range(len(name)):
        let code = ord(name[i])
        if code >= 65 and code <= 90:
            lower_name = lower_name + chr(code + 32)
        else:
            lower_name = lower_name + name[i]
    if dict_has(headers, lower_name):
        return headers[lower_name]
    return nil

# Check if a header exists
proc has(headers, name):
    return get(headers, name) != nil

# Get content type
proc content_type(headers):
    let ct = get(headers, "Content-Type")
    if ct == nil:
        return ""
    # Strip parameters (e.g., "; charset=utf-8")
    let result = ""
    for i in range(len(ct)):
        if ct[i] == ";":
            return result
        result = result + ct[i]
    return result

# Get content length as number
proc content_length(headers):
    let cl = get(headers, "Content-Length")
    if cl == nil:
        return -1
    return tonumber(cl)

# Check if response is JSON
proc is_json(headers):
    let ct = content_type(headers)
    return ct == "application/json"

# Check if response is HTML
proc is_html(headers):
    let ct = content_type(headers)
    return ct == "text/html"

# Common header constants
let CONTENT_TYPE = "Content-Type"
let CONTENT_LENGTH = "Content-Length"
let AUTHORIZATION = "Authorization"
let ACCEPT = "Accept"
let USER_AGENT = "User-Agent"
let HOST = "Host"
let CONNECTION = "Connection"
let CACHE_CONTROL = "Cache-Control"
let COOKIE = "Cookie"
let SET_COOKIE = "Set-Cookie"
let LOCATION = "Location"
let CONTENT_ENCODING = "Content-Encoding"
let TRANSFER_ENCODING = "Transfer-Encoding"
let ORIGIN = "Origin"
let REFERER = "Referer"

# Common content types
let TYPE_JSON = "application/json"
let TYPE_HTML = "text/html"
let TYPE_TEXT = "text/plain"
let TYPE_XML = "application/xml"
let TYPE_FORM = "application/x-www-form-urlencoded"
let TYPE_MULTIPART = "multipart/form-data"
let TYPE_OCTET = "application/octet-stream"
let TYPE_CSS = "text/css"
let TYPE_JS = "application/javascript"
let TYPE_PNG = "image/png"
let TYPE_JPEG = "image/jpeg"
let TYPE_GIF = "image/gif"
let TYPE_SVG = "image/svg+xml"
let TYPE_PDF = "application/pdf"
