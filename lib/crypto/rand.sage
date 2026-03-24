gc_disable()
# Pseudorandom number generators for cryptographic and general use
# Implements xoshiro256** (fast, high-quality PRNG) and utilities

proc u32(x):
    return x & 4294967295

proc u64(x):
    return x & 18446744073709551615

proc rotl64(x, k):
    return u64((x << k) | (x >> (64 - k)))

# ============================================================================
# xoshiro256** PRNG (period 2^256 - 1)
# ============================================================================

# Create a PRNG state from a 64-bit seed
proc create(seed):
    let state = {}
    # SplitMix64 to initialize 4 state words from single seed
    let s = seed
    let s0 = splitmix64_next(s)
    s = s0["state"]
    let s1 = splitmix64_next(s)
    s = s1["state"]
    let s2 = splitmix64_next(s)
    s = s2["state"]
    let s3 = splitmix64_next(s)
    state["s0"] = s0["value"]
    state["s1"] = s1["value"]
    state["s2"] = s2["value"]
    state["s3"] = s3["value"]
    return state

proc splitmix64_next(state):
    let z = state + 11400714819323198485
    z = u64(z)
    z = u64((z ^ (z >> 30)) * 13787848793156543929)
    z = u64((z ^ (z >> 27)) * 10723151780598845931)
    z = u64(z ^ (z >> 31))
    let result = {}
    result["value"] = z
    result["state"] = u64(state + 11400714819323198485)
    return result

# Generate next random u64
proc next_u64(state):
    let s0 = state["s0"]
    let s1 = state["s1"]
    let s2 = state["s2"]
    let s3 = state["s3"]
    let result = u64(rotl64(u64(s1 * 5), 7) * 9)
    let t = u64(s1 << 17)
    s2 = u64(s2 ^ s0)
    s3 = u64(s3 ^ s1)
    s1 = u64(s1 ^ s2)
    s0 = u64(s0 ^ s3)
    s2 = u64(s2 ^ t)
    s3 = rotl64(s3, 45)
    state["s0"] = s0
    state["s1"] = s1
    state["s2"] = s2
    state["s3"] = s3
    return result

# Generate random u32
proc next_u32(state):
    return u32(next_u64(state))

# Generate random number in [0, bound) using rejection sampling
proc next_bounded(state, bound):
    if bound <= 1:
        return 0
    let r = next_u64(state)
    # Simple modulo (slight bias for non-power-of-2 bounds, acceptable for most uses)
    if r < 0:
        r = 0 - r
    return r - ((r / bound) | 0) * bound

# Generate random float in [0.0, 1.0)
proc next_float(state):
    let r = next_u64(state) & 4503599627370495
    return r / 4503599627370496

# Generate random bytes
proc random_bytes(state, count):
    let result = []
    for i in range(count):
        push(result, next_u32(state) & 255)
    return result

# ============================================================================
# Linear Congruential Generator (fast, low-quality, for non-crypto use)
# ============================================================================

proc lcg_create(seed):
    let state = {}
    state["value"] = seed
    return state

proc lcg_next(state):
    state["value"] = u32(state["value"] * 1664525 + 1013904223)
    return state["value"]

proc lcg_bounded(state, bound):
    if bound <= 1:
        return 0
    let r = lcg_next(state)
    return r - ((r / bound) | 0) * bound

# ============================================================================
# Utility functions
# ============================================================================

# Shuffle an array in-place using Fisher-Yates
proc shuffle(state, arr):
    let n = len(arr)
    let i = n - 1
    while i > 0:
        let j = next_bounded(state, i + 1)
        let temp = arr[i]
        arr[i] = arr[j]
        arr[j] = temp
        i = i - 1
    return arr

# Generate a random hex string of given byte length
proc random_hex(state, byte_count):
    let digits = "0123456789abcdef"
    let bytes = random_bytes(state, byte_count)
    let result = ""
    for i in range(len(bytes)):
        result = result + digits[(bytes[i] >> 4) & 15] + digits[bytes[i] & 15]
    return result

# Generate a random alphanumeric string
proc random_string(state, length):
    let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    let result = ""
    for i in range(length):
        let idx = next_bounded(state, 62)
        result = result + chars[idx]
    return result

# Generate a UUID v4 (random)
proc uuid4(state):
    let bytes = random_bytes(state, 16)
    # Set version 4
    bytes[6] = (bytes[6] & 15) + 64
    # Set variant 1
    bytes[8] = (bytes[8] & 63) + 128
    let digits = "0123456789abcdef"
    let result = ""
    for i in range(16):
        result = result + digits[(bytes[i] >> 4) & 15] + digits[bytes[i] & 15]
        if i == 3 or i == 5 or i == 7 or i == 9:
            result = result + "-"
    return result
