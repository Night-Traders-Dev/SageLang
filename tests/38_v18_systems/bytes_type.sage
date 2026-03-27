# EXPECT: 5
# EXPECT: 104
# EXPECT: ABC
# EXPECT: el
# Test Bytes type
let b = bytes("hello")
print bytes_len(b)
print bytes_get(b, 0)

let b2 = bytes([65, 66, 67])
print bytes_to_string(b2)

let b3 = bytes_slice(b, 1, 3)
print bytes_to_string(b3)
