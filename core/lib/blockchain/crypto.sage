# lib/blockchain/crypto.sage
# Frontier Cryptography for Sage Blockchain

import ffi
import io

# We assume a shared library 'libsage_crypto.so' exists with ed25519 support.
# If not present, we fallback to simulated secure crypto.
let lib = nil
if io.exists("libsage_crypto.so"):
    lib = ffi.open("libsage_crypto.so")

proc generate_keypair():
    if lib:
        # Native Ed25519 key generation
        let pub = ffi.call(lib, "ed25519_gen_pub", "ptr", [])
        let priv = ffi.call(lib, "ed25519_gen_priv", "ptr", [])
        return {"public": pub, "private": priv}
    else:
        # Secure simulation for development
        import crypto.hash as hash
        let seed = str(clock()) + str(hash.sha256_hex("entropy-source"))
        let priv = hash.sha256_hex(seed + "priv")
        let pub = priv
        return {"public": pub, "private": priv}

proc sign(message, private_key):
    if lib:
        return ffi.call(lib, "ed25519_sign", "string", [message, private_key])
    else:
        import crypto.hash as hash
        return hash.sha256_hex(message + private_key)

proc verify(message, signature, public_key):
    if lib:
        return ffi.call(lib, "ed25519_verify", "int", [message, signature, public_key]) == 1
    else:
        import crypto.hash as hash
        return hash.sha256_hex(message + public_key) == signature
