# Password hashing and verification utilities
# PBKDF2-HMAC-SHA256 key derivation

# PBKDF2 key derivation function
# Uses HMAC with a provided hash function
# password: string or byte array
# salt: string or byte array
# iterations: number of HMAC rounds (recommended >= 10000)
# key_length: desired output length in bytes
# hash_fn: hash function (e.g., hash.sha256)
# block_size: hash block size (64 for SHA-256)
proc pbkdf2(hash_fn, password, salt, iterations, key_length, block_size):
    let pwd = password
    if type(password) == "string":
        pwd = str_to_bytes(password)
    let s = salt
    if type(salt) == "string":
        s = str_to_bytes(salt)

    let result = []
    let block_num = 1
    let hash_len = len(hash_fn(pwd))

    while len(result) < key_length:
        # U1 = HMAC(password, salt + INT32_BE(block_num))
        let salt_block = []
        for i in range(len(s)):
            push(salt_block, s[i])
        push(salt_block, (block_num >> 24) & 255)
        push(salt_block, (block_num >> 16) & 255)
        push(salt_block, (block_num >> 8) & 255)
        push(salt_block, block_num & 255)

        let u = hmac_raw(hash_fn, pwd, salt_block, block_size)
        let dk = []
        for i in range(len(u)):
            push(dk, u[i])

        # U2..Uc
        for iter in range(iterations - 1):
            u = hmac_raw(hash_fn, pwd, u, block_size)
            for i in range(len(dk)):
                dk[i] = dk[i] ^ u[i]

        for i in range(len(dk)):
            if len(result) < key_length:
                push(result, dk[i])
        block_num = block_num + 1

    return result

# Internal HMAC (duplicated here to avoid circular import)
proc hmac_raw(hash_fn, key, message, block_size):
    let k = key
    if len(k) > block_size:
        k = hash_fn(k)
    let padded_key = []
    for i in range(len(k)):
        push(padded_key, k[i])
    while len(padded_key) < block_size:
        push(padded_key, 0)
    let i_key_pad = []
    for i in range(block_size):
        push(i_key_pad, padded_key[i] ^ 54)
    let o_key_pad = []
    for i in range(block_size):
        push(o_key_pad, padded_key[i] ^ 92)
    let inner_input = []
    for i in range(len(i_key_pad)):
        push(inner_input, i_key_pad[i])
    for i in range(len(message)):
        push(inner_input, message[i])
    let inner_hash = hash_fn(inner_input)
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

# Constant-time comparison
proc secure_compare(a, b):
    if len(a) != len(b):
        return false
    let result = 0
    for i in range(len(a)):
        result = result | (a[i] ^ b[i])
    return result == 0

# Generate a password hash string: "pbkdf2:iterations:salt_hex:hash_hex"
proc hash_password(hash_fn, password, salt_bytes, iterations, block_size):
    let key = pbkdf2(hash_fn, password, salt_bytes, iterations, 32, block_size)
    let salt_hex = to_hex(salt_bytes)
    let key_hex = to_hex(key)
    return "pbkdf2:" + str(iterations) + ":" + salt_hex + ":" + key_hex

# Verify a password against a hash string
proc verify_password(hash_fn, password, hash_string, block_size):
    # Parse "pbkdf2:iterations:salt_hex:hash_hex"
    let parts = split_colon(hash_string)
    if len(parts) != 4:
        return false
    let iterations = tonumber(parts[1])
    let salt_bytes = hex_decode(parts[2])
    let expected = hex_decode(parts[3])
    let derived = pbkdf2(hash_fn, password, salt_bytes, iterations, len(expected), block_size)
    return secure_compare(derived, expected)

proc split_colon(s):
    let parts = []
    let current = ""
    for i in range(len(s)):
        if s[i] == ":":
            push(parts, current)
            current = ""
        else:
            current = current + s[i]
    if len(current) > 0:
        push(parts, current)
    return parts

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

proc hex_val(c):
    let code = ord(c)
    if code >= 48 and code <= 57:
        return code - 48
    if code >= 65 and code <= 70:
        return code - 55
    if code >= 97 and code <= 102:
        return code - 87
    return -1
