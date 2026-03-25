gc_disable()

# syscalls.sage — Linux system call interface for x86_64 and aarch64
#
# Provides constants and helpers for invoking Linux syscalls.
# Used with --compile-bare or --compile-native to generate direct syscall wrappers.
#
# x86_64 ABI: syscall instruction, rax=nr, rdi/rsi/rdx/r10/r8/r9=args
# aarch64 ABI: svc #0, x8=nr, x0-x5=args

# ----- Architecture detection -----
let ARCH_X86_64 = "x86_64"
let ARCH_AARCH64 = "aarch64"
let ARCH_RV64 = "rv64"

# ----- x86_64 syscall numbers -----
let SYS_READ = 0
let SYS_WRITE = 1
let SYS_OPEN = 2
let SYS_CLOSE = 3
let SYS_STAT = 4
let SYS_FSTAT = 5
let SYS_LSEEK = 8
let SYS_MMAP = 9
let SYS_MPROTECT = 10
let SYS_MUNMAP = 11
let SYS_BRK = 12
let SYS_IOCTL = 16
let SYS_PIPE = 22
let SYS_SELECT = 23
let SYS_SOCKET = 41
let SYS_CONNECT = 42
let SYS_ACCEPT = 43
let SYS_SENDTO = 44
let SYS_RECVFROM = 45
let SYS_BIND = 49
let SYS_LISTEN = 50
let SYS_CLONE = 56
let SYS_FORK = 57
let SYS_EXECVE = 59
let SYS_EXIT = 60
let SYS_WAIT4 = 61
let SYS_KILL = 62
let SYS_UNAME = 63
let SYS_GETPID = 39
let SYS_GETUID = 102
let SYS_GETGID = 104
let SYS_GETTID = 186
let SYS_MKDIR = 83
let SYS_RMDIR = 84
let SYS_UNLINK = 87
let SYS_RENAME = 82
let SYS_GETCWD = 79
let SYS_CHDIR = 80
let SYS_DUP = 32
let SYS_DUP2 = 33
let SYS_GETDENTS64 = 217
let SYS_OPENAT = 257
let SYS_MKDIRAT = 258
let SYS_UNLINKAT = 263
let SYS_RENAMEAT = 264
let SYS_FUTEX = 202
let SYS_EPOLL_CREATE1 = 291
let SYS_EPOLL_CTL = 233
let SYS_EPOLL_WAIT = 232
let SYS_EVENTFD2 = 290
let SYS_TIMERFD_CREATE = 283
let SYS_SIGNALFD4 = 289
let SYS_GETRANDOM = 318

# ----- aarch64 syscall numbers (Linux) -----
let ARM64_SYS_READ = 63
let ARM64_SYS_WRITE = 64
let ARM64_SYS_OPENAT = 56
let ARM64_SYS_CLOSE = 57
let ARM64_SYS_LSEEK = 62
let ARM64_SYS_MMAP = 222
let ARM64_SYS_MUNMAP = 215
let ARM64_SYS_BRK = 214
let ARM64_SYS_IOCTL = 29
let ARM64_SYS_CLONE = 220
let ARM64_SYS_EXECVE = 221
let ARM64_SYS_EXIT = 93
let ARM64_SYS_KILL = 129
let ARM64_SYS_GETPID = 172
let ARM64_SYS_SOCKET = 198
let ARM64_SYS_BIND = 200
let ARM64_SYS_LISTEN = 201
let ARM64_SYS_ACCEPT = 202
let ARM64_SYS_CONNECT = 203
let ARM64_SYS_GETRANDOM = 278

# ----- File open flags -----
let O_RDONLY = 0
let O_WRONLY = 1
let O_RDWR = 2
let O_CREAT = 64
let O_EXCL = 128
let O_TRUNC = 512
let O_APPEND = 1024
let O_NONBLOCK = 2048
let O_DIRECTORY = 65536
let O_CLOEXEC = 524288

