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

# ================================================================
# Hardware I/O Assembly Emission
# ================================================================

comptime:
    let MSR_STAR = 3221225601
    let MSR_LSTAR = 3221225602
    let MSR_SFMASK = 3221225604
    let KERNEL_CS = 8
    let KERNEL_SS = 16
    let USER_CS = 24
    let USER_SS = 32
    let IF_FLAG_BIT = 512
end

proc emit_syscall_entry_asm():
    # x86_64 assembly for SYSCALL instruction entry point
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global syscall_entry" + nl
    asm = asm + ".type syscall_entry, @function" + nl
    asm = asm + "syscall_entry:" + nl
    # Swap to kernel GS base (per-cpu data)
    asm = asm + tab + "swapgs" + nl
    # Save user RSP to per-cpu area, load kernel RSP
    asm = asm + tab + "movq %rsp, %gs:8" + nl
    asm = asm + tab + "movq %gs:0, %rsp" + nl
    # Push all general-purpose registers
    asm = asm + tab + "push %r15" + nl
    asm = asm + tab + "push %r14" + nl
    asm = asm + tab + "push %r13" + nl
    asm = asm + tab + "push %r12" + nl
    asm = asm + tab + "push %r11" + nl
    asm = asm + tab + "push %r10" + nl
    asm = asm + tab + "push %r9" + nl
    asm = asm + tab + "push %r8" + nl
    asm = asm + tab + "push %rbp" + nl
    asm = asm + tab + "push %rdi" + nl
    asm = asm + tab + "push %rsi" + nl
    asm = asm + tab + "push %rdx" + nl
    asm = asm + tab + "push %rcx" + nl
    asm = asm + tab + "push %rbx" + nl
    asm = asm + tab + "push %rax" + nl
    # Syscall number in rax -> first arg (rdi) for syscall_dispatch
    asm = asm + tab + "movq %rax, %rdi" + nl
    asm = asm + tab + "call syscall_dispatch" + nl
    # Pop all general-purpose registers
    asm = asm + tab + "pop %rax" + nl
    asm = asm + tab + "pop %rbx" + nl
    asm = asm + tab + "pop %rcx" + nl
    asm = asm + tab + "pop %rdx" + nl
    asm = asm + tab + "pop %rsi" + nl
    asm = asm + tab + "pop %rdi" + nl
    asm = asm + tab + "pop %rbp" + nl
    asm = asm + tab + "pop %r8" + nl
    asm = asm + tab + "pop %r9" + nl
    asm = asm + tab + "pop %r10" + nl
    asm = asm + tab + "pop %r11" + nl
    asm = asm + tab + "pop %r12" + nl
    asm = asm + tab + "pop %r13" + nl
    asm = asm + tab + "pop %r14" + nl
    asm = asm + tab + "pop %r15" + nl
    # Restore user RSP, swap back to user GS
    asm = asm + tab + "movq %gs:8, %rsp" + nl
    asm = asm + tab + "swapgs" + nl
    asm = asm + tab + "sysretq" + nl
    return asm
end

proc emit_syscall_init_asm():
    # x86_64 assembly to configure SYSCALL/SYSRET via MSRs
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global syscall_msr_init" + nl
    asm = asm + ".type syscall_msr_init, @function" + nl
    asm = asm + "syscall_msr_init:" + nl
    # Write STAR MSR (0xC0000081): kernel CS/SS in bits 47:32, user CS/SS in bits 63:48
    # Kernel CS=0x08, SS=0x10 -> bits 47:32 = 0x0008
    # User CS=0x18|3=0x1B, SS=0x20|3=0x23 -> bits 63:48 = 0x0018 (base, CPU adds 16+3)
    asm = asm + tab + "movl $0xC0000081, %ecx" + nl
    asm = asm + tab + "xorl %edx, %edx" + nl
    asm = asm + tab + "movl $0x00180008, %edx" + nl
    asm = asm + tab + "xorl %eax, %eax" + nl
    asm = asm + tab + "wrmsr" + nl
    # Write LSTAR MSR (0xC0000082): address of syscall_entry
    asm = asm + tab + "movl $0xC0000082, %ecx" + nl
    asm = asm + tab + "leaq syscall_entry(%rip), %rax" + nl
    asm = asm + tab + "movq %rax, %rdx" + nl
    asm = asm + tab + "shrq $32, %rdx" + nl
    asm = asm + tab + "wrmsr" + nl
    # Write SFMASK MSR (0xC0000084): mask IF flag (bit 9 = 0x200)
    asm = asm + tab + "movl $0xC0000084, %ecx" + nl
    asm = asm + tab + "xorl %edx, %edx" + nl
    asm = asm + tab + "movl $0x200, %eax" + nl
    asm = asm + tab + "wrmsr" + nl
    asm = asm + tab + "ret" + nl
    return asm
end

