# SageLang Cryptography Guide

This guide covers the cryptography library suite (`lib/crypto/`) providing hashing, encoding, encryption, random number generation, and password management.

## Architecture

All crypto modules are pure Sage implementations with no native C dependencies. They are imported with the `crypto.` prefix:

```sage
import crypto.hash       # SHA-256, SHA-1, CRC-32
import crypto.hmac       # HMAC with pluggable hash
import crypto.encoding   # Base64, hex encoding
import crypto.cipher     # XOR, RC4, block cipher modes
import crypto.rand       # PRNG, UUID, random strings
import crypto.password   # PBKDF2, password hashing
```

---

## Hash Functions (`crypto.hash`)

### SHA-256

```sage
import crypto.hash

let digest = hash.sha256("hello world")     # byte array (32 bytes)
let hex = hash.sha256_hex("hello world")    # hex string (64 chars)
print len(digest)  # 32
print len(hex)     # 64

# Also accepts byte arrays
let bytes = [72, 101, 108, 108, 111]
let h = hash.sha256(bytes)
```

### SHA-1

```sage
let digest = hash.sha1("hello")
let hex = hash.sha1_hex("hello")
print len(digest)  # 20
print len(hex)     # 40
```

### CRC-32

```sage
let checksum = hash.crc32("hello")          # integer
let hex = hash.crc32_hex("hello")           # hex string (8 chars)
```

### Utility Functions

```sage
let bytes = hash.string_to_bytes("hello")   # [72, 101, 108, 108, 111]
let hex = hash.to_hex([255, 0, 171])        # "ff00ab"
```

---

## HMAC (`crypto.hmac`)

HMAC (Hash-based Message Authentication Code) per RFC 2104.

```sage
import crypto.hmac
import crypto.hash

# HMAC-SHA256
let mac = hmac.hmac(hash.sha256, "secret-key", "message", 64)
print len(mac)  # 32 bytes

# HMAC-SHA1
let mac1 = hmac.hmac(hash.sha1, "key", "data", 64)
print len(mac1)  # 20 bytes

# Hex output
print hmac.to_hex(mac)
```

### Constant-Time Comparison

```sage
# Prevents timing attacks when verifying MACs
let valid = hmac.secure_compare(computed_mac, expected_mac)
```

---

## Encoding (`crypto.encoding`)

### Base64

```sage
import crypto.encoding

# Encode
print encoding.b64_encode("Hello, World!")    # SGVsbG8sIFdvcmxkIQ==
print encoding.b64_encode([1, 2, 3, 4])       # AQIDBA==

# Decode
let bytes = encoding.b64_decode("SGVsbG8=")
let text = encoding.b64_decode_string("SGVsbG8=")  # "Hello"

# URL-safe Base64 (no padding, +/ replaced with -_)
print encoding.b64url_encode("Hello")          # SGVsbG8
let decoded = encoding.b64url_decode("SGVsbG8") # [72, 101, 108, 108, 111]
```

### Hex (Base16)

```sage
print encoding.hex_encode("Hello")             # 48656c6c6f
print encoding.hex_encode([255, 0, 171])        # ff00ab

let bytes = encoding.hex_decode("48656c6c6f")
let text = encoding.hex_decode_string("48656c6c6f")  # "Hello"
```

### Conversion Helpers

```sage
let bytes = encoding.str_to_bytes("Hello")      # [72, 101, 108, 108, 111]
let text = encoding.bytes_to_str(bytes)          # "Hello"
```

---

## Ciphers (`crypto.cipher`)

### XOR Cipher

```sage
import crypto.cipher

let data = [72, 101, 108, 108, 111]
let key = [42, 17, 99]

let encrypted = cipher.xor_encrypt(data, key)
let decrypted = cipher.xor_decrypt(encrypted, key)
# decrypted == data (XOR is symmetric)
```

### RC4 Stream Cipher

```sage
# RC4 encrypt (also accepts strings for key)
let ciphertext = cipher.rc4("my-secret-key", [1, 2, 3, 4, 5, 6, 7, 8])

# RC4 decrypt (same operation)
let plaintext = cipher.rc4("my-secret-key", ciphertext)
```

### PKCS#7 Padding

```sage
let padded = cipher.pkcs7_pad([1, 2, 3], 16)    # pads to 16 bytes
print len(padded)  # 16

let unpadded = cipher.pkcs7_unpad(padded)
print len(unpadded)  # 3
```

### Block Cipher Modes

CBC and CTR modes accept a block encrypt/decrypt function as a parameter, making them usable with any block cipher:

