gc_disable()
# EXPECT: true
# EXPECT: true
# EXPECT: 16
# EXPECT: 3

import crypto.cipher

# XOR encrypt/decrypt round-trip
let data = [72, 101, 108, 108, 111]
let key = [42, 17, 99]
let encrypted = cipher.xor_encrypt(data, key)
let decrypted = cipher.xor_decrypt(encrypted, key)
let same = true
for i in range(5):
    if data[i] != decrypted[i]:
        same = false
print same

# RC4 encrypt/decrypt round-trip
let rc4_key = "secret"
let plaintext = [1, 2, 3, 4, 5, 6, 7, 8]
let ct = cipher.rc4(rc4_key, plaintext)
let pt = cipher.rc4(rc4_key, ct)
let rc4_same = true
for i in range(8):
    if plaintext[i] != pt[i]:
        rc4_same = false
print rc4_same

# PKCS7 padding
let padded = cipher.pkcs7_pad([1, 2, 3], 16)
print len(padded)

let unpadded = cipher.pkcs7_unpad(padded)
print len(unpadded)
