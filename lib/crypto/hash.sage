# Cryptographic hash functions
# Pure Sage implementations of MD5, SHA-1, SHA-256

# ============================================================================
# Utility functions
# ============================================================================

proc u32(x):
    return x & 4294967295

proc rotl32(x, n):
    return u32((x << n) | (x >> (32 - n)))

proc rotr32(x, n):
    return u32((x >> n) | (x << (32 - n)))

proc hex_byte(b):
    let digits = "0123456789abcdef"
    return digits[(b >> 4) & 15] + digits[b & 15]

proc to_hex(bytes):
    let result = ""
    for i in range(len(bytes)):
        result = result + hex_byte(bytes[i])
    return result

# Pad a message to a multiple of 64 bytes (512 bits) per MD5/SHA spec
proc pad_message(msg):
    let msg_len = len(msg)
    let bit_len = msg_len * 8
    let padded = []
    for i in range(msg_len):
        push(padded, msg[i])
    # Append 0x80
    push(padded, 128)
    # Pad with zeros until length = 56 mod 64
    while (len(padded) & 63) != 56:
        push(padded, 0)
    return padded

# Append 64-bit length in little-endian (for MD5)
proc append_length_le(padded, bit_len):
    push(padded, bit_len & 255)
    push(padded, (bit_len >> 8) & 255)
    push(padded, (bit_len >> 16) & 255)
    push(padded, (bit_len >> 24) & 255)
    push(padded, 0)
    push(padded, 0)
    push(padded, 0)
    push(padded, 0)
    return padded

# Append 64-bit length in big-endian (for SHA)
proc append_length_be(padded, bit_len):
    push(padded, 0)
    push(padded, 0)
    push(padded, 0)
    push(padded, 0)
    push(padded, (bit_len >> 24) & 255)
    push(padded, (bit_len >> 16) & 255)
    push(padded, (bit_len >> 8) & 255)
    push(padded, bit_len & 255)
    return padded

# Convert string to byte array
proc string_to_bytes(s):
    let bytes = []
    for i in range(len(s)):
        push(bytes, ord(s[i]))
    return bytes

# ============================================================================
# SHA-256
# ============================================================================

proc sha256_k():
    return [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580, 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986, 2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895, 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037, 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344, 430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779, 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]

proc sha256(input):
    let msg = input
    if type(input) == "string":
        msg = string_to_bytes(input)

    let bit_len = len(msg) * 8
    let padded = pad_message(msg)
    padded = append_length_be(padded, bit_len)

    # Initial hash values
    let h0 = 1779033703
    let h1 = 3144134277
    let h2 = 1013904242
    let h3 = 2773480762
    let h4 = 1359893119
    let h5 = 2600822924
    let h6 = 528734635
    let h7 = 1541459225

    let k = sha256_k()
    let num_blocks = (len(padded) / 64) | 0

    for block in range(num_blocks):
        let off = block * 64
        # Prepare message schedule
        let w = []
        for i in range(16):
            let val = padded[off + i * 4] * 16777216 + padded[off + i * 4 + 1] * 65536 + padded[off + i * 4 + 2] * 256 + padded[off + i * 4 + 3]
            push(w, u32(val))
        for i in range(48):
            let s0 = u32(rotr32(w[i + 16 - 15], 7) ^ rotr32(w[i + 16 - 15], 18) ^ (w[i + 16 - 15] >> 3))
            let s1 = u32(rotr32(w[i + 16 - 2], 17) ^ rotr32(w[i + 16 - 2], 19) ^ (w[i + 16 - 2] >> 10))
            push(w, u32(w[i + 16 - 16] + s0 + w[i + 16 - 7] + s1))

        let a = h0
        let b = h1
        let c = h2
        let d = h3
        let e = h4
        let f = h5
        let g = h6
        let hh = h7

        for i in range(64):
            let S1 = u32(rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25))
            let ch = u32((e & f) ^ ((u32(~e)) & g))
            let temp1 = u32(hh + S1 + ch + k[i] + w[i])
            let S0 = u32(rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22))
            let maj = u32((a & b) ^ (a & c) ^ (b & c))
            let temp2 = u32(S0 + maj)
            hh = g
            g = f
            f = e
            e = u32(d + temp1)
            d = c
            c = b
            b = a
            a = u32(temp1 + temp2)

        h0 = u32(h0 + a)
        h1 = u32(h1 + b)
        h2 = u32(h2 + c)
        h3 = u32(h3 + d)
        h4 = u32(h4 + e)
        h5 = u32(h5 + f)
        h6 = u32(h6 + g)
        h7 = u32(h7 + hh)

    # Produce the final hash as bytes
    let result = []
    let vals = [h0, h1, h2, h3, h4, h5, h6, h7]
    for i in range(8):
        let v = vals[i]
        push(result, (v >> 24) & 255)
        push(result, (v >> 16) & 255)
        push(result, (v >> 8) & 255)
        push(result, v & 255)
    return result

