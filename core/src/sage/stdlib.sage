gc_disable()
# SageLang Standard Library (self-hosted port)
#
# Pure Sage implementations of the standard library modules.
# These provide the same interfaces as the C native modules
# (math, io, string, sys, fat, net) for the self-hosted interpreter.
#
# Note: thread module requires C pthreads and cannot be ported.
# IO delegates to the C native io module for file operations.
# vm module requires C bytecode engine and cannot be ported.
# net module stubs are in net.sage; actual sockets require C.
import io
import net

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

# Helper: extract integer part from a float via string truncation
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

# asin via Newton's method: find t such that sin(t)=x
proc math_asin(x):
    if x < -1 or x > 1:
        return nil
    if x == 1:
        return 1.5707963267948966
    if x == -1:
        return -1.5707963267948966
    let t = x
    for i in range(10):
        let s = math_sin(t)
        let c = math_cos(t)
        if math_abs(c) < 0.0000000001:
            break
        t = t - (s - x) / c
    return t

# acos(x) = pi/2 - asin(x)
proc math_acos(x):
    let a = math_asin(x)
    if a == nil:
        return nil
    return 1.5707963267948966 - a

# atan via series: converges for |x|<=1, use identity for |x|>1
proc math_atan(x):
    if x > 1:
        return 1.5707963267948966 - math_atan(1.0 / x)
    if x < -1:
        return -1.5707963267948966 - math_atan(1.0 / x)
    let result = 0.0
    let term = x
    let x2 = x * x
    for n in range(50):
        result = result + term / (2 * n + 1)
        term = -term * x2
        if math_abs(term / (2 * n + 3)) < 0.00000000001:
            break
    return result

# atan2(y, x) — full quadrant arctangent
proc math_atan2(y, x):
    let pi = 3.14159265358979323846
    if x > 0:
        return math_atan(y / x)
    if x < 0 and y >= 0:
        return math_atan(y / x) + pi
    if x < 0 and y < 0:
        return math_atan(y / x) - pi
    if x == 0 and y > 0:
        return pi / 2
    if x == 0 and y < 0:
        return -pi / 2
    return 0  # x=0, y=0 -> undefined; return 0

# isnan: not equal to itself
proc math_isnan(x):
    return x != x

# isinf: larger than any finite number
proc math_isinf(x):
    if x != x:
        return false  # NaN is not inf
    return x > 1.7976931348623157e+308 or x < -1.7976931348623157e+308

# pack64: decompose a float64 into 8 bytes (little-endian IEEE 754 approximation)
# This is a best-effort pure-Sage port; exact bit representation requires C.
proc math_pack64(d):
    # Return 8 zeros as a placeholder (exact bit packing requires C)
    let result = []
    for i in range(8):
        push(result, 0)
    return result

# printm helpers — pretty-print arithmetic with alignment
proc _printm_fmt(n):
    return str(n)

proc math_printm_add(a, b):
    let res = a + b
    let sa = _printm_fmt(a)
    let sb = _printm_fmt(b)
    let sr = _printm_fmt(res)
    let max_l = len(sa)
    if len(sb) > max_l: max_l = len(sb)
    if len(sr) > max_l: max_l = len(sr)
    print "  " + string_repeat(" ", max_l - len(sa)) + sa
    print "+ " + string_repeat(" ", max_l - len(sb)) + sb
    print "--" + string_repeat("-", max_l)
    print "  " + string_repeat(" ", max_l - len(sr)) + sr
    return res

proc math_printm_sub(a, b):
    let res = a - b
    let sa = _printm_fmt(a)
    let sb = _printm_fmt(b)
    let sr = _printm_fmt(res)
    let max_l = len(sa)
    if len(sb) > max_l: max_l = len(sb)
    if len(sr) > max_l: max_l = len(sr)
    print "  " + string_repeat(" ", max_l - len(sa)) + sa
    print "- " + string_repeat(" ", max_l - len(sb)) + sb
    print "--" + string_repeat("-", max_l)
    print "  " + string_repeat(" ", max_l - len(sr)) + sr
    return res

