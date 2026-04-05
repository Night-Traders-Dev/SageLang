gc_disable()

# syscall.sage — System call dispatch table
# Handles int 0x80 / SYSCALL instruction dispatch.

import console

# ----- Syscall number constants -----
let SYS_EXIT = 0
let SYS_WRITE = 1
let SYS_READ = 2
let SYS_OPEN = 3
let SYS_CLOSE = 4
let SYS_MMAP = 5
let SYS_FORK = 6
let SYS_EXEC = 7
let SYS_GETPID = 8
let SYS_YIELD = 9

# ----- Internal state -----
let syscall_handlers = []
let syscall_names = []
let syscall_counts = []
let max_syscalls = 256
let next_pid = 1
let syscall_ready = false

proc init():
    syscall_handlers = []
    syscall_names = []
    syscall_counts = []
    let i = 0
    while i < max_syscalls:
        append(syscall_handlers, nil)
        append(syscall_names, "")
        append(syscall_counts, 0)
        i = i + 1
    end
    # Register built-in syscalls
    register(SYS_EXIT, "exit", builtin_exit)
    register(SYS_WRITE, "write", builtin_write)
    register(SYS_READ, "read", builtin_read)
    register(SYS_OPEN, "open", builtin_open)
    register(SYS_CLOSE, "close", builtin_close)
    register(SYS_MMAP, "mmap", builtin_mmap)
    register(SYS_FORK, "fork", builtin_fork)
    register(SYS_EXEC, "exec", builtin_exec)
    register(SYS_GETPID, "getpid", builtin_getpid)
    register(SYS_YIELD, "yield", builtin_yield)
    syscall_ready = true
end

proc register(number, name, handler):
    if number < 0:
        return false
    end
    if number >= max_syscalls:
        return false
    end
    syscall_handlers[number] = handler
    syscall_names[number] = name
    syscall_counts[number] = 0
    return true
end

proc dispatch(syscall_num, args):
    if syscall_num < 0:
        return -1
    end
    if syscall_num >= max_syscalls:
        return -1
    end
    let handler = syscall_handlers[syscall_num]
    if handler == nil:
        return -1
    end
    syscall_counts[syscall_num] = syscall_counts[syscall_num] + 1
    return handler(args)
end

# ----- Built-in syscall implementations -----

proc sys_write(fd, buf, length):
    let args = {}
    args["fd"] = fd
    args["buf"] = buf
    args["len"] = length
    return dispatch(SYS_WRITE, args)
end

proc sys_read(fd, buf, length):
    let args = {}
    args["fd"] = fd
    args["buf"] = buf
    args["len"] = length
    return dispatch(SYS_READ, args)
end

proc sys_exit(code):
    let args = {}
    args["code"] = code
    return dispatch(SYS_EXIT, args)
end

# ----- Built-in handlers -----

proc builtin_exit(args):
    let code = 0
    if args != nil:
        if dict_has(args, "code"):
            code = args["code"]
        end
    end
    # In a real kernel this terminates the current process.
    return code
end

proc builtin_write(args):
    if args == nil:
        return -1
    end
    let fd = args["fd"]
    let buf = args["buf"]
    let length = args["len"]
    # fd 1 = stdout, fd 2 = stderr
    if fd == 1:
        console.print_str(buf)
        return length
    end
    if fd == 2:
        let old_fg = console.current_fg
        console.set_color(console.RED, console.BLACK)
        console.print_str(buf)
        console.set_color(old_fg, console.BLACK)
        return length
    end
    return -1
end

