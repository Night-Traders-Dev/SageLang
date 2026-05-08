gc_disable()
# =============================================================================
# SageOS Example 2: Standalone Kernel
# =============================================================================
# Generates a minimal x86_64 kernel in C that:
#   - Is loaded by GRUB/QEMU via Multiboot1 (-kernel flag)
#   - Initializes COM1 serial at 115200 baud
#   - Prints system info (memory, CPU) via serial
#   - Runs a simple computation loop to prove execution
#   - Halts cleanly
#
# Usage:
#   sage lib/os/examples/kernel.sage
#   # Then run the printed QEMU command
# =============================================================================

import sys
import io
import os.qemu as qemu

let NL = chr(10)
let OUT = "/tmp/sageos_kernel"

print "=== SageOS Standalone Kernel ==="
print "Generating kernel source..."

# ---- Multiboot1 header + entry stub (assembly) ----
let boot_asm = ""
boot_asm = boot_asm + "# SageOS kernel entry stub (Multiboot1)" + NL
boot_asm = boot_asm + ".set MULTIBOOT_MAGIC,    0x1BADB002" + NL
boot_asm = boot_asm + ".set MULTIBOOT_FLAGS,    0x00000000" + NL
boot_asm = boot_asm + ".set MULTIBOOT_CHECKSUM, -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)" + NL
boot_asm = boot_asm + NL
boot_asm = boot_asm + ".section .multiboot" + NL
boot_asm = boot_asm + ".align 4" + NL
boot_asm = boot_asm + ".long MULTIBOOT_MAGIC" + NL
boot_asm = boot_asm + ".long MULTIBOOT_FLAGS" + NL
boot_asm = boot_asm + ".long MULTIBOOT_CHECKSUM" + NL
boot_asm = boot_asm + NL
boot_asm = boot_asm + ".section .bss" + NL
boot_asm = boot_asm + ".align 16" + NL
boot_asm = boot_asm + "stack_bottom:" + NL
boot_asm = boot_asm + ".skip 16384" + NL
boot_asm = boot_asm + "stack_top:" + NL
boot_asm = boot_asm + NL
boot_asm = boot_asm + ".section .text" + NL
boot_asm = boot_asm + ".global _start" + NL
boot_asm = boot_asm + "_start:" + NL
boot_asm = boot_asm + "    movl $stack_top, %esp" + NL
boot_asm = boot_asm + "    pushl $0" + NL
boot_asm = boot_asm + "    popf" + NL
boot_asm = boot_asm + "    pushl %ebx" + NL
boot_asm = boot_asm + "    pushl %eax" + NL
boot_asm = boot_asm + "    call kernel_main" + NL
boot_asm = boot_asm + ".Lhalt:" + NL
boot_asm = boot_asm + "    cli" + NL
boot_asm = boot_asm + "    hlt" + NL
boot_asm = boot_asm + "    jmp .Lhalt" + NL