# SHA-256 returning hex string
proc sha256_hex(input):
    return to_hex(sha256(input))

# ============================================================================
# SHA-1
# ============================================================================

proc sha1(input):
    let msg = input
    if type(input) == "string":
        msg = string_to_bytes(input)

    let bit_len = len(msg) * 8
    let padded = pad_message(msg)
    padded = append_length_be(padded, bit_len)

    let h0 = 1732584193
    let h1 = 4023233417
    let h2 = 2562383102
    let h3 = 271733878
    let h4 = 3285377520

    let num_blocks = (len(padded) / 64) | 0

    for block in range(num_blocks):
        let off = block * 64
        let w = []
        for i in range(16):
            let val = padded[off + i * 4] * 16777216 + padded[off + i * 4 + 1] * 65536 + padded[off + i * 4 + 2] * 256 + padded[off + i * 4 + 3]
            push(w, u32(val))
        for i in range(64):
            let val = u32(w[i + 16 - 3] ^ w[i + 16 - 8] ^ w[i + 16 - 14] ^ w[i + 16 - 16])
            push(w, rotl32(val, 1))

        let a = h0
        let b = h1
        let c = h2
        let d = h3
        let e = h4

        for i in range(80):
            let f_val = 0
            let k_val = 0
            if i < 20:
                f_val = u32((b & c) | ((u32(~b)) & d))
                k_val = 1518500249
            if i >= 20 and i < 40:
                f_val = u32(b ^ c ^ d)
                k_val = 1859775393
            if i >= 40 and i < 60:
                f_val = u32((b & c) | (b & d) | (c & d))
                k_val = 2400959708
            if i >= 60:
                f_val = u32(b ^ c ^ d)
                k_val = 3395469782
            let temp = u32(rotl32(a, 5) + f_val + e + k_val + w[i])
            e = d
            d = c
            c = rotl32(b, 30)
            b = a
            a = temp

        h0 = u32(h0 + a)
        h1 = u32(h1 + b)
        h2 = u32(h2 + c)
        h3 = u32(h3 + d)
        h4 = u32(h4 + e)

    let result = []
    let vals = [h0, h1, h2, h3, h4]
    for i in range(5):
        let v = vals[i]
        push(result, (v >> 24) & 255)
        push(result, (v >> 16) & 255)
        push(result, (v >> 8) & 255)
        push(result, v & 255)
    return result

proc sha1_hex(input):
    return to_hex(sha1(input))

# ============================================================================
# CRC-32 (not cryptographic, but commonly needed alongside hashes)
# ============================================================================

proc crc32_table():
    let table = []
    for i in range(256):
        let crc = i
        for j in range(8):
            if (crc & 1) != 0:
                crc = u32((crc >> 1) ^ 3988292384)
            else:
                crc = crc >> 1
        push(table, crc)
    return table

proc crc32(input):
    let msg = input
    if type(input) == "string":
        msg = string_to_bytes(input)
    let table = crc32_table()
    let crc = 4294967295
    for i in range(len(msg)):
        let idx = (crc ^ msg[i]) & 255
        crc = u32((crc >> 8) ^ table[idx])
    return u32(crc ^ 4294967295)

proc crc32_hex(input):
    let c = crc32(input)
    let result = ""
    for i in range(4):
        let byte_val = (c >> (24 - i * 8)) & 255
        result = result + hex_byte(byte_val)
    return result
