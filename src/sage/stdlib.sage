gc_disable()
# SageLang Standard Library (self-hosted port)
#
# Pure Sage implementations of the standard library modules.
# These provide the same interfaces as the C native modules
# (math, io, string, sys) for the self-hosted interpreter.
#
# Note: Some functions (threads) require C and can't be ported.
# IO delegates to the C native io module (readfile/writefile).
import io

# ============================================================================
# Math Module
# ============================================================================

# Random number generation (Linear Congruential Generator)
let _random_seed = 123456789

proc _random_next():
    # LCG parameters: a=1664525, c=1013904223, m=2^32
    _random_seed = (_random_seed * 1664525 + 1013904223) % 4294967296
    return _random_seed

proc math_random():
    return _random_next() / 4294967296.0

proc math_random_range(min_val, max_val):
    return min_val + math_random() * (max_val - min_val)

proc math_random_int(min_val, max_val):
    return math_floor(math_random_range(min_val, max_val + 1))

proc create_math_module():
    let m = {}
    # Constants
    m["pi"] = 3.14159265358979323846
    m["PI"] = 3.14159265358979323846  # Uppercase alias
    m["e"] = 2.71828182845904523536
    m["tau"] = 6.28318530717958647692
    m["inf"] = 1.0 / 0.0
    
    # Functions
    m["abs"] = math_abs
    m["min"] = math_min
    m["max"] = math_max
    m["clamp"] = math_clamp
    m["floor"] = math_floor
    m["ceil"] = math_ceil
    m["round"] = math_round
    m["fmod"] = math_fmod
    m["pow"] = math_pow
    m["sqrt"] = math_sqrt
    m["log"] = math_log
    m["log10"] = math_log10
    m["exp"] = math_exp
    m["sin"] = math_sin
    m["cos"] = math_cos
    m["tan"] = math_tan
    
    # Random number generation
    m["random"] = math_random
    m["random_range"] = math_random_range
    m["random_int"] = math_random_int
    
    return m

# Helper: extract integer part from a float via string truncation
# (Sage % operator casts to int, so x%1 always returns 0)
proc trunc(x):
    let s = str(x)
    let dot = -1
    for i in range(len(s)):
        if s[i] == ".":
            dot = i
            break
    if dot == -1:
        return x
    let int_part = ""
    for i in range(dot):
        int_part = int_part + s[i]
    if int_part == "-":
        return 0
    if int_part == "" or int_part == "-0":
        return 0
    return tonumber(int_part)

proc math_abs(x):
    if x < 0:
        return -x
    return x

proc math_min(a, b):
    if a < b:
        return a
    return b

proc math_max(a, b):
    if a > b:
        return a
    return b

proc math_clamp(v, lo, hi):
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v

proc math_floor(x):
    let t = trunc(x)
    if x < 0 and x != t:
        return t - 1
    return t

proc math_ceil(x):
    let t = trunc(x)
    if x > 0 and x != t:
        return t + 1
    return t

proc math_round(x):
    if x >= 0:
        return math_floor(x + 0.5)
    return math_ceil(x - 0.5)

proc math_fmod(a, b):
    if b == 0:
        return 0
    return a % b

proc math_pow(base, exp):
    if exp == 0:
        return 1
    if exp < 0:
        return 1.0 / math_pow(base, -exp)
    let result = 1
    let e = exp
    let b = base
    while e > 0:
        if e % 2 == 1:
            result = result * b
        b = b * b
        e = math_floor(e / 2)
    return result

proc math_sqrt(x):
    if x < 0:
        return nil
    if x == 0:
        return 0
    let guess = x / 2.0
    for i in range(50):
        let next_g = (guess + x / guess) / 2.0
        if math_abs(next_g - guess) < 0.0000000001:
            return next_g
        guess = next_g
    return guess

proc math_log(x):
    if x <= 0:
        return nil
    let exp_adj = 0
    let v = x
    while v > 2:
        v = v / 2.718281828459045
        exp_adj = exp_adj + 1
    while v < 0.5:
        v = v * 2.718281828459045
        exp_adj = exp_adj - 1
    let u = v - 1.0
    let result = 0.0
    let term = u
    for n in range(1, 100):
        result = result + term / n
        term = -term * u
        if math_abs(term / (n + 1)) < 0.00000000001:
            break
    return result + exp_adj

proc math_log10(x):
    let ln_x = math_log(x)
    if ln_x == nil:
        return nil
    return ln_x / 2.302585092994046

