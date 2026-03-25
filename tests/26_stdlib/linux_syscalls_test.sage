gc_disable()
# EXPECT: syscall_numbers
# EXPECT: make_syscall_x64
# EXPECT: make_syscall_arm64
# EXPECT: asm_emit
# EXPECT: syscall_table
# EXPECT: get_nr_found
# EXPECT: open_flags
# EXPECT: signal_numbers
# EXPECT: socket_constants
# EXPECT: PASS

# Test Linux syscall number definitions
let SYS_READ = 0
let SYS_WRITE = 1
let SYS_OPEN = 2
let SYS_CLOSE = 3
let SYS_EXIT = 60
let SYS_FORK = 57
let SYS_GETPID = 39
let SYS_KILL = 62
let SYS_MMAP = 9
let SYS_SOCKET = 41
if SYS_READ == 0:
    if SYS_WRITE == 1:
        if SYS_EXIT == 60:
            if SYS_MMAP == 9:
                print "syscall_numbers"

# Test make_syscall descriptor
proc make_syscall(arch, nr, args):
    let sc = {}
    sc["arch"] = arch
    sc["nr"] = nr
    sc["args"] = args
    if arch == "x86_64":
        sc["instruction"] = "syscall"
        sc["nr_reg"] = "rax"
    if arch == "aarch64":
        sc["instruction"] = "svc #0"
        sc["nr_reg"] = "x8"
    return sc

let sc_x64 = make_syscall("x86_64", SYS_WRITE, [1, 0, 13])
if sc_x64["instruction"] == "syscall":
    if sc_x64["nr_reg"] == "rax":
        if sc_x64["nr"] == 1:
            print "make_syscall_x64"

let sc_arm = make_syscall("aarch64", 64, [1, 0, 13])
if sc_arm["instruction"] == "svc #0":
    if sc_arm["nr_reg"] == "x8":
        print "make_syscall_arm64"

# Test x86_64 asm emission
proc emit_syscall_asm_x64(nr, arg_count):
    let nl = chr(10)
    let asm = ""
    asm = asm + "    movq $" + str(nr) + ", %rax" + nl
    asm = asm + "    syscall" + nl
    return asm

let asm = emit_syscall_asm_x64(SYS_WRITE, 3)
if contains(asm, "movq $1"):
    if contains(asm, "syscall"):
        print "asm_emit"

# Test syscall table building
proc syscall_desc(nr, name, nargs):
    let d = {}
    d["nr"] = nr
    d["name"] = name
    d["nargs"] = nargs
    return d

let table = []
push(table, syscall_desc(SYS_READ, "read", 3))
push(table, syscall_desc(SYS_WRITE, "write", 3))
push(table, syscall_desc(SYS_OPEN, "open", 3))
push(table, syscall_desc(SYS_CLOSE, "close", 1))
push(table, syscall_desc(SYS_EXIT, "exit", 1))
if len(table) == 5:
    if table[0]["name"] == "read":
        if table[4]["name"] == "exit":
            print "syscall_table"

# Test get_syscall_nr lookup
proc get_syscall_nr(tbl, name):
    let i = 0
    while i < len(tbl):
        if tbl[i]["name"] == name:
            return tbl[i]["nr"]
        i = i + 1
    return -1

let nr = get_syscall_nr(table, "write")
if nr == 1:
    print "get_nr_found"

# Test file open flags
let O_RDONLY = 0
let O_WRONLY = 1
let O_RDWR = 2
let O_CREAT = 64
let O_TRUNC = 512
let O_APPEND = 1024
let combined = O_WRONLY + O_CREAT + O_TRUNC
if combined == 577:
    print "open_flags"

# Test signal numbers
let SIGHUP = 1
let SIGINT = 2
let SIGKILL = 9
let SIGTERM = 15
if SIGKILL == 9:
    if SIGTERM == 15:
        print "signal_numbers"

# Test socket constants
let AF_INET = 2
let SOCK_STREAM = 1
let SOCK_DGRAM = 2
if AF_INET == 2:
    if SOCK_STREAM == 1:
        print "socket_constants"

print "PASS"
