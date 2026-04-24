gc_disable()

# build.sage — Integration layer for building bootable kernel images
#
# Ties together start.sage (boot assembly), linker.sage (linker scripts),
# serial.sage (UART output), and qemu.sage (VM launching) into a single
# pipeline that produces bootable ELF or flat binary images for
# x86_64, aarch64, and riscv64.
#
# Usage:
#   from boot.build import build_kernel, qemu_command
#   let img = build_kernel("x86_64", "kernel.c", "kernel.elf")
#   let cmd = qemu_command("x86_64", "kernel.elf")

import io
import os.serial
import os.qemu
import os.boot.start as start
import os.boot.linker as linker

let NL = chr(10)

# ============================================================================
# QEMU default UART addresses per architecture
# ============================================================================

comptime:
    let UART_X86_BASE = 1016
    let UART_AARCH64_BASE = 150994944
    let UART_RISCV64_BASE = 268435456
    let UART_BAUD = 115200

# ============================================================================
# Assembler / linker tool names per architecture
# ============================================================================

comptime:
    let AS_X86 = "as"
    let AS_AARCH64 = "aarch64-linux-gnu-as"
    let AS_RISCV64 = "riscv64-linux-gnu-as"
    let LD_X86 = "ld"
    let LD_AARCH64 = "aarch64-linux-gnu-ld"
    let LD_RISCV64 = "riscv64-linux-gnu-ld"
    let CC_X86 = "gcc"
    let CC_AARCH64 = "aarch64-linux-gnu-gcc"
    let CC_RISCV64 = "riscv64-linux-gnu-gcc"
    let OBJCOPY_X86 = "objcopy"
    let OBJCOPY_AARCH64 = "aarch64-linux-gnu-objcopy"
    let OBJCOPY_RISCV64 = "riscv64-linux-gnu-objcopy"

# ============================================================================
# Tool selection helpers
# ============================================================================

@inline
proc get_assembler(arch):
    if arch == "x86_64":
        return AS_X86
    end
    if arch == "aarch64":
        return AS_AARCH64
    end
    if arch == "riscv64":
        return AS_RISCV64
    end
    return "as"
end

@inline
proc get_linker(arch):
    if arch == "x86_64":
        return LD_X86
    end
    if arch == "aarch64":
        return LD_AARCH64
    end
    if arch == "riscv64":
        return LD_RISCV64
    end
    return "ld"
end

@inline
proc get_cc(arch):
    if arch == "x86_64":
        return CC_X86
    end
    if arch == "aarch64":
        return CC_AARCH64
    end
    if arch == "riscv64":
        return CC_RISCV64
    end
    return "gcc"
end

@inline
proc get_objcopy(arch):
    if arch == "x86_64":
        return OBJCOPY_X86
    end
    if arch == "aarch64":
        return OBJCOPY_AARCH64
    end
    if arch == "riscv64":
        return OBJCOPY_RISCV64
    end
    return "objcopy"
end

@inline
proc get_uart_base(arch):
    if arch == "x86_64":
        return UART_X86_BASE
    end
    if arch == "aarch64":
        return UART_AARCH64_BASE
    end
    if arch == "riscv64":
        return UART_RISCV64_BASE
    end
    return 0
end

# ============================================================================
# Assembly generation: serial-enabled boot stub + kernel glue
# ============================================================================

