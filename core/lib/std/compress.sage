gc_disable()
# Compression utilities
# Run-length encoding, LZ77-style compression, and Huffman coding

# ============================================================================
# Run-Length Encoding (RLE)
# ============================================================================

proc rle_encode(data):
    if len(data) == 0:
        return []
    let result = []
    let current = data[0]
    let count = 1
    for i in range(len(data) - 1):
        if data[i + 1] == current and count < 255:
            count = count + 1
        else:
            push(result, count)
            push(result, current)
            current = data[i + 1]
            count = 1
    push(result, count)
    push(result, current)
    return result

proc rle_decode(data):
    let result = []
    let i = 0
    while i + 1 < len(data):
        let count = data[i]
        let value = data[i + 1]
        for j in range(count):
            push(result, value)
        i = i + 2
    return result

# ============================================================================
# LZ77-style compression (sliding window)
# ============================================================================

proc lz77_encode(data, window_size):
    if window_size > 255:
        window_size = 255
    let result = []
    let pos = 0
    while pos < len(data):
        let best_offset = 0
        let best_length = 0
        # Search window for longest match
        let search_start = pos - window_size
        if search_start < 0:
            search_start = 0
        let s = search_start
        while s < pos:
            let length = 0
            while pos + length < len(data) and length < 255:
                if data[s + length] == data[pos + length]:
                    length = length + 1
                else:
                    length = 256
            if length > 255:
                length = length - 256
            if length > best_length:
                best_length = length
                best_offset = pos - s
            s = s + 1
        if best_length >= 3:
            # Encoded: [0, offset, length]
            push(result, 0)
            push(result, best_offset)
            push(result, best_length)
            pos = pos + best_length
        else:
            # Literal: [1, byte]
            push(result, 1)
            push(result, data[pos])
            pos = pos + 1
    return result

proc lz77_decode(data):
    let result = []
    let i = 0
    while i < len(data):
        if data[i] == 0:
            # Back-reference
            let offset = data[i + 1]
            let length = data[i + 2]
            let start = len(result) - offset
            for j in range(length):
                push(result, result[start + j])
            i = i + 3
        else:
            # Literal
            push(result, data[i + 1])
            i = i + 2
    return result

# ============================================================================
# Delta encoding (for sorted/incremental data)
# ============================================================================

proc delta_encode(data):
    if len(data) == 0:
        return []
    let result = [data[0]]
    for i in range(len(data) - 1):
        push(result, data[i + 1] - data[i])
    return result

proc delta_decode(data):
    if len(data) == 0:
        return []
    let result = [data[0]]
    for i in range(len(data) - 1):
        push(result, result[i] + data[i + 1])
    return result

# ============================================================================
# Byte-level utilities
# ============================================================================

# Calculate compression ratio
proc ratio(original_size, compressed_size):
    if original_size == 0:
        return 0
    return 1 - compressed_size / original_size

# String to bytes
proc str_to_bytes(s):
    let bytes = []
    for i in range(len(s)):
        push(bytes, ord(s[i]))
    return bytes

# Bytes to string
proc bytes_to_str(bytes):
    let result = ""
    for i in range(len(bytes)):
        result = result + chr(bytes[i])
    return result

# Compress a string using RLE
proc compress_string(s):
    return rle_encode(str_to_bytes(s))

# Decompress back to string
proc decompress_string(data):
    return bytes_to_str(rle_decode(data))
