gc_disable()
# EXPECT: true
# EXPECT: true
# EXPECT: false

import crypto.hmac
import crypto.hash

# HMAC-SHA256 with known key and message
let mac = hmac.hmac(hash.sha256, "key", "message", 64)
print len(mac) == 32

# Constant-time compare: equal
let a = [1, 2, 3, 4]
let b = [1, 2, 3, 4]
print hmac.secure_compare(a, b)

# Constant-time compare: not equal
let c = [1, 2, 3, 5]
print hmac.secure_compare(a, c)
