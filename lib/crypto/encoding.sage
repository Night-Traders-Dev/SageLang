# Encoding utilities: Base64, Base16 (hex), Base32

# ============================================================================
# Base64 (RFC 4648)
# ============================================================================

let B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

proc b64_encode(input):
    let data = input
    if type(input) == "string":
        data = str_to_bytes(input)
    let result = ""
    let i = 0
    while i < len(data):
        let a = data[i]
        let b = 0
        let c = 0
        let pad = 0
        if i + 1 < len(data):
            b = data[i + 1]
        else:
            pad = pad + 1
        if i + 2 < len(data):
            c = data[i + 2]
        else:
            pad = pad + 1
        let n = a * 65536 + b * 256 + c
        result = result + B64_CHARS[(n >> 18) & 63]
        result = result + B64_CHARS[(n >> 12) & 63]
        if pad < 2:
            result = result + B64_CHARS[(n >> 6) & 63]
        else:
            result = result + "="
        if pad < 1:
            result = result + B64_CHARS[n & 63]
        else:
            result = result + "="
        i = i + 3
    return result

proc b64_char_val(c):
    let code = ord(c)
    if code >= 65 and code <= 90:
        return code - 65
    if code >= 97 and code <= 122:
        return code - 71
    if code >= 48 and code <= 57:
        return code + 4
    if c == "+":
        return 62
    if c == "/":
        return 63
    return -1

proc b64_decode(encoded):
    let result = []
    let i = 0
    while i < len(encoded):
        let a = b64_char_val(encoded[i])
        let b = 0
        let c = 0
        let d = 0
        if i + 1 < len(encoded):
            b = b64_char_val(encoded[i + 1])
        if i + 2 < len(encoded) and encoded[i + 2] != "=":
            c = b64_char_val(encoded[i + 2])
        else:
            c = -1
        if i + 3 < len(encoded) and encoded[i + 3] != "=":
            d = b64_char_val(encoded[i + 3])
        else:
            d = -1
        if a < 0 or b < 0:
            i = len(encoded)
        else:
            push(result, (a * 4 + (b >> 4)) & 255)
            if c >= 0:
                push(result, ((b & 15) * 16 + (c >> 2)) & 255)
            if d >= 0:
                push(result, ((c & 3) * 64 + d) & 255)
            i = i + 4
    return result

proc b64_decode_string(encoded):
    let bytes = b64_decode(encoded)
    let result = ""
    for i in range(len(bytes)):
        result = result + chr(bytes[i])
    return result

# URL-safe Base64 (RFC 4648 section 5)
proc b64url_encode(input):
    let std = b64_encode(input)
    let result = ""
    for i in range(len(std)):
        if std[i] == "+":
            result = result + "-"
        if std[i] == "/":
            result = result + "_"
        if std[i] == "=":
            let skip = true
        if std[i] != "+" and std[i] != "/" and std[i] != "=":
            result = result + std[i]
    return result

proc b64url_decode(encoded):
    let std = ""
    for i in range(len(encoded)):
        if encoded[i] == "-":
            std = std + "+"
        if encoded[i] == "_":
            std = std + "/"
        if encoded[i] != "-" and encoded[i] != "_":
            std = std + encoded[i]
    # Add padding
    while (len(std) & 3) != 0:
        std = std + "="
    return b64_decode(std)

# ============================================================================
# Hex (Base16)
# ============================================================================

proc hex_encode(input):
    let data = input
    if type(input) == "string":
        data = str_to_bytes(input)
    let digits = "0123456789abcdef"
    let result = ""
    for i in range(len(data)):
        result = result + digits[(data[i] >> 4) & 15] + digits[data[i] & 15]
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

proc hex_decode(encoded):
    let result = []
    let i = 0
    while i + 1 < len(encoded):
        let hi = hex_val(encoded[i])
        let lo = hex_val(encoded[i + 1])
        if hi >= 0 and lo >= 0:
            push(result, hi * 16 + lo)
        i = i + 2
    return result

proc hex_decode_string(encoded):
    let bytes = hex_decode(encoded)
    let result = ""
    for i in range(len(bytes)):
        result = result + chr(bytes[i])
    return result

# ============================================================================
# Helpers
# ============================================================================

proc str_to_bytes(s):
    let bytes = []
    for i in range(len(s)):
        push(bytes, ord(s[i]))
    return bytes

proc bytes_to_str(bytes):
    let result = ""
    for i in range(len(bytes)):
        result = result + chr(bytes[i])
    return result
