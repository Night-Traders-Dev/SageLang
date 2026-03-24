# HMAC (Hash-based Message Authentication Code)
# RFC 2104 implementation using pluggable hash functions

# Compute HMAC with a given hash function
# hash_fn: a proc that takes byte array and returns byte array (e.g., hash.sha256)
# key: byte array or string
# message: byte array or string
# block_size: hash block size in bytes (64 for SHA-256/SHA-1, 64 for MD5)
proc hmac(hash_fn, key, message, block_size):
    let k = key
    if type(key) == "string":
        k = str_to_bytes(key)
    let msg = message
    if type(message) == "string":
        msg = str_to_bytes(message)

    # If key is longer than block size, hash it
    if len(k) > block_size:
        k = hash_fn(k)

    # Pad key to block_size with zeros
    let padded_key = []
    for i in range(len(k)):
        push(padded_key, k[i])
    while len(padded_key) < block_size:
        push(padded_key, 0)

    # Inner padding (key XOR 0x36)
    let i_key_pad = []
    for i in range(block_size):
        push(i_key_pad, padded_key[i] ^ 54)

    # Outer padding (key XOR 0x5C)
    let o_key_pad = []
    for i in range(block_size):
        push(o_key_pad, padded_key[i] ^ 92)

    # inner_hash = hash(i_key_pad + message)
    let inner_input = []
    for i in range(len(i_key_pad)):
        push(inner_input, i_key_pad[i])
    for i in range(len(msg)):
        push(inner_input, msg[i])
    let inner_hash = hash_fn(inner_input)

    # outer_hash = hash(o_key_pad + inner_hash)
    let outer_input = []
    for i in range(len(o_key_pad)):
        push(outer_input, o_key_pad[i])
    for i in range(len(inner_hash)):
        push(outer_input, inner_hash[i])

    return hash_fn(outer_input)

proc str_to_bytes(s):
    let bytes = []
    for i in range(len(s)):
        push(bytes, ord(s[i]))
    return bytes

proc to_hex(bytes):
    let digits = "0123456789abcdef"
    let result = ""
    for i in range(len(bytes)):
        result = result + digits[(bytes[i] >> 4) & 15] + digits[bytes[i] & 15]
    return result

# Convenience: HMAC-SHA256
proc hmac_sha256(key, message):
    # Import must happen at module level in Sage, so we take hash_fn as param
    # Users should call: hmac.hmac(hash.sha256, key, msg, 64)
    # This is a wrapper that requires hash module to be passed
    return nil

# Constant-time comparison of two byte arrays (prevents timing attacks)
proc secure_compare(a, b):
    if len(a) != len(b):
        return false
    let result = 0
    for i in range(len(a)):
        result = result | (a[i] ^ b[i])
    return result == 0