```sage
# CBC mode (requires padded input)
let iv = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
let padded = cipher.pkcs7_pad(plaintext, 16)
let ct = cipher.cbc_encrypt(my_block_encrypt, key, iv, padded)
let pt = cipher.cbc_decrypt(my_block_decrypt, key, iv, ct)
let result = cipher.pkcs7_unpad(pt)

# CTR mode (no padding needed, encrypt = decrypt)
let nonce = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
let ct = cipher.ctr(my_block_encrypt, key, nonce, plaintext)
let pt = cipher.ctr(my_block_encrypt, key, nonce, ct)
```

---

## Random Number Generation (`crypto.rand`)

### PRNG (xoshiro256**)

```sage
import crypto.rand

let rng = rand.create(42)                  # seed with integer
let n = rand.next_u64(rng)                 # random 64-bit integer
let n32 = rand.next_u32(rng)              # random 32-bit integer
let bounded = rand.next_bounded(rng, 100)  # [0, 100)
let f = rand.next_float(rng)              # [0.0, 1.0)
```

### Random Data Generation

```sage
let bytes = rand.random_bytes(rng, 32)     # 32 random bytes
let hex = rand.random_hex(rng, 16)         # 32-char hex string
let token = rand.random_string(rng, 24)    # 24-char alphanumeric
```

### UUID v4

```sage
let id = rand.uuid4(rng)
print id  # e.g., "a3f2b1c4-5d6e-4f78-9a0b-1c2d3e4f5a6b"
```

### Shuffling

```sage
let arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
rand.shuffle(rng, arr)
# arr is now randomly permuted
```

### LCG (Fast, Non-Crypto)

```sage
let lcg = rand.lcg_create(12345)
let val = rand.lcg_next(lcg)
let bounded = rand.lcg_bounded(lcg, 6)  # dice roll [0, 6)
```

---

## Password Hashing (`crypto.password`)

### PBKDF2 Key Derivation

```sage
import crypto.password
import crypto.hash

# Derive a 32-byte key from password + salt
let key = password.pbkdf2(hash.sha256, "my-password", "random-salt", 10000, 32, 64)
print len(key)  # 32
```

### Password Hash/Verify

```sage
import crypto.rand

let rng = rand.create(42)
let salt = rand.random_bytes(rng, 16)

# Hash a password
let hashed = password.hash_password(hash.sha256, "user-password", salt, 10000, 64)
print hashed  # "pbkdf2:10000:salt_hex:hash_hex"

# Verify a password
let valid = password.verify_password(hash.sha256, "user-password", hashed, 64)
print valid  # true

let invalid = password.verify_password(hash.sha256, "wrong-password", hashed, 64)
print invalid  # false
```

### Constant-Time Comparison

```sage
# Use for comparing hashes/MACs to prevent timing attacks
let equal = password.secure_compare(hash_a, hash_b)
```

---

## Module Reference

| Module | Import | Key Functions |
|--------|--------|---------------|
| `hash` | `import crypto.hash` | `sha256`, `sha256_hex`, `sha1`, `sha1_hex`, `crc32`, `crc32_hex`, `to_hex` |
| `hmac` | `import crypto.hmac` | `hmac`, `secure_compare`, `to_hex` |
| `encoding` | `import crypto.encoding` | `b64_encode`, `b64_decode`, `b64_decode_string`, `b64url_encode`, `b64url_decode`, `hex_encode`, `hex_decode`, `hex_decode_string` |
| `cipher` | `import crypto.cipher` | `xor_encrypt`, `xor_decrypt`, `rc4`, `rc4_init`, `pkcs7_pad`, `pkcs7_unpad`, `cbc_encrypt`, `cbc_decrypt`, `ctr`, `xor_blocks` |
| `rand` | `import crypto.rand` | `create`, `next_u64`, `next_u32`, `next_bounded`, `next_float`, `random_bytes`, `random_hex`, `random_string`, `uuid4`, `shuffle` |
| `password` | `import crypto.password` | `pbkdf2`, `hash_password`, `verify_password`, `secure_compare` |

## Security Notes

- Hash implementations are pure Sage (no FFI to OpenSSL). They are suitable for checksums, data integrity, and educational use.
- For production TLS/SSL, use the native `ssl` module which wraps OpenSSL.
- RC4 is included for compatibility; it is considered cryptographically broken for new applications.
- The xoshiro256** PRNG is high-quality but not cryptographically secure. For cryptographic randomness, seed it from a system entropy source.
- PBKDF2 iteration count should be >= 10,000 for password storage (100,000+ recommended).