proc math_printm_mul(a, b):
    let res = a * b
    let sa = _printm_fmt(a)
    let sb = _printm_fmt(b)
    let sr = _printm_fmt(res)
    let max_l = len(sa)
    if len(sb) > max_l: max_l = len(sb)
    if len(sr) > max_l: max_l = len(sr)
    print "  " + string_repeat(" ", max_l - len(sa)) + sa
    print "x " + string_repeat(" ", max_l - len(sb)) + sb
    print "--" + string_repeat("-", max_l)
    print "  " + string_repeat(" ", max_l - len(sr)) + sr
    return res

proc math_printm_div(a, b):
    if b == 0:
        return nil
    let res = a / b
    print str(a) + " / " + str(b) + " = " + str(res)
    return res

proc create_math_module():
    let m = {}
    # Constants
    m["pi"] = 3.14159265358979323846
    m["PI"] = 3.14159265358979323846
    m["e"] = 2.71828182845904523536
    m["tau"] = 6.28318530717958647692
    m["inf"] = tonumber("inf")
    m["nan"] = tonumber("nan")

    # Arithmetic
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

    # Trig
    m["sin"] = math_sin
    m["cos"] = math_cos
    m["tan"] = math_tan
    m["asin"] = math_asin
    m["acos"] = math_acos
    m["atan"] = math_atan
    m["atan2"] = math_atan2

    # Checks
    m["isnan"] = math_isnan
    m["isinf"] = math_isinf

    # Packing
    m["pack64"] = math_pack64

    # Printm helpers
    m["printm_add"] = math_printm_add
    m["printm_sub"] = math_printm_sub
    m["printm_mul"] = math_printm_mul
    m["printm_div"] = math_printm_div

    # Random
    m["random"] = math_random
    m["random_range"] = math_random_range
    m["random_int"] = math_random_int

    return m

# ============================================================================
# IO Module
# ============================================================================

proc io_read(path):
    return io.readfile(path)

proc io_write(path, content):
    return io.writefile(path, content)

proc io_append(path, content):
    return io.appendfile(path, content)

proc io_exists(path):
    return io.exists(path)

proc io_remove(path):
    return io.remove(path)

proc io_isdir(path):
    return io.isdir(path)

proc io_mkdir(path):
    return io.mkdir(path)

proc io_filesize(path):
    return io.filesize(path)

proc io_readbytes(path):
    return io.readbytes(path)

proc io_writebytes(path, arr):
    return io.writebytes(path, arr)

proc io_appendbytes(path, arr):
    return io.appendbytes(path, arr)

proc io_listdir(path):
    return io.listdir(path)

proc create_io_module():
    let m = {}
    m["readfile"]    = io_read
    m["writefile"]   = io_write
    m["appendfile"]  = io_append
    m["exists"]      = io_exists
    m["remove"]      = io_remove
    m["isdir"]       = io_isdir
    m["mkdir"]       = io_mkdir
    m["filesize"]    = io_filesize
    m["readbytes"]   = io_readbytes
    m["writebytes"]  = io_writebytes
    m["appendbytes"] = io_appendbytes
    m["listdir"]     = io_listdir
    return m

# ============================================================================
# String Module
# ============================================================================

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

# ord/chr delegates to host builtins
proc string_ord(s):
    if len(s) == 0:
        return nil
    return ord(s[0])

proc string_chr(code):
    if code < 0 or code > 127:
        return nil
    return chr(code)

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

proc create_string_module():
    let m = {}
    m["find"]       = string_find
    m["rfind"]      = string_rfind
    m["startswith"] = string_startswith
    m["endswith"]   = string_endswith
    m["contains"]   = string_contains
    m["char_at"]    = string_char_at
    m["ord"]        = string_ord
    m["chr"]        = string_chr
    m["repeat"]     = string_repeat
    m["count"]      = string_count
    m["substr"]     = string_substr
    m["reverse"]    = string_reverse
    return m

# ============================================================================
# Sys Module
# ============================================================================

# g_sys_args is set by the host before running user code.
# Fall back to empty array if not set.
let g_sys_args = []

proc sys_args():
    return g_sys_args

proc sys_exit(code):
    # In the self-hosted interpreter, delegate to C host.
    # There is no pure-Sage way to hard-exit; raise a sentinel.
    raise "__sys_exit__:" + str(code)