# ----- File mode bits -----
let S_IRWXU = 448
let S_IRUSR = 256
let S_IWUSR = 128
let S_IXUSR = 64
let S_IRWXG = 56
let S_IRGRP = 32
let S_IWGRP = 16
let S_IXGRP = 8
let S_IRWXO = 7
let S_IROTH = 4
let S_IWOTH = 2
let S_IXOTH = 1

# ----- mmap protection flags -----
let PROT_NONE = 0
let PROT_READ = 1
let PROT_WRITE = 2
let PROT_EXEC = 4

# ----- mmap flags -----
let MAP_SHARED = 1
let MAP_PRIVATE = 2
let MAP_ANONYMOUS = 32
let MAP_FIXED = 16

# ----- Signal numbers -----
let SIGHUP = 1
let SIGINT = 2
let SIGQUIT = 3
let SIGKILL = 9
let SIGSEGV = 11
let SIGPIPE = 13
let SIGALRM = 14
let SIGTERM = 15
let SIGCHLD = 17
let SIGSTOP = 19
let SIGCONT = 18
let SIGUSR1 = 10
let SIGUSR2 = 12

# ----- Socket constants -----
let AF_UNIX = 1
let AF_INET = 2
let AF_INET6 = 10
let SOCK_STREAM = 1
let SOCK_DGRAM = 2
let SOCK_RAW = 3

# ----- Epoll constants -----
let EPOLLIN = 1
let EPOLLOUT = 4
let EPOLLERR = 8
let EPOLLHUP = 16
let EPOLLET = 2147483648

# ----- Clone flags -----
let CLONE_VM = 256
let CLONE_FS = 512
let CLONE_FILES = 1024
let CLONE_SIGHAND = 2048
let CLONE_THREAD = 65536
let CLONE_NEWNS = 131072
let CLONE_NEWPID = 536870912

# ========== Syscall descriptor builders ==========

proc syscall_desc(nr, name, nargs):
    let d = {}
    d["nr"] = nr
    d["name"] = name
    d["nargs"] = nargs
    return d
end

# Build a syscall invocation record (for codegen)
proc make_syscall(arch, nr, args):
    let sc = {}
    sc["arch"] = arch
    sc["nr"] = nr
    sc["args"] = args
    if arch == ARCH_X86_64:
        sc["instruction"] = "syscall"
        sc["nr_reg"] = "rax"
        let arg_regs = ["rdi", "rsi", "rdx", "r10", "r8", "r9"]
        sc["arg_regs"] = arg_regs
    end
    if arch == ARCH_AARCH64:
        sc["instruction"] = "svc #0"
        sc["nr_reg"] = "x8"
        let arg_regs = ["x0", "x1", "x2", "x3", "x4", "x5"]
        sc["arg_regs"] = arg_regs
    end
    if arch == ARCH_RV64:
        sc["instruction"] = "ecall"
        sc["nr_reg"] = "a7"
        let arg_regs = ["a0", "a1", "a2", "a3", "a4", "a5"]
        sc["arg_regs"] = arg_regs
    end
    return sc
end

# Generate inline assembly for a syscall (x86_64)
proc emit_syscall_asm_x64(nr, arg_count):
    let nl = chr(10)
    let asm = ""
    asm = asm + "    movq $" + str(nr) + ", %rax" + nl
    if arg_count >= 1:
        asm = asm + "    # arg1 already in %rdi" + nl
    end
    if arg_count >= 2:
        asm = asm + "    # arg2 already in %rsi" + nl
    end
    if arg_count >= 3:
        asm = asm + "    # arg3 already in %rdx" + nl
    end
    asm = asm + "    syscall" + nl
    return asm
end

# Generate inline assembly for a syscall (aarch64)
proc emit_syscall_asm_arm64(nr, arg_count):
    let nl = chr(10)
    let asm = ""
    asm = asm + "    mov x8, #" + str(nr) + nl
    if arg_count >= 1:
        asm = asm + "    # arg1 already in x0" + nl
    end
    asm = asm + "    svc #0" + nl
    return asm
