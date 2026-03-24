gc_disable()
# Unicode and UTF-8 utilities
# Provides codepoint classification, UTF-8 encoding/decoding, and string normalization

# ============================================================================
# Character classification
# ============================================================================

proc is_ascii(c):
    return ord(c) < 128

proc is_upper(c):
    let code = ord(c)
    return code >= 65 and code <= 90

proc is_lower(c):
    let code = ord(c)
    return code >= 97 and code <= 122

proc is_alpha(c):
    return is_upper(c) or is_lower(c)

proc is_digit(c):
    let code = ord(c)
    return code >= 48 and code <= 57

proc is_alnum(c):
    return is_alpha(c) or is_digit(c)

proc is_whitespace(c):
    let code = ord(c)
    return code == 32 or code == 9 or code == 10 or code == 13 or code == 12 or code == 11

proc is_printable(c):
    let code = ord(c)
    return code >= 32 and code < 127

proc is_punctuation(c):
    if is_alnum(c):
        return false
    if is_whitespace(c):
        return false
    let code = ord(c)
    return code >= 33 and code <= 126

# ============================================================================
# Case conversion
# ============================================================================

proc to_upper(s):
    let result = ""
    for i in range(len(s)):
        let code = ord(s[i])
        if code >= 97 and code <= 122:
            result = result + chr(code - 32)
        else:
            result = result + s[i]
    return result

proc to_lower(s):
    let result = ""
    for i in range(len(s)):
        let code = ord(s[i])
        if code >= 65 and code <= 90:
            result = result + chr(code + 32)
        else:
            result = result + s[i]
    return result

proc to_title(s):
    let result = ""
    let prev_space = true
    for i in range(len(s)):
        if prev_space and is_lower(s[i]):
            result = result + chr(ord(s[i]) - 32)
        else:
            result = result + s[i]
        prev_space = is_whitespace(s[i])
    return result

proc swap_case(s):
    let result = ""
    for i in range(len(s)):
        if is_upper(s[i]):
            result = result + chr(ord(s[i]) + 32)
        if is_lower(s[i]):
            result = result + chr(ord(s[i]) - 32)
        if not is_upper(s[i]) and not is_lower(s[i]):
            result = result + s[i]
    return result

# ============================================================================
# UTF-8 encoding/decoding
# ============================================================================

# Encode a single codepoint to UTF-8 bytes
proc encode_codepoint(cp):
    let bytes = []
    if cp < 128:
        push(bytes, cp)
    if cp >= 128 and cp < 2048:
        push(bytes, 192 + (cp >> 6))
        push(bytes, 128 + (cp & 63))
    if cp >= 2048 and cp < 65536:
        push(bytes, 224 + (cp >> 12))
        push(bytes, 128 + ((cp >> 6) & 63))
        push(bytes, 128 + (cp & 63))
    if cp >= 65536:
        push(bytes, 240 + (cp >> 18))
        push(bytes, 128 + ((cp >> 12) & 63))
        push(bytes, 128 + ((cp >> 6) & 63))
        push(bytes, 128 + (cp & 63))
    return bytes

# Decode UTF-8 bytes starting at offset, returns {codepoint, bytes_consumed}
proc decode_codepoint(bytes, offset):
    if offset >= len(bytes):
        return nil
    let b0 = bytes[offset]
    if b0 < 128:
        let r = {}
        r["codepoint"] = b0
        r["bytes"] = 1
        return r
    if (b0 & 224) == 192 and offset + 1 < len(bytes):
        let cp = ((b0 & 31) << 6) + (bytes[offset + 1] & 63)
        let r = {}
        r["codepoint"] = cp
        r["bytes"] = 2
        return r
    if (b0 & 240) == 224 and offset + 2 < len(bytes):
        let cp = ((b0 & 15) << 12) + ((bytes[offset + 1] & 63) << 6) + (bytes[offset + 2] & 63)
        let r = {}
        r["codepoint"] = cp
        r["bytes"] = 3
        return r
    if (b0 & 248) == 240 and offset + 3 < len(bytes):
        let cp = ((b0 & 7) << 18) + ((bytes[offset + 1] & 63) << 12) + ((bytes[offset + 2] & 63) << 6) + (bytes[offset + 3] & 63)
        let r = {}
        r["codepoint"] = cp
        r["bytes"] = 4
        return r
    let r = {}
    r["codepoint"] = 65533
    r["bytes"] = 1
    return r

# Count UTF-8 codepoints in a byte array
proc codepoint_count(bytes):
    let count = 0
    let i = 0
    while i < len(bytes):
        let d = decode_codepoint(bytes, i)
        if d == nil:
            return count
        count = count + 1
        i = i + d["bytes"]
    return count

# ============================================================================
# String utilities
# ============================================================================

proc trim(s):
    let start = 0
    while start < len(s) and is_whitespace(s[start]):
        start = start + 1
    let end_idx = len(s) - 1
    while end_idx > start and is_whitespace(s[end_idx]):
        end_idx = end_idx - 1
    let result = ""
    for i in range(end_idx - start + 1):
        result = result + s[start + i]
    return result

proc trim_left(s):
    let start = 0
    while start < len(s) and is_whitespace(s[start]):
        start = start + 1
    let result = ""
    for i in range(len(s) - start):
        result = result + s[start + i]
    return result

proc trim_right(s):
    let end_idx = len(s) - 1
    while end_idx >= 0 and is_whitespace(s[end_idx]):
        end_idx = end_idx - 1
    let result = ""
    for i in range(end_idx + 1):
        result = result + s[i]
    return result

proc center(s, width, pad_char):
    if len(s) >= width:
        return s
    let total_pad = width - len(s)
    let left_pad = (total_pad / 2) | 0
    let right_pad = total_pad - left_pad
    let result = ""
    for i in range(left_pad):
        result = result + pad_char
    result = result + s
    for i in range(right_pad):
        result = result + pad_char
    return result

proc repeat_str(s, n):
    let result = ""
    for i in range(n):
        result = result + s
    return result

proc reverse(s):
    let result = ""
    let i = len(s) - 1
    while i >= 0:
        result = result + s[i]
        i = i - 1
    return result

proc count_char(s, ch):
    let count = 0
    for i in range(len(s)):
        if s[i] == ch:
            count = count + 1
    return count

proc starts_with(s, prefix):
    if len(prefix) > len(s):
        return false
    for i in range(len(prefix)):
        if s[i] != prefix[i]:
            return false
    return true

proc ends_with(s, suffix):
    if len(suffix) > len(s):
        return false
    let off = len(s) - len(suffix)
    for i in range(len(suffix)):
        if s[off + i] != suffix[i]:
            return false
    return true