# ---- Kernel C source ----
let kernel_c = ""
kernel_c = kernel_c + "#include <stdint.h>" + NL
kernel_c = kernel_c + "#include <stddef.h>" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "/* COM1 serial port I/O */" + NL
kernel_c = kernel_c + "#define COM1 0x3F8" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "static inline void outb(uint16_t port, uint8_t val) {" + NL
kernel_c = kernel_c + "    __asm__ volatile (\"outb %0, %1\" : : \"a\"(val), \"Nd\"(port));" + NL
kernel_c = kernel_c + "}" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "static inline uint8_t inb(uint16_t port) {" + NL
kernel_c = kernel_c + "    uint8_t ret;" + NL
kernel_c = kernel_c + "    __asm__ volatile (\"inb %1, %0\" : \"=a\"(ret) : \"Nd\"(port));" + NL
kernel_c = kernel_c + "    return ret;" + NL
kernel_c = kernel_c + "}" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "static void serial_init(void) {" + NL
kernel_c = kernel_c + "    outb(COM1 + 1, 0x00);" + NL
kernel_c = kernel_c + "    outb(COM1 + 3, 0x80);" + NL
kernel_c = kernel_c + "    outb(COM1 + 0, 0x01);" + NL
kernel_c = kernel_c + "    outb(COM1 + 1, 0x00);" + NL
kernel_c = kernel_c + "    outb(COM1 + 3, 0x03);" + NL
kernel_c = kernel_c + "    outb(COM1 + 2, 0xC7);" + NL
kernel_c = kernel_c + "    outb(COM1 + 4, 0x0B);" + NL
kernel_c = kernel_c + "}" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "static void serial_putc(char c) {" + NL
kernel_c = kernel_c + "    while (!(inb(COM1 + 5) & 0x20));" + NL
kernel_c = kernel_c + "    outb(COM1, (uint8_t)c);" + NL
kernel_c = kernel_c + "}" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "static void serial_puts(const char *s) {" + NL
kernel_c = kernel_c + "    while (*s) {" + NL
kernel_c = kernel_c + "        if (*s == '\\n') serial_putc('\\r');" + NL
kernel_c = kernel_c + "        serial_putc(*s++);" + NL
kernel_c = kernel_c + "    }" + NL
kernel_c = kernel_c + "}" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "static void serial_puthex(uint32_t n) {" + NL
kernel_c = kernel_c + "    const char *hex = \"0123456789ABCDEF\";" + NL
kernel_c = kernel_c + "    serial_puts(\"0x\");" + NL
kernel_c = kernel_c + "    for (int i = 28; i >= 0; i -= 4)" + NL
kernel_c = kernel_c + "        serial_putc(hex[(n >> i) & 0xF]);" + NL
kernel_c = kernel_c + "}" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "/* Multiboot info structure (partial) */" + NL
kernel_c = kernel_c + "typedef struct {" + NL
kernel_c = kernel_c + "    uint32_t flags;" + NL
kernel_c = kernel_c + "    uint32_t mem_lower;" + NL
kernel_c = kernel_c + "    uint32_t mem_upper;" + NL
kernel_c = kernel_c + "} __attribute__((packed)) multiboot_info_t;" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "#define MULTIBOOT_MAGIC 0x2BADB002" + NL
kernel_c = kernel_c + NL
kernel_c = kernel_c + "void kernel_main(uint32_t magic, multiboot_info_t *mbi) {" + NL
kernel_c = kernel_c + "    serial_init();" + NL
kernel_c = kernel_c + "    serial_puts(\"\\n\");" + NL
kernel_c = kernel_c + "    serial_puts(\"========================================\\n\");" + NL
kernel_c = kernel_c + "    serial_puts(\"  SageOS Kernel v0.1.0\\n\");" + NL
kernel_c = kernel_c + "    serial_puts(\"  Built with Sage Programming Language\\n\");" + NL
kernel_c = kernel_c + "    serial_puts(\"========================================\\n\");" + NL
kernel_c = kernel_c + "    serial_puts(\"\\n\");" + NL
kernel_c = kernel_c + "    if (magic == MULTIBOOT_MAGIC) {" + NL
kernel_c = kernel_c + "        serial_puts(\"[OK] Multiboot magic verified\\n\");" + NL
kernel_c = kernel_c + "        if (mbi && (mbi->flags & 1)) {" + NL
kernel_c = kernel_c + "            serial_puts(\"[OK] Memory: lower=\");" + NL
kernel_c = kernel_c + "            serial_puthex(mbi->mem_lower);" + NL
kernel_c = kernel_c + "            serial_puts(\"KB upper=\");" + NL
kernel_c = kernel_c + "            serial_puthex(mbi->mem_upper);" + NL
kernel_c = kernel_c + "            serial_puts(\"KB\\n\");" + NL
kernel_c = kernel_c + "        }" + NL
kernel_c = kernel_c + "    } else {" + NL
kernel_c = kernel_c + "        serial_puts(\"[WARN] Not loaded by Multiboot\\n\");" + NL
kernel_c = kernel_c + "    }" + NL
kernel_c = kernel_c + "    /* Prove execution: compute sum 1..100 */" + NL
kernel_c = kernel_c + "    uint32_t sum = 0;" + NL
kernel_c = kernel_c + "    for (uint32_t i = 1; i <= 100; i++) sum += i;" + NL
kernel_c = kernel_c + "    serial_puts(\"[OK] sum(1..100) = \");" + NL
kernel_c = kernel_c + "    serial_puthex(sum);" + NL
kernel_c = kernel_c + "    serial_puts(\" (expected 0x13BA = 5050)\\n\");" + NL
kernel_c = kernel_c + "    serial_puts(\"\\n[OK] Kernel halting cleanly.\\n\");" + NL
kernel_c = kernel_c + "}" + NL