end

# ========== High-level syscall wrappers ==========

proc sys_exit_desc(code):
    return make_syscall(ARCH_X86_64, SYS_EXIT, [code])
end

proc sys_write_desc(fd, buf, count):
    return make_syscall(ARCH_X86_64, SYS_WRITE, [fd, buf, count])
end

proc sys_read_desc(fd, buf, count):
    return make_syscall(ARCH_X86_64, SYS_READ, [fd, buf, count])
end

proc sys_open_desc(path, flags, mode):
    return make_syscall(ARCH_X86_64, SYS_OPEN, [path, flags, mode])
end

proc sys_close_desc(fd):
    return make_syscall(ARCH_X86_64, SYS_CLOSE, [fd])
end

proc sys_mmap_desc(addr, length, prot, flags, fd, offset):
    return make_syscall(ARCH_X86_64, SYS_MMAP, [addr, length, prot, flags, fd, offset])
end

proc sys_munmap_desc(addr, length):
    return make_syscall(ARCH_X86_64, SYS_MUNMAP, [addr, length])
end

proc sys_fork_desc():
    return make_syscall(ARCH_X86_64, SYS_FORK, [])
end

proc sys_getpid_desc():
    return make_syscall(ARCH_X86_64, SYS_GETPID, [])
end

proc sys_kill_desc(pid, sig):
    return make_syscall(ARCH_X86_64, SYS_KILL, [pid, sig])
end

proc sys_socket_desc(domain, sock_type, protocol):
    return make_syscall(ARCH_X86_64, SYS_SOCKET, [domain, sock_type, protocol])
end

# ========== Syscall table (for kernel-side dispatch) ==========

proc build_syscall_table():
    let table = []
    append(table, syscall_desc(SYS_READ, "read", 3))
    append(table, syscall_desc(SYS_WRITE, "write", 3))
    append(table, syscall_desc(SYS_OPEN, "open", 3))
    append(table, syscall_desc(SYS_CLOSE, "close", 1))
    append(table, syscall_desc(SYS_STAT, "stat", 2))
    append(table, syscall_desc(SYS_FSTAT, "fstat", 2))
    append(table, syscall_desc(SYS_LSEEK, "lseek", 3))
    append(table, syscall_desc(SYS_MMAP, "mmap", 6))
    append(table, syscall_desc(SYS_MPROTECT, "mprotect", 3))
    append(table, syscall_desc(SYS_MUNMAP, "munmap", 2))
    append(table, syscall_desc(SYS_BRK, "brk", 1))
    append(table, syscall_desc(SYS_IOCTL, "ioctl", 3))
    append(table, syscall_desc(SYS_FORK, "fork", 0))
    append(table, syscall_desc(SYS_EXECVE, "execve", 3))
    append(table, syscall_desc(SYS_EXIT, "exit", 1))
    append(table, syscall_desc(SYS_KILL, "kill", 2))
    append(table, syscall_desc(SYS_GETPID, "getpid", 0))
    append(table, syscall_desc(SYS_SOCKET, "socket", 3))
    append(table, syscall_desc(SYS_BIND, "bind", 3))
    append(table, syscall_desc(SYS_LISTEN, "listen", 2))
    append(table, syscall_desc(SYS_ACCEPT, "accept", 3))
    append(table, syscall_desc(SYS_CONNECT, "connect", 3))
    append(table, syscall_desc(SYS_GETRANDOM, "getrandom", 3))
    return table
end

# Get the arch-specific syscall number
proc get_syscall_nr(arch, name):
    let table = build_syscall_table()
    let i = 0
    while i < len(table):
        if table[i]["name"] == name:
            return table[i]["nr"]
        end
        i = i + 1
    end
    return -1
end
