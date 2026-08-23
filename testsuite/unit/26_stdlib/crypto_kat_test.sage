# Crypto library known-answer test suite
import crypto.hash as H
import crypto.blake2s as B2S
import crypto.chacha20 as CC
import crypto.poly1305 as P13
import crypto.aead as AE
import crypto.cipher as CIP
import crypto.hmac as HM
import crypto.encoding as ENC

let passed = 0
let failed = 0

let failures = []

proc tohex(bytes):
    let digits = "0123456789abcdef"
    let out = []
    for b in bytes:
        push(out, digits[(b >> 4) & 15])
        push(out, digits[b & 15])
    return join(out, "")

# --- SHA-256 ---
if H.sha256_hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "sha256(abc)=" + H.sha256_hex("abc"))

if H.sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "sha256(long) wrong")

# --- SHA-1 ---
if H.sha1_hex("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "sha1(abc)=" + H.sha1_hex("abc"))

# --- CRC32 ---
if H.crc32_hex("123456789") == "cbf43926":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "crc32(123456789)=" + H.crc32_hex("123456789"))

# --- BLAKE2s-256 ---
if tohex(B2S.blake2s("abc")) == "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "blake2s(abc)=" + tohex(B2S.blake2s("abc")))

# --- ChaCha20 block (RFC 8439 2.3.2) ---
let cckey = []
for i in range(32):
    push(cckey, i)
let ccnonce = [0, 0, 0, 9, 0, 0, 0, 74, 0, 0, 0, 0]
let ccblk = CC.chacha20_block(cckey, 1, ccnonce)
if tohex(ccblk) == "10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4ed2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "chacha20_block=" + tohex(ccblk))

# --- ChaCha20 encrypt (RFC 8439 2.4.2) ---
let msg2 = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
let k2 = []
for i in range(32):
    push(k2, i)
let n2 = [0, 0, 0, 0, 0, 0, 0, 74, 0, 0, 0, 0]
let ct2 = CC.chacha20_encrypt(k2, 1, n2, msg2)
if tohex(ct2) == "6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "chacha20_encrypt=" + tohex(ct2))

# --- Poly1305 (RFC 8439 2.5.2) ---
let pkey = [133, 214, 190, 120, 87, 85, 109, 51, 127, 68, 82, 254, 66, 213, 6, 168, 1, 3, 128, 138, 251, 13, 178, 253, 74, 191, 246, 175, 65, 73, 245, 27]
let ptag = P13.poly1305_mac(pkey, "Cryptographic Forum Research Group")
if tohex(ptag) == "a8061dc1305136c6c22b8baf0c0127a9":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "poly1305_tag=" + tohex(ptag))

# --- AES-128/256 FIPS-197 ---
let aesk = []
for i in range(16):
    push(aesk, i)
let aespt = [0, 17, 34, 51, 68, 85, 102, 119, 136, 153, 170, 187, 204, 221, 238, 255]
let aesct = CIP.aes_block_encrypt(aespt, aesk)
if tohex(aesct) == "69c4e0d86a7b0430d8cdb78070b4c55a":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "aes128_ct=" + tohex(aesct))
let aesrt = CIP.aes_block_decrypt(aesct, aesk)
if tohex(aesrt) == tohex(aespt):
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "aes128_roundtrip=" + tohex(aesrt))

let aesk256 = []
for i in range(32):
    push(aesk256, i)
let aesct256 = CIP.aes_block_encrypt(aespt, aesk256)
if tohex(aesct256) == "8ea2b7ca516745bfeafc49904b496089":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "aes256_ct=" + tohex(aesct256))

# --- HMAC-SHA256 (RFC 4231 #1) ---
let hmack = []
for i in range(20):
    push(hmack, 11)
let hmacout = HM.hmac(H.sha256, hmack, "Hi There", 64)
if tohex(hmacout) == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "hmac_sha256_1=" + tohex(hmacout))

# --- X25519 (RFC 7748 5.2) ---
import crypto.x25519 as X19
let x_scalar = [165, 70, 227, 107, 240, 82, 124, 157, 59, 22, 21, 75, 130, 70, 94, 221, 98, 20, 76, 10, 193, 252, 90, 24, 80, 106, 34, 68, 186, 68, 154, 196]
let x_u = [230, 219, 104, 103, 88, 48, 48, 219, 53, 148, 193, 164, 36, 177, 95, 124, 114, 102, 36, 236, 38, 179, 53, 59, 16, 169, 3, 166, 208, 171, 28, 76]
let x_out = X19.x25519(x_scalar, x_u)
if tohex(x_out) == "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "x25519_v1=" + tohex(x_out))