proc math_exp(x):
    let result = 1.0
    let term = 1.0
    for n in range(1, 100):
        term = term * x / n
        result = result + term
        if math_abs(term) < 0.00000000001:
            break
    return result

# Sine via Taylor series with proper float range reduction
proc math_sin(x):
    let pi = 3.14159265358979323846
    let two_pi = 2 * pi
    # Range reduce to [-pi, pi] using repeated subtraction (% is integer-only)
    let v = x
    while v > pi:
        v = v - two_pi
    while v < -pi:
        v = v + two_pi
    let result = 0.0
    let term = v
    for n in range(20):
        result = result + term
        term = -term * v * v / ((2 * n + 2) * (2 * n + 3))
    return result

# Cosine via Taylor series
proc math_cos(x):
    let pi = 3.14159265358979323846
    let two_pi = 2 * pi
    let v = x
    while v > pi:
        v = v - two_pi
    while v < -pi:
        v = v + two_pi
    let result = 0.0
    let term = 1.0
    for n in range(20):
        result = result + term
        term = -term * v * v / ((2 * n + 1) * (2 * n + 2))
    return result

proc math_tan(x):
    let c = math_cos(x)
    if math_abs(c) < 0.0000000001:
        return nil
    return math_sin(x) / c

# ============================================================================
# IO Module
# ============================================================================

proc create_io_module():
    let m = {}
    return m

proc io_read(path):
    return io.readfile(path)

proc io_write(path, content):
    return io.writefile(path, content)

proc io_append(path, content):
    return io.appendfile(path, content)

proc io_exists(path):
    return io.exists(path)

# ============================================================================
# String Module
# ============================================================================

proc create_string_module():
    let m = {}
    return m

proc string_find(haystack, needle):
    let hlen = len(haystack)
    let nlen = len(needle)
    if nlen == 0:
        return 0
    if nlen > hlen:
        return -1
    for i in range(hlen - nlen + 1):
        let found = true
        for j in range(nlen):
            if haystack[i + j] != needle[j]:
                found = false
                break
        if found:
            return i
    return -1

proc string_rfind(haystack, needle):
    let hlen = len(haystack)
    let nlen = len(needle)
    if nlen == 0:
        return hlen
    if nlen > hlen:
        return -1
    let last = -1
    for i in range(hlen - nlen + 1):
        let found = true
        for j in range(nlen):
            if haystack[i + j] != needle[j]:
                found = false
                break
        if found:
            last = i
    return last

proc string_startswith(s, prefix):
    return startswith(s, prefix)

proc string_endswith(s, suffix):
    return endswith(s, suffix)

proc string_contains(s, sub):
    return contains(s, sub)

proc string_char_at(s, idx):
    if idx < 0 or idx >= len(s):
        return nil
    return s[idx]

proc string_repeat(s, count):
    if count <= 0:
        return ""
    let parts = []
    for i in range(count):
        push(parts, s)
    return join(parts, "")

proc string_count(s, sub):
    let slen = len(s)
    let sublen = len(sub)
    if sublen == 0:
        return 0
    let count = 0
    let i = 0
    while i <= slen - sublen:
        let found = true
        for j in range(sublen):
            if s[i + j] != sub[j]:
                found = false
                break
        if found:
            count = count + 1
            i = i + sublen
        else:
            i = i + 1
    return count

proc string_substr(s, start, length):
    let slen = len(s)
    if start < 0:
        start = 0
    if start >= slen:
        return ""
    if length < 0:
        length = 0
    if start + length > slen:
        length = slen - start
    let chars = []
    for i in range(start, start + length):
        push(chars, s[i])
    return join(chars, "")

proc string_reverse(s):
    let slen = len(s)
    let chars = []
    for i in range(slen):
        push(chars, s[slen - 1 - i])
    return join(chars, "")

# ============================================================================
# Sys Module
# ============================================================================

proc create_sys_module():
    let m = {}
    m["version"] = "1.1.0"
    m["platform"] = "sage"
    return m

# ============================================================================
# Module Registry
# ============================================================================

let g_stdlib_registry = {}

proc init_stdlib():
    g_stdlib_registry["math"] = create_math_module()
    g_stdlib_registry["io"] = create_io_module()
    g_stdlib_registry["string"] = create_string_module()
    g_stdlib_registry["sys"] = create_sys_module()

proc get_stdlib_module(name):
    if dict_has(g_stdlib_registry, name):
        return g_stdlib_registry[name]
    return nil

proc is_stdlib_module(name):
    return dict_has(g_stdlib_registry, name)