proc generate_serial_boot_x86():
    let asm = ""
    # Serial init for COM1 (0x3F8) at 115200 baud
    asm = asm + ".section .text" + NL
    asm = asm + ".global serial_init, serial_putchar, serial_puts" + NL
    asm = asm + "serial_init:" + NL
    asm = asm + "    # Disable interrupts on COM1" + NL
    asm = asm + "    movw $0x3F9, %dx" + NL
    asm = asm + "    xorb %al, %al" + NL
    asm = asm + "    outb %al, %dx" + NL
    asm = asm + "    # Enable DLAB" + NL
    asm = asm + "    movw $0x3FB, %dx" + NL
    asm = asm + "    movb $0x80, %al" + NL
    asm = asm + "    outb %al, %dx" + NL
    asm = asm + "    # Divisor = 1 (115200 baud)" + NL
    asm = asm + "    movw $0x3F8, %dx" + NL
    asm = asm + "    movb $0x01, %al" + NL
    asm = asm + "    outb %al, %dx" + NL
    asm = asm + "    movw $0x3F9, %dx" + NL
    asm = asm + "    xorb %al, %al" + NL
    asm = asm + "    outb %al, %dx" + NL
    asm = asm + "    # 8N1" + NL
    asm = asm + "    movw $0x3FB, %dx" + NL
    asm = asm + "    movb $0x03, %al" + NL
    asm = asm + "    outb %al, %dx" + NL
    asm = asm + "    # Enable FIFO" + NL
    asm = asm + "    movw $0x3FA, %dx" + NL
    asm = asm + "    movb $0xC7, %al" + NL
    asm = asm + "    outb %al, %dx" + NL
    asm = asm + "    # DTR + RTS + OUT2" + NL
    asm = asm + "    movw $0x3FC, %dx" + NL
    asm = asm + "    movb $0x0B, %al" + NL
    asm = asm + "    outb %al, %dx" + NL
    asm = asm + "    ret" + NL
    asm = asm + NL
    # serial_putchar: write byte in %dil to COM1
    asm = asm + "serial_putchar:" + NL
    asm = asm + "    pushq %rdx" + NL
    asm = asm + "    pushq %rax" + NL
    asm = asm + ".Lwait_tx:" + NL
    asm = asm + "    movw $0x3FD, %dx" + NL
    asm = asm + "    inb %dx, %al" + NL
    asm = asm + "    testb $0x20, %al" + NL
    asm = asm + "    jz .Lwait_tx" + NL
    asm = asm + "    movw $0x3F8, %dx" + NL
    asm = asm + "    movb %dil, %al" + NL
    asm = asm + "    outb %al, %dx" + NL
    asm = asm + "    popq %rax" + NL
    asm = asm + "    popq %rdx" + NL
    asm = asm + "    ret" + NL
    asm = asm + NL
    # serial_puts: write null-terminated string at %rsi to COM1
    asm = asm + "serial_puts:" + NL
    asm = asm + "    pushq %rsi" + NL
    asm = asm + "    pushq %rdi" + NL
    asm = asm + ".Lputs_loop:" + NL
    asm = asm + "    lodsb" + NL
    asm = asm + "    testb %al, %al" + NL
    asm = asm + "    jz .Lputs_done" + NL
    asm = asm + "    movb %al, %dil" + NL
    asm = asm + "    call serial_putchar" + NL
    asm = asm + "    jmp .Lputs_loop" + NL
    asm = asm + ".Lputs_done:" + NL
    asm = asm + "    popq %rdi" + NL
    asm = asm + "    popq %rsi" + NL
    asm = asm + "    ret" + NL
    asm = asm + NL
    return asm
end

proc generate_serial_boot_aarch64():
    let base = "0x09000000"
    let asm = ""
    asm = asm + ".section .text" + NL
    asm = asm + ".global serial_init, serial_putchar, serial_puts" + NL
    # PL011 init
    asm = asm + "serial_init:" + NL
    asm = asm + "    ldr x1, =" + base + NL
    asm = asm + "    # Disable UART" + NL
    asm = asm + "    str wzr, [x1, #48]" + NL
    asm = asm + "    # IBRD = 26 (48MHz / 16 / 115200)" + NL
    asm = asm + "    mov w2, #26" + NL
    asm = asm + "    str w2, [x1, #36]" + NL
    asm = asm + "    # FBRD = 3" + NL
    asm = asm + "    mov w2, #3" + NL
    asm = asm + "    str w2, [x1, #40]" + NL
    asm = asm + "    # LCRH: 8-bit, FIFO enable" + NL
    asm = asm + "    mov w2, #0x70" + NL
    asm = asm + "    str w2, [x1, #44]" + NL
    asm = asm + "    # Enable UART, TX, RX" + NL
    asm = asm + "    mov w2, #0x301" + NL
    asm = asm + "    str w2, [x1, #48]" + NL
    asm = asm + "    ret" + NL
    asm = asm + NL
    # serial_putchar: write byte in w0
    asm = asm + "serial_putchar:" + NL
    asm = asm + "    ldr x1, =" + base + NL
    asm = asm + ".Lwait_tx:" + NL
    asm = asm + "    ldr w2, [x1, #24]" + NL
    asm = asm + "    tst w2, #0x20" + NL
    asm = asm + "    b.ne .Lwait_tx" + NL
    asm = asm + "    str w0, [x1]" + NL
    asm = asm + "    ret" + NL
    asm = asm + NL
    # serial_puts: write null-terminated string at x0
    asm = asm + "serial_puts:" + NL
    asm = asm + "    stp x29, x30, [sp, #-16]!" + NL
    asm = asm + "    mov x19, x0" + NL
    asm = asm + ".Lputs_loop:" + NL
    asm = asm + "    ldrb w0, [x19], #1" + NL
    asm = asm + "    cbz w0, .Lputs_done" + NL
    asm = asm + "    bl serial_putchar" + NL
    asm = asm + "    b .Lputs_loop" + NL
    asm = asm + ".Lputs_done:" + NL
    asm = asm + "    ldp x29, x30, [sp], #16" + NL
    asm = asm + "    ret" + NL
    asm = asm + NL
    return asm
