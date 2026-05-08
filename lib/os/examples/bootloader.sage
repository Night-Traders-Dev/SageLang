gc_disable()
# =============================================================================
# SageOS Example 1: Standalone Multiboot2 Bootloader
# =============================================================================
# Generates a minimal x86_64 Multiboot2-compliant bootloader that:
#   - Transitions from 32-bit protected mode to 64-bit long mode
#   - Sets up a GDT, enables PAE paging, activates long mode
#   - Prints "SageOS Bootloader OK" via serial (COM1) and halts
#
# Usage:
#   sage lib/os/examples/bootloader.sage
#   # Then run the printed QEMU command
# =============================================================================

import sys
import io
import os.boot.start as start
import os.boot.linker as linker
import os.qemu as qemu

let NL = chr(10)
let OUT = "/tmp/sageos_bootloader"

print "=== SageOS Standalone Bootloader ==="
print "Generating boot assembly..."

# ---- Generate boot assembly (Multiboot2 + 32->64 transition) ----
let boot_asm = start.generate_boot_asm({})

# Append a 64-bit entry that prints via serial and halts
boot_asm = boot_asm + NL
boot_asm = boot_asm + "# 64-bit kernel entry" + NL
boot_asm = boot_asm + ".code64" + NL
boot_asm = boot_asm + ".global kmain" + NL
boot_asm = boot_asm + "kmain:" + NL
boot_asm = boot_asm + "    # Initialize COM1 serial port (115200 baud)" + NL
boot_asm = boot_asm + "    movw $0x3F9, %dx" + NL
boot_asm = boot_asm + "    xorb %al, %al" + NL
boot_asm = boot_asm + "    outb %al, %dx" + NL
boot_asm = boot_asm + "    movw $0x3FB, %dx" + NL
boot_asm = boot_asm + "    movb $0x80, %al" + NL
boot_asm = boot_asm + "    outb %al, %dx" + NL
boot_asm = boot_asm + "    movw $0x3F8, %dx" + NL
boot_asm = boot_asm + "    movb $0x01, %al" + NL
boot_asm = boot_asm + "    outb %al, %dx" + NL
boot_asm = boot_asm + "    movw $0x3F9, %dx" + NL
boot_asm = boot_asm + "    xorb %al, %al" + NL
boot_asm = boot_asm + "    outb %al, %dx" + NL
boot_asm = boot_asm + "    movw $0x3FB, %dx" + NL
boot_asm = boot_asm + "    movb $0x03, %al" + NL
boot_asm = boot_asm + "    outb %al, %dx" + NL
boot_asm = boot_asm + "    movw $0x3FA, %dx" + NL
boot_asm = boot_asm + "    movb $0xC7, %al" + NL
boot_asm = boot_asm + "    outb %al, %dx" + NL
boot_asm = boot_asm + "    movw $0x3FC, %dx" + NL
boot_asm = boot_asm + "    movb $0x0B, %al" + NL
boot_asm = boot_asm + "    outb %al, %dx" + NL
boot_asm = boot_asm + "    # Print message via serial" + NL
boot_asm = boot_asm + "    leaq boot_msg(%rip), %rsi" + NL
boot_asm = boot_asm + ".Lprint_loop:" + NL
boot_asm = boot_asm + "    movzbl (%rsi), %eax" + NL
boot_asm = boot_asm + "    testb %al, %al" + NL
boot_asm = boot_asm + "    jz .Lhalt" + NL
boot_asm = boot_asm + ".Lwait_serial:" + NL
boot_asm = boot_asm + "    movw $0x3FD, %dx" + NL
boot_asm = boot_asm + "    inb %dx, %al" + NL
boot_asm = boot_asm + "    testb $0x20, %al" + NL
boot_asm = boot_asm + "    jz .Lwait_serial" + NL
boot_asm = boot_asm + "    movzbl (%rsi), %eax" + NL
boot_asm = boot_asm + "    movw $0x3F8, %dx" + NL
boot_asm = boot_asm + "    outb %al, %dx" + NL
boot_asm = boot_asm + "    incq %rsi" + NL
boot_asm = boot_asm + "    jmp .Lprint_loop" + NL
boot_asm = boot_asm + ".Lhalt:" + NL
boot_asm = boot_asm + "    cli" + NL
boot_asm = boot_asm + "    hlt" + NL
boot_asm = boot_asm + "    jmp .Lhalt" + NL
boot_asm = boot_asm + NL
boot_asm = boot_asm + ".section .rodata" + NL
boot_asm = boot_asm + "boot_msg:" + NL
boot_asm = boot_asm + "    .asciz \"SageOS Bootloader OK\\r\\n\"" + NL

# ---- Generate linker script ----
let cfg = linker.default_config()
cfg["entry"] = "_start"
cfg["base_address"] = 1048576
let ld_script = linker.generate_script(cfg)

# ---- Write files ----
io.writefile(OUT + "/boot.s", boot_asm)
io.writefile(OUT + "/kernel.ld", ld_script)
print "  Written: " + OUT + "/boot.s"
print "  Written: " + OUT + "/kernel.ld"

# ---- Compile ----
print "Compiling..."
let r1 = sys.exec("mkdir -p " + OUT)
let r2 = sys.exec("as --64 -o " + OUT + "/boot.o " + OUT + "/boot.s 2>&1 && echo 'AS OK' || echo 'AS FAILED'")
let r3 = sys.exec("ld -T " + OUT + "/kernel.ld -o " + OUT + "/bootloader.elf " + OUT + "/boot.o 2>&1 && echo 'LD OK' || echo 'LD FAILED'")

if r2 == 0 and r3 == 0:
    print "  Compiled: " + OUT + "/bootloader.elf"
    print ""
    print "=== Run with QEMU ==="
    let vm = qemu.create_vm("sageos-bootloader")
    vm = qemu.vm_set_arch(vm, qemu.ARCH_X86_64)
    vm = qemu.vm_set_machine(vm, qemu.MACH_Q35)
    vm = qemu.vm_set_memory(vm, "32M")
    vm = qemu.vm_set_display(vm, qemu.DISPLAY_NONE)
    vm = qemu.vm_set_serial(vm, qemu.SERIAL_STDIO)
    vm = qemu.vm_boot_kernel(vm, OUT + "/bootloader.elf", "")
    vm["no_reboot"] = true
    let cmd = qemu.vm_build_command(vm)
    print cmd
    print ""
    print "Expected output: SageOS Bootloader OK"
else:
    print "Compilation failed. Check that 'as' and 'ld' are installed."
end