proc emit_svc_entry_aarch64():
    # aarch64 assembly for SVC (supervisor call) exception entry
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global svc_entry" + nl
    asm = asm + ".type svc_entry, @function" + nl
    asm = asm + "svc_entry:" + nl
    # Save general-purpose registers x0-x30 and ELR_EL1 to stack
    asm = asm + tab + "sub sp, sp, #264" + nl
    asm = asm + tab + "stp x0, x1, [sp, #0]" + nl
    asm = asm + tab + "stp x2, x3, [sp, #16]" + nl
    asm = asm + tab + "stp x4, x5, [sp, #32]" + nl
    asm = asm + tab + "stp x6, x7, [sp, #48]" + nl
    asm = asm + tab + "stp x8, x9, [sp, #64]" + nl
    asm = asm + tab + "stp x10, x11, [sp, #80]" + nl
    asm = asm + tab + "stp x12, x13, [sp, #96]" + nl
    asm = asm + tab + "stp x14, x15, [sp, #112]" + nl
    asm = asm + tab + "stp x16, x17, [sp, #128]" + nl
    asm = asm + tab + "stp x18, x19, [sp, #144]" + nl
    asm = asm + tab + "stp x20, x21, [sp, #160]" + nl
    asm = asm + tab + "stp x22, x23, [sp, #176]" + nl
    asm = asm + tab + "stp x24, x25, [sp, #192]" + nl
    asm = asm + tab + "stp x26, x27, [sp, #208]" + nl
    asm = asm + tab + "stp x28, x29, [sp, #224]" + nl
    asm = asm + tab + "str x30, [sp, #240]" + nl
    asm = asm + tab + "mrs x0, ELR_EL1" + nl
    asm = asm + tab + "str x0, [sp, #248]" + nl
    # Read ESR_EL1 to get exception syndrome
    asm = asm + tab + "mrs x0, ESR_EL1" + nl
    # Extract EC field (bits 31:26) to verify SVC
    asm = asm + tab + "lsr x1, x0, #26" + nl
    asm = asm + tab + "cmp x1, #0x15" + nl
    asm = asm + tab + "b.ne .Lsvc_not_svc" + nl
    # x8 holds syscall number (AArch64 calling convention)
    asm = asm + tab + "ldr x0, [sp, #64]" + nl
    asm = asm + tab + "bl syscall_dispatch" + nl
    # Store return value
    asm = asm + tab + "str x0, [sp, #0]" + nl
    asm = asm + ".Lsvc_not_svc:" + nl
    # Restore registers
    asm = asm + tab + "ldr x0, [sp, #248]" + nl
    asm = asm + tab + "msr ELR_EL1, x0" + nl
    asm = asm + tab + "ldp x0, x1, [sp, #0]" + nl
    asm = asm + tab + "ldp x2, x3, [sp, #16]" + nl
    asm = asm + tab + "ldp x4, x5, [sp, #32]" + nl
    asm = asm + tab + "ldp x6, x7, [sp, #48]" + nl
    asm = asm + tab + "ldp x8, x9, [sp, #64]" + nl
    asm = asm + tab + "ldp x10, x11, [sp, #80]" + nl
    asm = asm + tab + "ldp x12, x13, [sp, #96]" + nl
    asm = asm + tab + "ldp x14, x15, [sp, #112]" + nl
    asm = asm + tab + "ldp x16, x17, [sp, #128]" + nl
    asm = asm + tab + "ldp x18, x19, [sp, #144]" + nl
    asm = asm + tab + "ldp x20, x21, [sp, #160]" + nl
    asm = asm + tab + "ldp x22, x23, [sp, #176]" + nl
    asm = asm + tab + "ldp x24, x25, [sp, #192]" + nl
    asm = asm + tab + "ldp x26, x27, [sp, #208]" + nl
    asm = asm + tab + "ldp x28, x29, [sp, #224]" + nl
    asm = asm + tab + "ldr x30, [sp, #240]" + nl
    asm = asm + tab + "add sp, sp, #264" + nl
    asm = asm + tab + "eret" + nl
    return asm
end