end

proc generate_serial_boot_riscv64():
    let base = "0x10000000"
    let asm = ""
    asm = asm + ".section .text" + NL
    asm = asm + ".global serial_init, serial_putchar, serial_puts" + NL
    # 16550 MMIO init
    asm = asm + "serial_init:" + NL
    asm = asm + "    li t0, " + base + NL
    asm = asm + "    # Disable interrupts" + NL
    asm = asm + "    sb zero, 1(t0)" + NL
    asm = asm + "    # Enable DLAB" + NL
    asm = asm + "    li t1, 0x80" + NL
    asm = asm + "    sb t1, 3(t0)" + NL
    asm = asm + "    # Divisor = 1 (115200 baud at 1.8432MHz)" + NL
    asm = asm + "    li t1, 1" + NL
    asm = asm + "    sb t1, 0(t0)" + NL
    asm = asm + "    sb zero, 1(t0)" + NL
    asm = asm + "    # 8N1" + NL
    asm = asm + "    li t1, 3" + NL
    asm = asm + "    sb t1, 3(t0)" + NL
    asm = asm + "    # Enable FIFO" + NL
    asm = asm + "    li t1, 0xC7" + NL
    asm = asm + "    sb t1, 2(t0)" + NL
    asm = asm + "    # DTR + RTS + OUT2" + NL
    asm = asm + "    li t1, 0x0B" + NL
    asm = asm + "    sb t1, 4(t0)" + NL
    asm = asm + "    ret" + NL
    asm = asm + NL
    # serial_putchar: write byte in a0
    asm = asm + "serial_putchar:" + NL
    asm = asm + "    li t0, " + base + NL
    asm = asm + ".Lwait_tx:" + NL
    asm = asm + "    lb t1, 5(t0)" + NL
    asm = asm + "    andi t1, t1, 0x20" + NL
    asm = asm + "    beqz t1, .Lwait_tx" + NL
    asm = asm + "    sb a0, 0(t0)" + NL
    asm = asm + "    ret" + NL
    asm = asm + NL
    # serial_puts: write null-terminated string at a0
    asm = asm + "serial_puts:" + NL
    asm = asm + "    addi sp, sp, -16" + NL
    asm = asm + "    sd ra, 8(sp)" + NL
    asm = asm + "    sd s0, 0(sp)" + NL
    asm = asm + "    mv s0, a0" + NL
    asm = asm + ".Lputs_loop:" + NL
    asm = asm + "    lb a0, 0(s0)" + NL
    asm = asm + "    beqz a0, .Lputs_done" + NL
    asm = asm + "    call serial_putchar" + NL
    asm = asm + "    addi s0, s0, 1" + NL
    asm = asm + "    j .Lputs_loop" + NL
    asm = asm + ".Lputs_done:" + NL
    asm = asm + "    ld ra, 8(sp)" + NL
    asm = asm + "    ld s0, 0(sp)" + NL
    asm = asm + "    addi sp, sp, 16" + NL
    asm = asm + "    ret" + NL
    asm = asm + NL
    return asm
end

# ============================================================================
# Minimal C kernel template generation
# ============================================================================

