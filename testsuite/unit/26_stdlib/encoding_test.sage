gc_disable()
# EXPECT: SGVsbG8=
# EXPECT: Hello
# EXPECT: 48656c6c6f
# EXPECT: Hello
# EXPECT: SGVsbG8
# EXPECT: true

import crypto.encoding

# Base64 encode/decode
print encoding.b64_encode("Hello")
print encoding.b64_decode_string("SGVsbG8=")

# Hex encode/decode
print encoding.hex_encode("Hello")
print encoding.hex_decode_string("48656c6c6f")

# URL-safe Base64
print encoding.b64url_encode("Hello")

# Round-trip
let original = [1, 2, 3, 4, 5]
let encoded = encoding.b64_encode(original)
let decoded = encoding.b64_decode(encoded)
let same = true
for i in range(5):
    if original[i] != decoded[i]:
        same = false
print same