proc sys_getenv(name):
    # Environment variables are not accessible from pure Sage.
    return nil

proc sys_clock():
    return clock()

proc sys_sleep(seconds):
    # Delegation to host — no-op in pure Sage.
    return nil

proc sys_exec(cmd):
    return nil

proc sys_shell_exec(cmd):
    return ""

proc sys_call(callee):
    return nil

proc create_sys_module():
    let m = {}
    m["version"]    = "4.1.3"
    m["platform"]   = "sage"
    m["args"]       = sys_args
    m["exit"]       = sys_exit
    m["getenv"]     = sys_getenv
    m["clock"]      = sys_clock
    m["sleep"]      = sys_sleep
    m["exec"]       = sys_exec
    m["shell_exec"] = sys_shell_exec
    m["call"]       = sys_call
    return m

# ============================================================================
# FAT Module (pure Sage port of C fat module)
# ============================================================================

proc _fat_le16(bytes, off):
    return bytes[off] + bytes[off + 1] * 256

proc _fat_le32(bytes, off):
    return bytes[off] + bytes[off+1]*256 + bytes[off+2]*65536 + bytes[off+3]*16777216

proc _fat_is_pow2(x):
    if x == 0:
        return false
    return (x & (x - 1)) == 0

proc _fat_copy_trimmed(bytes, start, length):
    let end_idx = start + length - 1
    while end_idx >= start:
        let b = bytes[end_idx]
        if b != 32 and b != 0:
            break
        end_idx = end_idx - 1
    let chars = []
    for i in range(start, end_idx + 1):
        push(chars, chr(bytes[i]))
    return join(chars, "")

proc fat_parse_boot_sector(byte_arr):
    let info = {}
    info["valid"] = false
    info["fat_bits"] = 0
    info["fat_type"] = "UNKNOWN"
    info["bytes_per_sector"] = 0
    info["sectors_per_cluster"] = 0
    info["reserved_sector_count"] = 0
    info["fat_count"] = 0
    info["root_entry_count"] = 0
    info["total_sectors"] = 0
    info["sectors_per_fat"] = 0
    info["root_dir_sectors"] = 0
    info["first_data_sector"] = 0
    info["data_sector_count"] = 0
    info["cluster_count"] = 0
    info["root_cluster"] = 0
    info["media_descriptor"] = 0
    info["fs_type_label"] = ""
    info["volume_label"] = ""

    if byte_arr == nil:
        return info
    let n = len(byte_arr)
    if n < 64:
        return info

    let bps = _fat_le16(byte_arr, 11)
    let spc = byte_arr[13]
    let rsc = _fat_le16(byte_arr, 14)
    let fc  = byte_arr[16]
    let rec = _fat_le16(byte_arr, 17)
    let tot16 = _fat_le16(byte_arr, 19)
    let media = byte_arr[21]
    let fat16 = _fat_le16(byte_arr, 22)
    let tot32 = _fat_le32(byte_arr, 32)
    let fat32_spf = _fat_le32(byte_arr, 36)
    let root_clus = _fat_le32(byte_arr, 44)

    let total_sec = tot16
    if total_sec == 0:
        total_sec = tot32
    let spf = fat16
    if spf == 0:
        spf = fat32_spf

    let vol_label = ""
    let fs_type = ""
    if n >= 90:
        if rec == 0:
            vol_label = _fat_copy_trimmed(byte_arr, 71, 11)
            fs_type   = _fat_copy_trimmed(byte_arr, 82, 8)
        else:
            vol_label = _fat_copy_trimmed(byte_arr, 43, 11)
            fs_type   = _fat_copy_trimmed(byte_arr, 54, 8)

    # Validate fields
    if not _fat_is_pow2(bps) or bps < 128 or bps > 4096:
        return info
    if not _fat_is_pow2(spc) or spc == 0 or spc > 128:
        return info
    if rsc == 0 or fc == 0 or spf == 0 or total_sec == 0:
        return info

    let root_dir_secs = (rec * 32 + bps - 1) / bps
    let first_data = rsc + fc * spf + root_dir_secs
    if first_data >= total_sec:
        return info
    let data_secs = total_sec - first_data
    let cluster_count = data_secs / spc

    # Determine FAT type from cluster count
    let fat_bits = 16
    if cluster_count < 16:
        fat_bits = 8
    elif cluster_count < 4085:
        fat_bits = 12
    elif cluster_count < 65525:
        fat_bits = 16
    else:
        fat_bits = 32

    # Let fs_type label override the guess
    if startswith(fs_type, "FAT8"):  fat_bits = 8
    elif startswith(fs_type, "FAT12"): fat_bits = 12
    elif startswith(fs_type, "FAT16"): fat_bits = 16
    elif startswith(fs_type, "FAT32"): fat_bits = 32

    let fat_type_name = "UNKNOWN"
    if fat_bits == 8:  fat_type_name = "FAT8"
    elif fat_bits == 12: fat_type_name = "FAT12"
    elif fat_bits == 16: fat_type_name = "FAT16"
    elif fat_bits == 32: fat_type_name = "FAT32"

    if fat_bits == 32 and root_clus == 0:
        root_clus = 2

    info["valid"]                = true
    info["fat_bits"]             = fat_bits
    info["fat_type"]             = fat_type_name
    info["bytes_per_sector"]     = bps
    info["sectors_per_cluster"]  = spc
    info["reserved_sector_count"] = rsc
    info["fat_count"]            = fc
    info["root_entry_count"]     = rec
    info["total_sectors"]        = total_sec
    info["sectors_per_fat"]      = spf
    info["root_dir_sectors"]     = root_dir_secs
    info["first_data_sector"]    = first_data
    info["data_sector_count"]    = data_secs
    info["cluster_count"]        = cluster_count
    info["root_cluster"]         = root_clus
    info["media_descriptor"]     = media
    info["fs_type_label"]        = fs_type
    info["volume_label"]         = vol_label
    return info