# Generate a 32-bit linker script for x86 multiboot1 QEMU-direct loading
proc generate_linker_x86_mb1():
    let s = ""
    s = s + "ENTRY(_start)" + NL
    s = s + "OUTPUT_FORMAT(" + chr(34) + "elf32-i386" + chr(34) + ")" + NL
    s = s + "SECTIONS {" + NL
    s = s + "    . = 1048576;" + NL
    s = s + "    .multiboot ALIGN(4) : SUBALIGN(4) {" + NL
    s = s + "        *(.multiboot)" + NL
    s = s + "    }" + NL
    s = s + "    .text ALIGN(16) : {" + NL
    s = s + "        *(.text .text.*)" + NL
    s = s + "    }" + NL
    s = s + "    .rodata ALIGN(16) : {" + NL
    s = s + "        *(.rodata .rodata.*)" + NL
    s = s + "    }" + NL
    s = s + "    .data ALIGN(16) : {" + NL
    s = s + "        *(.data .data.*)" + NL
    s = s + "    }" + NL
    s = s + "    .bss ALIGN(16) : {" + NL
    s = s + "        __bss_start = .;" + NL
    s = s + "        *(.bss .bss.*)" + NL
    s = s + "        *(COMMON)" + NL
    s = s + "        __bss_end = .;" + NL
    s = s + "    }" + NL
    s = s + "}" + NL
    return s
end

proc generate_kernel_c(arch, message):
    let c = ""
    c = c + "/* Minimal bare-metal kernel — generated by Sage */" + NL
    c = c + "void serial_init(void);" + NL
    c = c + "void serial_putchar(char c);" + NL
    c = c + "void serial_puts(const char *s);" + NL
    c = c + NL
    c = c + "void kmain(void) {" + NL
    c = c + "    serial_init();" + NL
    c = c + "    serial_puts(" + chr(34) + message + chr(92) + "r" + chr(92) + "n" + chr(34) + ");" + NL
    c = c + "    while (1) {" + NL
    if arch == "x86_64":
        c = c + "        __asm__ volatile(\"hlt\");" + NL
    end
    if arch == "aarch64":
        c = c + "        __asm__ volatile(\"wfe\");" + NL
    end
    if arch == "riscv64":
        c = c + "        __asm__ volatile(\"wfi\");" + NL
    end
    c = c + "    }" + NL
    c = c + "}" + NL
    return c
end

# ============================================================================
# Full build command generation
# ============================================================================

comptime:
    let BARE_METAL_C = "src/c/bare_metal.c"

proc build_commands(arch, boot_asm_path, kernel_c_path, linker_script_path, output_elf):
    let as_cmd = get_assembler(arch)
    let cc = get_cc(arch)
    let ld = get_linker(arch)
    let cmds = []

    let boot_obj = "boot.o"
    let kernel_obj = "kernel.o"

    # Step 1: Assemble boot stub
    if arch == "x86_64":
        push(cmds, as_cmd + " --64 -o " + boot_obj + " " + boot_asm_path)
    end
    if arch == "aarch64":
        push(cmds, as_cmd + " -o " + boot_obj + " " + boot_asm_path)
    end
    if arch == "riscv64":
        push(cmds, as_cmd + " -march=rv64gc -mabi=lp64d -o " + boot_obj + " " + boot_asm_path)
    end

    # Step 2: Compile kernel C code
    if arch == "x86_64":
        push(cmds, cc + " -ffreestanding -nostdlib -mno-red-zone -c -o " + kernel_obj + " " + kernel_c_path)
    end
    if arch == "aarch64":
        push(cmds, cc + " -ffreestanding -nostdlib -c -o " + kernel_obj + " " + kernel_c_path)
    end
    if arch == "riscv64":
        push(cmds, cc + " -ffreestanding -nostdlib -march=rv64gc -mabi=lp64d -c -o " + kernel_obj + " " + kernel_c_path)
    end

    # Step 3: Link into ELF
    push(cmds, ld + " -T " + linker_script_path + " -o " + output_elf + " " + boot_obj + " " + kernel_obj)

    return cmds
end

