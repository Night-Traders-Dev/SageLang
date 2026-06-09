gc_disable()
# EXPECT: 64
# EXPECT: 40
# EXPECT: 32
# EXPECT: 20
# EXPECT: true
# EXPECT: 8

import crypto.hash

# SHA-256 produces 64-char hex string
let h256 = hash.sha256_hex("hello")
print len(h256)

# SHA-1 produces 40-char hex string
let h1 = hash.sha1_hex("hello")
print len(h1)

# SHA-256 produces 32 bytes
let h256b = hash.sha256("hello")
print len(h256b)

# SHA-1 produces 20 bytes
let h1b = hash.sha1("hello")
print len(h1b)

# Different inputs produce different hashes
let ha = hash.sha256_hex("abc")
let hb = hash.sha256_hex("def")
print ha != hb

# CRC-32 produces a hex string
let c = hash.crc32_hex("hello")
print len(c)