proc fat_probe(path):
    let data = io.readbytes(path)
    if data == nil:
        return nil
    let info = fat_parse_boot_sector(data)
    info["source_path"] = path
    return info

proc fat_cluster_to_lba(boot_info, cluster):
    if boot_info == nil:
        return nil
    let first_data = boot_info["first_data_sector"]
    let spc = boot_info["sectors_per_cluster"]
    if cluster < 2 or spc <= 0:
        return nil
    return first_data + (cluster - 2) * spc

proc fat_fat_entry_offset(boot_info, cluster):
    if boot_info == nil:
        return nil
    let fat_bits = boot_info["fat_bits"]
    if cluster < 0:
        return nil
    let offset = 0
    let is_odd = false
    if fat_bits == 12:
        offset = (cluster * 3) / 2
        is_odd = (cluster & 1) == 1
    else:
        offset = cluster * fat_bits / 8
    let out = {}
    out["byte_offset"] = offset
    out["is_odd"]      = is_odd
    out["fat_bits"]    = fat_bits
    return out

proc create_fat_module():
    let m = {}
    m["parse_boot_sector"] = fat_parse_boot_sector
    m["probe"]             = fat_probe
    m["cluster_to_lba"]    = fat_cluster_to_lba
    m["fat_entry_offset"]  = fat_fat_entry_offset
    # Constants
    m["FAT8"]  = 8
    m["FAT12"] = 12
    m["FAT16"] = 16
    m["FAT32"] = 32
    return m

# ============================================================================
# Net Module (delegates to net.sage stubs)
# ============================================================================

proc create_net_module():
    if type(net) == "dict":
        return net.create_net_module()
    end
    return nil

# ============================================================================
# Module Registry
# ============================================================================

let g_stdlib_registry = {}

proc init_stdlib():
    g_stdlib_registry["math"]   = create_math_module()
    g_stdlib_registry["_math"]  = g_stdlib_registry["math"]   # C name alias
    g_stdlib_registry["io"]     = create_io_module()
    g_stdlib_registry["string"] = create_string_module()
    g_stdlib_registry["sys"]    = create_sys_module()
    g_stdlib_registry["fat"]    = create_fat_module()
    g_stdlib_registry["net"]    = create_net_module()

proc get_stdlib_module(name):
    if dict_has(g_stdlib_registry, name):
        return g_stdlib_registry[name]
    return nil

proc is_stdlib_module(name):
    return dict_has(g_stdlib_registry, name)
