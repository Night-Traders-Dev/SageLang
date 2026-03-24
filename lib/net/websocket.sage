# WebSocket protocol helpers
# Frame building/parsing per RFC 6455
# Use with native socket/tcp modules for transport

# WebSocket opcodes
let OP_CONTINUATION = 0
let OP_TEXT = 1
let OP_BINARY = 2
let OP_CLOSE = 8
let OP_PING = 9
let OP_PONG = 10

# Close status codes
let CLOSE_NORMAL = 1000
let CLOSE_GOING_AWAY = 1001
let CLOSE_PROTOCOL_ERROR = 1002
let CLOSE_UNSUPPORTED = 1003
let CLOSE_NO_STATUS = 1005
let CLOSE_ABNORMAL = 1006
let CLOSE_INVALID_DATA = 1007
let CLOSE_POLICY = 1008
let CLOSE_TOO_LARGE = 1009
let CLOSE_EXTENSION = 1010
let CLOSE_UNEXPECTED = 1011

proc opcode_name(op):
    if op == 0:
        return "continuation"
    if op == 1:
        return "text"
    if op == 2:
        return "binary"
    if op == 8:
        return "close"
    if op == 9:
        return "ping"
    if op == 10:
        return "pong"
    return "unknown"

# Build a WebSocket frame (server-side, no masking)
# Returns byte array
proc build_frame(opcode, payload, fin):
    let frame = []
    # Byte 0: FIN + opcode
    let b0 = opcode & 15
    if fin:
        b0 = b0 + 128
    push(frame, b0)

    # Byte 1+: payload length (no mask for server)
    let plen = len(payload)
    if plen < 126:
        push(frame, plen)
    if plen >= 126 and plen < 65536:
        push(frame, 126)
        push(frame, (plen >> 8) & 255)
        push(frame, plen & 255)
    if plen >= 65536:
        push(frame, 127)
        # 8-byte extended length
        push(frame, 0)
        push(frame, 0)
        push(frame, 0)
        push(frame, 0)
        push(frame, (plen >> 24) & 255)
        push(frame, (plen >> 16) & 255)
        push(frame, (plen >> 8) & 255)
        push(frame, plen & 255)

    # Payload
    for i in range(plen):
        push(frame, payload[i])

    return frame

# Build a text frame from a string
proc text_frame(text):
    let payload = []
    for i in range(len(text)):
        push(payload, ord(text[i]))
    return build_frame(1, payload, true)

# Build a binary frame
proc binary_frame(data):
    return build_frame(2, data, true)

# Build a close frame
proc close_frame(code):
    let payload = []
    push(payload, (code >> 8) & 255)
    push(payload, code & 255)
    return build_frame(8, payload, true)

# Build a ping frame
proc ping_frame(data):
    return build_frame(9, data, true)

# Build a pong frame
proc pong_frame(data):
    return build_frame(10, data, true)

# Parse a WebSocket frame from raw bytes
# Returns dict with: fin, opcode, masked, length, mask_key, payload, total_size
proc parse_frame(bs, off):
    if off + 2 > len(bs):
        return nil

    let frame = {}
    let b0 = bs[off]
    let b1 = bs[off + 1]

    frame["fin"] = (b0 & 128) != 0
    frame["opcode"] = b0 & 15
    frame["opcode_name"] = opcode_name(b0 & 15)
    frame["masked"] = (b1 & 128) != 0

    let plen = b1 & 127
    let header_size = 2

    if plen == 126:
        if off + 4 > len(bs):
            return nil
        plen = bs[off + 2] * 256 + bs[off + 3]
        header_size = 4
    if plen == 127:
        if off + 10 > len(bs):
            return nil
        plen = bs[off + 6] * 16777216 + bs[off + 7] * 65536 + bs[off + 8] * 256 + bs[off + 9]
        header_size = 10

    frame["length"] = plen

    let mask_key = []
    if frame["masked"]:
        if off + header_size + 4 > len(bs):
            return nil
        for i in range(4):
            push(mask_key, bs[off + header_size + i])
        header_size = header_size + 4
    frame["mask_key"] = mask_key

    # Extract and unmask payload
    let payload = []
    let data_off = off + header_size
    if data_off + plen > len(bs):
        return nil

    for i in range(plen):
        let byte_val = bs[data_off + i]
        if frame["masked"]:
            byte_val = byte_val ^ mask_key[i & 3]
        push(payload, byte_val)

    frame["payload"] = payload
    frame["total_size"] = header_size + plen
    return frame

# Convert payload bytes to string
proc payload_to_string(payload):
    let result = ""
    for i in range(len(payload)):
        result = result + chr(payload[i])
    return result

# Generate the WebSocket upgrade response headers
# sec_key is the Sec-WebSocket-Key from the client
proc upgrade_response(sec_key):
    # In a real implementation, we'd compute SHA-1 of key+GUID and base64 encode.
    # Here we provide the response template.
    let resp = "HTTP/1.1 101 Switching Protocols" + chr(13) + chr(10)
    resp = resp + "Upgrade: websocket" + chr(13) + chr(10)
    resp = resp + "Connection: Upgrade" + chr(13) + chr(10)
    resp = resp + "Sec-WebSocket-Accept: " + sec_key + chr(13) + chr(10)
    resp = resp + chr(13) + chr(10)
    return resp

# Build a client upgrade request
proc upgrade_request(host, path, key):
    let req = "GET " + path + " HTTP/1.1" + chr(13) + chr(10)
    req = req + "Host: " + host + chr(13) + chr(10)
    req = req + "Upgrade: websocket" + chr(13) + chr(10)
    req = req + "Connection: Upgrade" + chr(13) + chr(10)
    req = req + "Sec-WebSocket-Key: " + key + chr(13) + chr(10)
    req = req + "Sec-WebSocket-Version: 13" + chr(13) + chr(10)
    req = req + chr(13) + chr(10)
    return req