# --- AEAD roundtrip + tag (RFC 8439 2.8.2 key/nonce/aad) ---
let aead_key = [128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159]
let aead_nonce = [7, 0, 0, 0, 64, 65, 66, 67, 68, 69, 70, 71]
let aead_aad = [80, 81, 82, 83, 192, 193, 194, 195, 196, 197, 198, 199]
let aead_res = AE.chacha20_poly1305_encrypt(aead_key, aead_nonce, msg2, aead_aad)
let aead_prefix_ok = true
let expect_prefix = [211, 26, 141, 52, 100, 142, 96, 219, 123, 134]
for i in range(10):
    if aead_res["ciphertext"][i] != expect_prefix[i]:
        aead_prefix_ok = false
if aead_prefix_ok:
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "aead_ct_prefix=" + tohex(aead_res["ciphertext"]))

let expect_tag = [26, 225, 11, 89, 79, 9, 226, 106, 126, 144, 46, 203, 208, 96, 6, 145]
let tag_ok = true
for i in range(16):
    if aead_res["tag"][i] != expect_tag[i]:
        tag_ok = false
if tag_ok:
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "aead_tag=" + tohex(aead_res["tag"]))

let decrypted = AE.chacha20_poly1305_decrypt(aead_key, aead_nonce, aead_res["ciphertext"], aead_res["tag"], aead_aad)
if decrypted != nil:
    let dec_ok = true
    for i in range(len(msg2)):
        if decrypted[i] != ord(msg2[i]):
            dec_ok = false
    if dec_ok:
        passed = passed + 1
    else:
        failed = failed + 1
        push(failures, "aead_roundtrip mismatch")
else:
    failed = failed + 1
    push(failures, "aead_decrypt returned nil")

# tamper detection
let bad_tag = []
for i in range(16):
    push(bad_tag, aead_res["tag"][i])
bad_tag[0] = bad_tag[0] ^ 1
if AE.chacha20_poly1305_decrypt(aead_key, aead_nonce, aead_res["ciphertext"], bad_tag, aead_aad) == nil:
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "aead_tamper not detected")

# --- Base64 (RFC 4648) ---
if ENC.b64_encode("foobar") == "Zm9vYmFy" and ENC.b64_encode("foob") == "Zm9vYg==" and ENC.b64_encode("fooba") == "Zm9vYmE=":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "b64_encode wrong")

# --- PBKDF2-HMAC-SHA256 (RFC vector, iter=1) ---
import crypto.password as PW
let pbd = PW.pbkdf2(H.sha256, "password", "salt", 1, 32, 64)
if tohex(pbd) == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "pbkdf2_1iter=" + tohex(pbd))

# --- RC4 known vector (FIPS-classic): key "Key", pt "Plaintext" ---
let rc4ct = CIP.rc4("Key", "Plaintext")
if tohex(rc4ct) == "bbf316e8d940af0ad3":
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "rc4=" + tohex(rc4ct))

# --- XOR with non-power-of-2 key (regression: i & (len-1) bug) ---
let xor_out = CIP.xor_encrypt([1, 2, 3, 4, 5, 6], [10, 20, 30])
let xor_ok = true
for i in range(6):
    if xor_out[i] != ([1, 2, 3, 4, 5, 6][i] ^ [10, 20, 30][i % 3]):
        xor_ok = false
if xor_ok and CIP.xor_decrypt(xor_out, [10, 20, 30]) == [1, 2, 3, 4, 5, 6]:
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "xor non-pow2 key broken")

# --- AES rejects invalid key length instead of silent garbage ---
let aes_bad_key = []
for i in range(24):
    push(aes_bad_key, i)
try:
    CIP.aes_block_encrypt(aespt, aes_bad_key)
    failed = failed + 1
    push(failures, "aes accepted 24-byte key")
catch e:
    passed = passed + 1

# --- xoshiro256** matches the reference generator (splitmix64 seeding) ---
import crypto.rand as RD
let rng = RD.create(12345)
if RD.next_u32(rng) == 1096864923 and RD.next_u32(rng) == 933660870 and RD.next_u32(rng) == 2572473224:
    passed = passed + 1
else:
    failed = failed + 1
    push(failures, "xoshiro256** sequence mismatch")

print(str(passed) + " passed, " + str(failed) + " failed")
for f in failures:
    print("FAIL " + f)

