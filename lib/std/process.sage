gc_disable()
# Process management and environment utilities
# Wraps sys module with higher-level abstractions

import sys

# ============================================================================
# Environment variables
# ============================================================================

proc get_env(name):
    return sys.getenv(name)

proc get_env_or(name, default_val):
    let val = sys.getenv(name)
    if val == nil:
        return default_val
    return val

# ============================================================================
# Process info
# ============================================================================

proc platform():
    return sys.platform

proc version():
    return sys.version

proc args():
    return sys.args

# ============================================================================
# Exit codes
# ============================================================================

let EXIT_SUCCESS = 0
let EXIT_FAILURE = 1
let EXIT_USAGE = 64
let EXIT_DATA_ERR = 65
let EXIT_NO_INPUT = 66
let EXIT_SOFTWARE = 70
let EXIT_OS_ERR = 71
let EXIT_IO_ERR = 74
let EXIT_CONFIG = 78

proc exit_with(code):
    sys.exit(code)

proc exit_ok():
    sys.exit(0)

proc exit_error(message):
    print message
    sys.exit(1)

# ============================================================================
# Path utilities
# ============================================================================

proc path_separator():
    let p = platform()
    if p == "windows":
        return chr(92)
    return "/"

proc join_path(parts):
    let sep = path_separator()
    let result = ""
    for i in range(len(parts)):
        if i > 0:
            result = result + sep
        result = result + parts[i]
    return result

proc basename(path):
    let sep = path_separator()
    let last = 0
    for i in range(len(path)):
        if path[i] == sep or path[i] == "/":
            last = i + 1
    let result = ""
    for i in range(len(path) - last):
        result = result + path[last + i]
    return result

proc dirname(path):
    let sep = path_separator()
    let last = 0
    for i in range(len(path)):
        if path[i] == sep or path[i] == "/":
            last = i
    let result = ""
    for i in range(last):
        result = result + path[i]
    if len(result) == 0:
        return "."
    return result

proc extension(path):
    let name = basename(path)
    let dot = -1
    for i in range(len(name)):
        if name[i] == ".":
            dot = i
    if dot < 1:
        return ""
    let ext = ""
    for i in range(len(name) - dot - 1):
        ext = ext + name[dot + 1 + i]
    return ext

# ============================================================================
# Timer
# ============================================================================

proc timer_start():
    return clock()

proc timer_elapsed(start_time):
    return clock() - start_time

proc timer_elapsed_ms(start_time):
    return (clock() - start_time) * 1000