# ---- Linker script ----
let ld_script = "ENTRY(_start)" + NL
ld_script = ld_script + "OUTPUT_FORMAT(\"elf32-i386\")" + NL
ld_script = ld_script + "SECTIONS {" + NL
ld_script = ld_script + "    . = 1048576;" + NL
ld_script = ld_script + "    .multiboot ALIGN(4) : { *(.multiboot) }" + NL
ld_script = ld_script + "    .text ALIGN(16) : { *(.text .text.*) }" + NL
ld_script = ld_script + "    .rodata ALIGN(16) : { *(.rodata .rodata.*) }" + NL
ld_script = ld_script + "    .data ALIGN(16) : { *(.data .data.*) }" + NL
ld_script = ld_script + "    .bss ALIGN(16) : {" + NL
ld_script = ld_script + "        __bss_start = .;" + NL
ld_script = ld_script + "        *(.bss .bss.*) *(COMMON)" + NL
ld_script = ld_script + "        __bss_end = .;" + NL
ld_script = ld_script + "    }" + NL
ld_script = ld_script + "}" + NL

# ---- Write and compile ----
sys.exec("mkdir -p " + OUT)
io.writefile(OUT + "/boot.s", boot_asm)
io.writefile(OUT + "/kernel.c", kernel_c)
io.writefile(OUT + "/kernel.ld", ld_script)
print "  Written: " + OUT + "/boot.s"
print "  Written: " + OUT + "/kernel.c"
print "  Written: " + OUT + "/kernel.ld"

print "Compiling..."
let r1 = sys.exec("as --32 -o " + OUT + "/boot.o " + OUT + "/boot.s 2>&1")
let r2 = sys.exec("gcc -m32 -ffreestanding -fno-stack-protector -nostdlib -c -o " + OUT + "/kernel.o " + OUT + "/kernel.c 2>&1")
let r3 = sys.exec("ld -m elf_i386 -T " + OUT + "/kernel.ld -o " + OUT + "/kernel.elf " + OUT + "/boot.o " + OUT + "/kernel.o 2>&1")

if r1 == 0 and r2 == 0 and r3 == 0:
    print "  Compiled: " + OUT + "/kernel.elf"
    print ""
    print "=== Run with QEMU ==="
    let vm = qemu.create_vm("sageos-kernel")
    vm = qemu.vm_set_arch(vm, qemu.ARCH_X86_64)
    vm = qemu.vm_set_machine(vm, qemu.MACH_Q35)
    vm = qemu.vm_set_memory(vm, "32M")
    vm = qemu.vm_set_display(vm, qemu.DISPLAY_NONE)
    vm = qemu.vm_set_serial(vm, qemu.SERIAL_STDIO)
    vm = qemu.vm_boot_kernel(vm, OUT + "/kernel.elf", "")
    vm["no_reboot"] = true
    let cmd = qemu.vm_build_command(vm)
    print cmd
    print ""
    print "Expected output: SageOS Kernel v0.1.0 + memory info + sum(1..100)=0x13BA (5050)"
else:
    print "Compilation failed (exit codes: " + str(r1) + " " + str(r2) + " " + str(r3) + ")"
    print "Ensure gcc-multilib is installed: sudo apt install gcc-multilib"
end
