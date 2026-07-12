# EXPECT: true
import crypto.cipher as cipher

let key = "abcdefghijklmnop"
let data = "Hello World 1234"
let enc = cipher.aes_encrypt(data, key)
let dec = cipher.aes_decrypt(enc, key)
print dec == [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 32, 49, 50, 51, 52]
