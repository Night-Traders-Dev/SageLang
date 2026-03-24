# HTTP request builder and response handler
# High-level wrapper around the native http module with fluent API

import http

# HTTP methods
let GET = "GET"
let POST = "POST"
let PUT = "PUT"
let DELETE = "DELETE"
let PATCH = "PATCH"
let HEAD = "HEAD"

# Create a request builder
proc create(method, url):
    let req = {}
    req["method"] = method
    req["url"] = url
    req["headers"] = {}
    req["body"] = ""
    req["timeout"] = 30
    req["follow_redirects"] = true
    req["verify_ssl"] = true
    return req

# Set a header on the request
proc set_header(req, key, value):
    req["headers"][key] = value
    return req

# Set the request body
proc set_body(req, body):
    req["body"] = body
    return req

# Set JSON body (auto-sets content-type)
proc set_json(req, body):
    req["body"] = body
    req["headers"]["Content-Type"] = "application/json"
    return req

# Set form body (auto-sets content-type)
proc set_form(req, body):
    req["body"] = body
    req["headers"]["Content-Type"] = "application/x-www-form-urlencoded"
    return req

# Set timeout in seconds
proc set_timeout(req, seconds):
    req["timeout"] = seconds
    return req

# Set authorization header
proc set_auth(req, auth_type, credentials):
    req["headers"]["Authorization"] = auth_type + " " + credentials
    return req

# Set bearer token
proc set_bearer(req, token):
    return set_auth(req, "Bearer", token)

# Set basic auth
proc set_basic_auth(req, username, password):
    return set_auth(req, "Basic", username + ":" + password)

# Set user agent
proc set_user_agent(req, agent):
    req["headers"]["User-Agent"] = agent
    return req

# Execute the request using the native http module
proc send(req):
    let opts = {}
    if len(req["headers"]) > 0:
        let header_list = []
        let keys = dict_keys(req["headers"])
        for i in range(len(keys)):
            push(header_list, keys[i] + ": " + req["headers"][keys[i]])
        opts["headers"] = header_list
    opts["timeout"] = req["timeout"]
    opts["follow_redirects"] = req["follow_redirects"]
    opts["verify_ssl"] = req["verify_ssl"]

    let method = req["method"]
    let url = req["url"]
    let body = req["body"]

    let resp = nil
    if method == "GET":
        resp = http.get(url, opts)
    if method == "POST":
        resp = http.post(url, body, opts)
    if method == "PUT":
        resp = http.put(url, body, opts)
    if method == "DELETE":
        resp = http.delete(url, opts)
    if method == "PATCH":
        resp = http.patch(url, body, opts)
    if method == "HEAD":
        resp = http.head(url, opts)

    return resp

# Convenience: quick GET
proc get(url):
    let req = create("GET", url)
    return send(req)

# Convenience: quick POST with body
proc post(url, body):
    let req = create("POST", url)
    set_body(req, body)
    return send(req)

# Convenience: quick POST JSON
proc post_json(url, body):
    let req = create("POST", url)
    set_json(req, body)
    return send(req)

# Check if response was successful (2xx)
proc is_ok(resp):
    if resp == nil:
        return false
    let status = resp["status"]
    return status >= 200 and status < 300

# Check if response is a redirect
proc is_redirect(resp):
    if resp == nil:
        return false
    let status = resp["status"]
    return status >= 300 and status < 400

# Check if response is a client error
proc is_client_error(resp):
    if resp == nil:
        return false
    let status = resp["status"]
    return status >= 400 and status < 500

# Check if response is a server error
proc is_server_error(resp):
    if resp == nil:
        return false
    let status = resp["status"]
    return status >= 500

# Get status text for common HTTP status codes
proc status_text(code):
    if code == 200:
        return "OK"
    if code == 201:
        return "Created"
    if code == 204:
        return "No Content"
    if code == 301:
        return "Moved Permanently"
    if code == 302:
        return "Found"
    if code == 304:
        return "Not Modified"
    if code == 400:
        return "Bad Request"
    if code == 401:
        return "Unauthorized"
    if code == 403:
        return "Forbidden"
    if code == 404:
        return "Not Found"
    if code == 405:
        return "Method Not Allowed"
    if code == 408:
        return "Request Timeout"
    if code == 409:
        return "Conflict"
    if code == 429:
        return "Too Many Requests"
    if code == 500:
        return "Internal Server Error"
    if code == 502:
        return "Bad Gateway"
    if code == 503:
        return "Service Unavailable"
    if code == 504:
        return "Gateway Timeout"
    return "Unknown"
