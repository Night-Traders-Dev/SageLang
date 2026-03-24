# URL parsing, building, and encoding utilities
# Parses URLs into components and provides percent-encoding/decoding

# Parse a URL string into its components
# Returns dict with: scheme, host, port, path, query, fragment, userinfo
proc parse(raw):
    let url = {}
    url["scheme"] = ""
    url["userinfo"] = ""
    url["host"] = ""
    url["port"] = 0
    url["path"] = "/"
    url["query"] = ""
    url["fragment"] = ""
    url["raw"] = raw

    let pos = 0
    let length = len(raw)

    # Parse scheme (e.g., "http://")
    let scheme_end = -1
    let scheme_found = false
    for i in range(length):
        if not scheme_found and i + 2 < length:
            if raw[i] == ":" and raw[i + 1] == "/" and raw[i + 2] == "/":
                scheme_end = i
                scheme_found = true
    if scheme_end > 0:
        let s = ""
        for i in range(scheme_end):
            s = s + raw[i]
        url["scheme"] = s
        pos = scheme_end + 3

    # Parse authority (userinfo@host:port)
    let auth_end = length
    let auth_found = false
    for i in range(length - pos):
        if not auth_found:
            let idx = pos + i
            if raw[idx] == "/" or raw[idx] == "?" or raw[idx] == "#":
                auth_end = idx
                auth_found = true

    # Extract authority substring
    let auth = ""
    for i in range(auth_end - pos):
        auth = auth + raw[pos + i]
    pos = auth_end

    # Check for userinfo@
    let at_pos = -1
    for i in range(len(auth)):
        if auth[i] == "@":
            at_pos = i

    let host_part = auth
    if at_pos >= 0:
        let ui = ""
        for i in range(at_pos):
            ui = ui + auth[i]
        url["userinfo"] = ui
        host_part = ""
        for i in range(len(auth) - at_pos - 1):
            host_part = host_part + auth[at_pos + 1 + i]

    # Check for :port
    let colon_pos = -1
    for i in range(len(host_part)):
        if host_part[i] == ":":
            colon_pos = i

    if colon_pos >= 0:
        let h = ""
        for i in range(colon_pos):
            h = h + host_part[i]
        url["host"] = h
        let port_str = ""
        for i in range(len(host_part) - colon_pos - 1):
            port_str = port_str + host_part[colon_pos + 1 + i]
        url["port"] = tonumber(port_str)
    else:
        url["host"] = host_part
        # Default ports
        if url["scheme"] == "http":
            url["port"] = 80
        if url["scheme"] == "https":
            url["port"] = 443
        if url["scheme"] == "ftp":
            url["port"] = 21
        if url["scheme"] == "ssh":
            url["port"] = 22
        if url["scheme"] == "ws":
            url["port"] = 80
        if url["scheme"] == "wss":
            url["port"] = 443

    # Parse path
    if pos < length and raw[pos] == "/":
        let p = ""
        while pos < length and raw[pos] != "?" and raw[pos] != "#":
            p = p + raw[pos]
            pos = pos + 1
        url["path"] = p

    # Parse query
    if pos < length and raw[pos] == "?":
        pos = pos + 1
        let q = ""
        while pos < length and raw[pos] != "#":
            q = q + raw[pos]
            pos = pos + 1
        url["query"] = q

    # Parse fragment
    if pos < length and raw[pos] == "#":
        pos = pos + 1
        let f = ""
        while pos < length:
            f = f + raw[pos]
            pos = pos + 1
        url["fragment"] = f

    return url

# Build a URL string from components
proc build(url):
    let result = ""
    if len(url["scheme"]) > 0:
        result = url["scheme"] + "://"
    if len(url["userinfo"]) > 0:
        result = result + url["userinfo"] + "@"
    result = result + url["host"]
    # Only include port if non-default
    let include_port = true
    if url["scheme"] == "http" and url["port"] == 80:
        include_port = false
    if url["scheme"] == "https" and url["port"] == 443:
        include_port = false
    if url["port"] == 0:
        include_port = false
    if include_port:
        result = result + ":" + str(url["port"])
    result = result + url["path"]
    if len(url["query"]) > 0:
        result = result + "?" + url["query"]
    if len(url["fragment"]) > 0:
        result = result + "#" + url["fragment"]
    return result

# Percent-encode a string (for URL components)
proc encode(text):
    let result = ""
    let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
    let hex_digits = "0123456789ABCDEF"
    for i in range(len(text)):
        let c = text[i]
        let is_safe = false
        for j in range(len(unreserved)):
            if not is_safe and c == unreserved[j]:
                is_safe = true
        if is_safe:
            result = result + c
        else:
            let code = ord(c)
            let hi = (code >> 4) & 15
            let lo = code & 15
            result = result + "%" + hex_digits[hi] + hex_digits[lo]
    return result

# Decode a percent-encoded string
proc decode(text):
    let result = ""
    let i = 0
    while i < len(text):
        if text[i] == "%" and i + 2 < len(text):
            let hi = hex_val(text[i + 1])
            let lo = hex_val(text[i + 2])
            if hi >= 0 and lo >= 0:
                result = result + chr(hi * 16 + lo)
                i = i + 3
            else:
                result = result + text[i]
                i = i + 1
        if text[i] == "+" and i < len(text):
            result = result + " "
            i = i + 1
        if i < len(text) and text[i] != "%" and text[i] != "+":
            result = result + text[i]
            i = i + 1
    return result

proc hex_val(c):
    let code = ord(c)
    if code >= 48 and code <= 57:
        return code - 48
    if code >= 65 and code <= 70:
        return code - 55
    if code >= 97 and code <= 102:
        return code - 87
    return -1

# Parse query string "key=val&key2=val2" into a dict
proc parse_query(query_str):
    let params = {}
    if len(query_str) == 0:
        return params
    let current_key = ""
    let current_val = ""
    let in_value = false
    for i in range(len(query_str)):
        let c = query_str[i]
        if c == "=":
            in_value = true
        if c == "&":
            if len(current_key) > 0:
                params[decode(current_key)] = decode(current_val)
            current_key = ""
            current_val = ""
            in_value = false
        if c != "=" and c != "&":
            if in_value:
                current_val = current_val + c
            else:
                current_key = current_key + c
    if len(current_key) > 0:
        params[decode(current_key)] = decode(current_val)
    return params

# Build a query string from a dict
proc build_query(params):
    let result = ""
    let keys = dict_keys(params)
    for i in range(len(keys)):
        if i > 0:
            result = result + "&"
        result = result + encode(keys[i]) + "=" + encode(params[keys[i]])
    return result

# Join a base URL with a relative path
proc resolve(base_url, relative):
    if len(relative) == 0:
        return base_url
    # Absolute URL
    let has_scheme = false
    for i in range(len(relative)):
        if not has_scheme and i + 2 < len(relative):
            if relative[i] == ":" and relative[i + 1] == "/" and relative[i + 2] == "/":
                has_scheme = true
    if has_scheme:
        return relative
    let base = parse(base_url)
    if len(relative) > 0 and relative[0] == "/":
        base["path"] = relative
        base["query"] = ""
        base["fragment"] = ""
    else:
        # Relative to current path directory
        let dir = ""
        let last_slash = 0
        for i in range(len(base["path"])):
            if base["path"][i] == "/":
                last_slash = i
        for i in range(last_slash + 1):
            dir = dir + base["path"][i]
        base["path"] = dir + relative
        base["query"] = ""
        base["fragment"] = ""
    return build(base)