proc builtin_read(args):
    if args == nil:
        return -1
    end
    let fd = args["fd"]
    let count = 0
    if dict_has(args, "count"):
        count = args["count"]
    end
    # fd 0 = stdin — read from keyboard buffer
    if fd == 0:
        if dict_has(args, "buffer"):
            # Copy available bytes into buffer (non-blocking)
            let buf = args["buffer"]
            let read_count = 0
            while read_count < count:
                if dict_has(args, "kbd_buffer"):
                    if len(args["kbd_buffer"]) > 0:
                        push(buf, args["kbd_buffer"][0])
                        let new_buf = []
                        let ki = 1
                        while ki < len(args["kbd_buffer"]):
                            push(new_buf, args["kbd_buffer"][ki])
                            ki = ki + 1
                        end
                        args["kbd_buffer"] = new_buf
                        read_count = read_count + 1
                    else:
                        return read_count
                    end
                else:
                    return read_count
                end
            end
            return read_count
        end
        return 0
    end
    # fd 1, 2 = stdout/stderr (not readable)
    if fd == 1 or fd == 2:
        return -1
    end
    # Other fds: check open file table
    if dict_has(args, "file_table"):
        if dict_has(args["file_table"], str(fd)):
            let file = args["file_table"][str(fd)]
            if dict_has(file, "data"):
                let data = file["data"]
                let pos = file["pos"]
                let result = []
                let read_count = 0
                while read_count < count and pos < len(data):
                    push(result, data[pos])
                    pos = pos + 1
                    read_count = read_count + 1
                end
                file["pos"] = pos
                return read_count
            end
        end
    end
    return -1
end

# In-memory file table for the kernel
let _file_table = {}
let _next_fd = 3

proc builtin_open(args):
    if args == nil:
        return -1
    end
    if not dict_has(args, "path"):
        return -1
    end
    let path = args["path"]
    let flags = 0
    if dict_has(args, "flags"):
        flags = args["flags"]
    end
    # Allocate a file descriptor
    let fd = _next_fd
    _next_fd = _next_fd + 1
    let file = {}
    file["path"] = path
    file["flags"] = flags
    file["pos"] = 0
    file["data"] = []
    _file_table[str(fd)] = file
    return fd
end

proc builtin_close(args):
    if args == nil:
        return -1
    end
    let fd = args["fd"]
    let key = str(fd)
    if dict_has(_file_table, key):
        dict_delete(_file_table, key)
        return 0
    end
    return -1
end

proc builtin_mmap(args):
    if args == nil:
        return -1
    end
    let addr = 0
    if dict_has(args, "addr"):
        addr = args["addr"]
    end
    let length = 4096
    if dict_has(args, "length"):
        length = args["length"]
    end
    # Allocate a simulated memory region (array of zeros)
    let region = {}
    region["addr"] = addr
    region["length"] = length
    region["data"] = []
    let i = 0
    while i < length:
        push(region["data"], 0)
        i = i + 1
    end
    return region
end

proc builtin_fork(args):
    # Allocate a new PID for the child process
    let pid = next_pid
    next_pid = next_pid + 1
    return pid
end

proc builtin_exec(args):
    if args == nil:
        return -1
    end
    if not dict_has(args, "path"):
        return -1
    end
    # In kernel context, exec replaces the current process image
    # Return the path as confirmation (actual exec requires ELF loader)
    let path = args["path"]
    let result = {}
    result["status"] = 0
    result["path"] = path
    result["pid"] = builtin_getpid(nil)
    return result
end

proc builtin_getpid(args):
    # Return current PID (kernel init process = 1)
    return 1
end

proc builtin_yield(args):
    # Cooperative yield: in a single-tasked kernel, this is a no-op
    # In a multi-tasked kernel, this would switch to the next ready task
    # Return 0 to indicate success
    return 0
end

# ----- Introspection -----

proc syscall_table():
    let entries = []
    let i = 0
    while i < max_syscalls:
        if syscall_names[i] != "":
            let entry = {}
            entry["number"] = i
            entry["name"] = syscall_names[i]
            append(entries, entry)
        end
        i = i + 1
    end
    return entries
end

proc stats():
    let s = {}
    s["total_calls"] = 0
    let entries = []
    let i = 0
    while i < max_syscalls:
        if syscall_names[i] != "":
            let entry = {}
            entry["number"] = i
            entry["name"] = syscall_names[i]
            entry["count"] = syscall_counts[i]
            s["total_calls"] = s["total_calls"] + syscall_counts[i]
            append(entries, entry)
        end
        i = i + 1
    end
    s["syscalls"] = entries
    return s
end