proc emit_ecall_entry_riscv64():
    # riscv64 assembly for ECALL trap entry (M-mode trap handler)
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global ecall_entry" + nl
    asm = asm + ".type ecall_entry, @function" + nl
    asm = asm + "ecall_entry:" + nl
    # Save registers to trap frame (allocate 256 bytes on stack)
    asm = asm + tab + "addi sp, sp, -256" + nl
    asm = asm + tab + "sd ra, 0(sp)" + nl
    asm = asm + tab + "sd t0, 8(sp)" + nl
    asm = asm + tab + "sd t1, 16(sp)" + nl
    asm = asm + tab + "sd t2, 24(sp)" + nl
    asm = asm + tab + "sd a0, 32(sp)" + nl
    asm = asm + tab + "sd a1, 40(sp)" + nl
    asm = asm + tab + "sd a2, 48(sp)" + nl
    asm = asm + tab + "sd a3, 56(sp)" + nl
    asm = asm + tab + "sd a4, 64(sp)" + nl
    asm = asm + tab + "sd a5, 72(sp)" + nl
    asm = asm + tab + "sd a6, 80(sp)" + nl
    asm = asm + tab + "sd a7, 88(sp)" + nl
    asm = asm + tab + "sd t3, 96(sp)" + nl
    asm = asm + tab + "sd t4, 104(sp)" + nl
    asm = asm + tab + "sd t5, 112(sp)" + nl
    asm = asm + tab + "sd t6, 120(sp)" + nl
    asm = asm + tab + "sd s0, 128(sp)" + nl
    asm = asm + tab + "sd s1, 136(sp)" + nl
    asm = asm + tab + "sd s2, 144(sp)" + nl
    asm = asm + tab + "sd s3, 152(sp)" + nl
    asm = asm + tab + "sd s4, 160(sp)" + nl
    asm = asm + tab + "sd s5, 168(sp)" + nl
    asm = asm + tab + "sd s6, 176(sp)" + nl
    asm = asm + tab + "sd s7, 184(sp)" + nl
    asm = asm + tab + "sd s8, 192(sp)" + nl
    asm = asm + tab + "sd s9, 200(sp)" + nl
    asm = asm + tab + "sd s10, 208(sp)" + nl
    asm = asm + tab + "sd s11, 216(sp)" + nl
    # Save MEPC
    asm = asm + tab + "csrr t0, mepc" + nl
    asm = asm + tab + "sd t0, 224(sp)" + nl
    # Read mcause to determine trap type
    asm = asm + tab + "csrr t0, mcause" + nl
    # Check for environment call from U-mode (cause=8)
    asm = asm + tab + "li t1, 8" + nl
    asm = asm + tab + "beq t0, t1, .Lecall_dispatch" + nl
    # Check for environment call from M-mode (cause=11)
    asm = asm + tab + "li t1, 11" + nl
    asm = asm + tab + "beq t0, t1, .Lecall_dispatch" + nl
    # Not an ecall, jump to restore
    asm = asm + tab + "j .Lecall_restore" + nl
    asm = asm + ".Lecall_dispatch:" + nl
    # a7 holds syscall number (RISC-V convention), pass as first arg (a0)
    asm = asm + tab + "mv a0, a7" + nl
    asm = asm + tab + "call syscall_dispatch" + nl
    # Store return value back to a0 slot in trap frame
    asm = asm + tab + "sd a0, 32(sp)" + nl
    # Advance MEPC past ecall instruction (+4 bytes)
    asm = asm + tab + "ld t0, 224(sp)" + nl
    asm = asm + tab + "addi t0, t0, 4" + nl
    asm = asm + tab + "sd t0, 224(sp)" + nl
    asm = asm + ".Lecall_restore:" + nl
    # Restore MEPC
    asm = asm + tab + "ld t0, 224(sp)" + nl
    asm = asm + tab + "csrw mepc, t0" + nl
    # Restore registers
    asm = asm + tab + "ld ra, 0(sp)" + nl
    asm = asm + tab + "ld t0, 8(sp)" + nl
    asm = asm + tab + "ld t1, 16(sp)" + nl
    asm = asm + tab + "ld t2, 24(sp)" + nl
    asm = asm + tab + "ld a0, 32(sp)" + nl
    asm = asm + tab + "ld a1, 40(sp)" + nl
    asm = asm + tab + "ld a2, 48(sp)" + nl
    asm = asm + tab + "ld a3, 56(sp)" + nl
    asm = asm + tab + "ld a4, 64(sp)" + nl
    asm = asm + tab + "ld a5, 72(sp)" + nl
    asm = asm + tab + "ld a6, 80(sp)" + nl
    asm = asm + tab + "ld a7, 88(sp)" + nl
    asm = asm + tab + "ld t3, 96(sp)" + nl
    asm = asm + tab + "ld t4, 104(sp)" + nl
    asm = asm + tab + "ld t5, 112(sp)" + nl
    asm = asm + tab + "ld t6, 120(sp)" + nl
    asm = asm + tab + "ld s0, 128(sp)" + nl
    asm = asm + tab + "ld s1, 136(sp)" + nl
    asm = asm + tab + "ld s2, 144(sp)" + nl
    asm = asm + tab + "ld s3, 152(sp)" + nl
    asm = asm + tab + "ld s4, 160(sp)" + nl
    asm = asm + tab + "ld s5, 168(sp)" + nl
    asm = asm + tab + "ld s6, 176(sp)" + nl
    asm = asm + tab + "ld s7, 184(sp)" + nl
    asm = asm + tab + "ld s8, 192(sp)" + nl
    asm = asm + tab + "ld s9, 200(sp)" + nl
    asm = asm + tab + "ld s10, 208(sp)" + nl
    asm = asm + tab + "ld s11, 216(sp)" + nl
    asm = asm + tab + "addi sp, sp, 256" + nl
    asm = asm + tab + "mret" + nl
    return asm
end
