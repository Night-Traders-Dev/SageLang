gc_disable()
# EXPECT: 32
# EXPECT: true

import crypto.hash
import crypto.password

# PBKDF2 produces correct length output
let key = password.pbkdf2(hash.sha256, "password", "salt", 1, 32, 64)
print len(key)

# Constant-time compare works
let a = [1, 2, 3]
let b = [1, 2, 3]
print password.secure_compare(a, b)
