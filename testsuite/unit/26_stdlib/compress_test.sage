gc_disable()
# EXPECT: true
# EXPECT: true
# EXPECT: true

import std.compress

# RLE round-trip
let data = [1, 1, 1, 2, 2, 3]
let encoded = compress.rle_encode(data)
let decoded = compress.rle_decode(encoded)
let same = true
for i in range(len(data)):
    if data[i] != decoded[i]:
        same = false
print same

# Delta round-trip
let sorted_data = [10, 12, 15, 20, 28]
let delta_enc = compress.delta_encode(sorted_data)
let delta_dec = compress.delta_decode(delta_enc)
let delta_same = true
for i in range(len(sorted_data)):
    if sorted_data[i] != delta_dec[i]:
        delta_same = false
print delta_same

# LZ77 round-trip
let text = compress.str_to_bytes("abcabcabcabc")
let lz_enc = compress.lz77_encode(text, 32)
let lz_dec = compress.lz77_decode(lz_enc)
let lz_same = true
for i in range(len(text)):
    if text[i] != lz_dec[i]:
        lz_same = false
print lz_same
