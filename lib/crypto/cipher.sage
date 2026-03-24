# Symmetric cipher utilities
# XOR cipher, RC4 stream cipher, and block cipher mode helpers

proc u32(x):
    return x & 4294967295

proc str_to_bytes(s):
    let bytes = []
    for i in range(len(s)):
        push(bytes, ord(s[i]))
    return bytes

# ============================================================================
# XOR Cipher (repeating key)
# ============================================================================

proc xor_encrypt(data, key):
    let d = data
    if type(data) == "string":
        d = str_to_bytes(data)
    let k = key
    if type(key) == "string":
        k = str_to_bytes(key)
    let result = []
    for i in range(len(d)):
        push(result, d[i] ^ k[i & (len(k) - 1)])
    return result

# XOR decrypt is identical to encrypt
proc xor_decrypt(data, key):
    return xor_encrypt(data, key)

# ============================================================================
# RC4 Stream Cipher
# ============================================================================

# Initialize RC4 key schedule (KSA)
proc rc4_init(key):
    let k = key
    if type(key) == "string":
        k = str_to_bytes(key)
    let s = []
    for i in range(256):
        push(s, i)
    let j = 0
    for i in range(256):
        j = (j + s[i] + k[i & (len(k) - 1)]) & 255
        let temp = s[i]
        s[i] = s[j]
        s[j] = temp
    let state = {}
    state["s"] = s
    state["i"] = 0
    state["j"] = 0
    return state

# Generate next RC4 keystream byte
proc rc4_next(state):
    let s = state["s"]
    state["i"] = (state["i"] + 1) & 255
    let i = state["i"]
    state["j"] = (state["j"] + s[i]) & 255
    let j = state["j"]
    let temp = s[i]
    s[i] = s[j]
    s[j] = temp
    return s[(s[i] + s[j]) & 255]

# Encrypt/decrypt data using RC4
proc rc4(key, data):
    let d = data
    if type(data) == "string":
        d = str_to_bytes(data)
    let state = rc4_init(key)
    let result = []
    for i in range(len(d)):
        push(result, d[i] ^ rc4_next(state))
    return result

# ============================================================================
# Block Cipher Mode Helpers (for use with external block ciphers)
# ============================================================================

# PKCS#7 padding
proc pkcs7_pad(data, block_size):
    let d = data
    if type(data) == "string":
        d = str_to_bytes(data)
    let pad_len = block_size - (len(d) & (block_size - 1))
    if pad_len == 0:
        pad_len = block_size
    let result = []
    for i in range(len(d)):
        push(result, d[i])
    for i in range(pad_len):
        push(result, pad_len)
    return result

# Remove PKCS#7 padding
proc pkcs7_unpad(data):
    if len(data) == 0:
        return data
    let pad_len = data[len(data) - 1]
    if pad_len > len(data) or pad_len == 0:
        return data
    # Verify all padding bytes
    let valid = true
    for i in range(pad_len):
        if data[len(data) - 1 - i] != pad_len:
            valid = false
    if not valid:
        return data
    let result = []
    for i in range(len(data) - pad_len):
        push(result, data[i])
    return result

# XOR two blocks of equal length
proc xor_blocks(a, b):
    let result = []
    for i in range(len(a)):
        push(result, a[i] ^ b[i])
    return result

# CBC mode encrypt (takes a block encrypt function, IV, and padded data)
# block_encrypt_fn: proc(block, key) -> encrypted block (byte arrays)
proc cbc_encrypt(block_encrypt_fn, key, iv, data):
    let block_size = len(iv)
    let result = []
    let prev = iv
    let i = 0
    while i < len(data):
        let block = []
        for j in range(block_size):
            if i + j < len(data):
                push(block, data[i + j])
            else:
                push(block, 0)
        let xored = xor_blocks(block, prev)
        let encrypted = block_encrypt_fn(xored, key)
        for j in range(len(encrypted)):
            push(result, encrypted[j])
        prev = encrypted
        i = i + block_size
    return result

# CBC mode decrypt
proc cbc_decrypt(block_decrypt_fn, key, iv, data):
    let block_size = len(iv)
    let result = []
    let prev = iv
    let i = 0
    while i < len(data):
        let block = []
        for j in range(block_size):
            if i + j < len(data):
                push(block, data[i + j])
            else:
                push(block, 0)
        let decrypted = block_decrypt_fn(block, key)
        let xored = xor_blocks(decrypted, prev)
        for j in range(len(xored)):
            push(result, xored[j])
        prev = block
        i = i + block_size
    return result

# CTR mode (encrypt and decrypt are identical)
proc ctr(block_encrypt_fn, key, nonce, data):
    let block_size = len(nonce)
    let result = []
    let counter = 0
    let i = 0
    while i < len(data):
        # Build counter block: nonce + counter (big-endian in last 4 bytes)
        let ctr_block = []
        for j in range(len(nonce)):
            push(ctr_block, nonce[j])
        # Overwrite last 4 bytes with counter
        let ctr_off = len(ctr_block) - 4
        if ctr_off < 0:
            ctr_off = 0
        ctr_block[ctr_off] = (counter >> 24) & 255
        ctr_block[ctr_off + 1] = (counter >> 16) & 255
        ctr_block[ctr_off + 2] = (counter >> 8) & 255
        ctr_block[ctr_off + 3] = counter & 255
        let keystream = block_encrypt_fn(ctr_block, key)
        for j in range(block_size):
            if i + j < len(data):
                push(result, data[i + j] ^ keystream[j])
        counter = counter + 1
        i = i + block_size
    return result