# Build commands with bare_metal.c runtime linked in (provides memset, memcpy,
# inb/outb, cli/sti/hlt, rdmsr/wrmsr, invlpg, read_cr3/write_cr3)
proc build_commands_with_runtime(arch, boot_asm_path, kernel_c_path, linker_script_path, output_elf, sage_root):
    let as_cmd = get_assembler(arch)
    let cc = get_cc(arch)
    let ld = get_linker(arch)
    let cmds = []

    let boot_obj = "boot.o"
    let kernel_obj = "kernel.o"
    let runtime_obj = "bare_metal.o"
    let runtime_src = sage_root + "/" + BARE_METAL_C

    # Step 1: Assemble boot stub
    if arch == "x86_64":
        push(cmds, as_cmd + " --64 -o " + boot_obj + " " + boot_asm_path)
    end
    if arch == "aarch64":
        push(cmds, as_cmd + " -o " + boot_obj + " " + boot_asm_path)
    end
    if arch == "riscv64":
        push(cmds, as_cmd + " -march=rv64gc -mabi=lp64d -o " + boot_obj + " " + boot_asm_path)
    end

    # Step 2: Compile kernel C code
    let cflags = " -ffreestanding -nostdlib -DSAGE_BARE_METAL"
    if arch == "x86_64":
        cflags = cflags + " -mno-red-zone"
    end
    if arch == "riscv64":
        cflags = cflags + " -march=rv64gc -mabi=lp64d"
    end
    push(cmds, cc + cflags + " -c -o " + kernel_obj + " " + kernel_c_path)

    # Step 3: Compile bare_metal.c runtime
    push(cmds, cc + cflags + " -c -o " + runtime_obj + " " + runtime_src)

    # Step 4: Link all objects
    push(cmds, ld + " -T " + linker_script_path + " -o " + output_elf + " " + boot_obj + " " + kernel_obj + " " + runtime_obj)

    return cmds
end

# ============================================================================
# QEMU launch command generation
# ============================================================================

proc qemu_command(arch, kernel_path):
    if arch == "x86_64":
        return "qemu-system-x86_64 -m 128M -display none -serial mon:stdio -kernel " + kernel_path
    end
    if arch == "aarch64":
        return "qemu-system-aarch64 -machine virt -cpu cortex-a57 -m 128M -display none -serial mon:stdio -kernel " + kernel_path
    end
    if arch == "riscv64":
        return "qemu-system-riscv64 -machine virt -m 128M -display none -serial mon:stdio -bios none -kernel " + kernel_path
    end
    return ""
end

proc qemu_command_debug(arch, kernel_path, gdb_port):
    return qemu_command(arch, kernel_path) + " -s -S -gdb tcp::" + str(gdb_port)
end

# ============================================================================
# High-level build pipeline
# ============================================================================

proc write_build_files(arch, output_dir, message):
    let result = {}

    # Generate boot assembly with serial support
    let boot_asm = ""
    if arch == "x86_64":
        boot_asm = start.generate_boot_asm(nil)
        boot_asm = boot_asm + generate_serial_boot_x86()
    end
    if arch == "aarch64":
        boot_asm = start.emit_start_aarch64("kmain", "stack_top")
        boot_asm = boot_asm + generate_serial_boot_aarch64()
    end
    if arch == "riscv64":
        boot_asm = start.emit_start_riscv64("kmain", "stack_top")
        boot_asm = boot_asm + generate_serial_boot_riscv64()
    end

    # Generate minimal kernel
    let kernel_c = generate_kernel_c(arch, message)

    # Generate linker script
    let ld_config = linker.default_config()
    if arch == "aarch64":
        ld_config["base_address"] = 1073741824
    end
    if arch == "riscv64":
        ld_config["base_address"] = 2147483648
    end
    let linker_script = linker.generate_script(ld_config)

    # Write files
    let boot_path = output_dir + "/boot.S"
    let kernel_path = output_dir + "/kernel.c"
    let linker_path = output_dir + "/linker.ld"
    let elf_path = output_dir + "/kernel.elf"

    io.writefile(boot_path, boot_asm)
    io.writefile(kernel_path, kernel_c)
    io.writefile(linker_path, linker_script)

    result["boot_asm"] = boot_path
    result["kernel_c"] = kernel_path
    result["linker_script"] = linker_path
    result["output_elf"] = elf_path
    result["build_commands"] = build_commands(arch, boot_path, kernel_path, linker_path, elf_path)
    result["qemu_command"] = qemu_command(arch, elf_path)
    return result
end

# ============================================================================
# One-shot build + run script generation
# ============================================================================

proc generate_build_script(arch, output_dir, message):
    let files = write_build_files(arch, output_dir, message)
    let script = "#!/bin/sh" + NL
    script = script + "set -e" + NL
    script = script + "echo 'Building " + arch + " kernel...'" + NL
    for cmd in files["build_commands"]:
        script = script + "echo '  " + cmd + "'" + NL
        script = script + cmd + NL
    end
    script = script + "echo 'Build complete: " + files["output_elf"] + "'" + NL
    script = script + "echo 'Run with:'" + NL
    script = script + "echo '  " + files["qemu_command"] + "'" + NL
    return script
end
