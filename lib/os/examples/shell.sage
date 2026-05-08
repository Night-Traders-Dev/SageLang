gc_disable()
# =============================================================================
# SageOS Example 3: Standalone Interactive Shell Kernel
# =============================================================================
# Generates a kernel with a full interactive serial shell that:
#   - Boots via Multiboot1 (-kernel flag)
#   - Reads commands from COM1 serial (stdin in QEMU)
#   - Supports: help, echo, mem, regs, clear, uptime, halt
#   - Demonstrates interrupt-driven input via polling
#
# Usage:
#   sage lib/os/examples/shell.sage
#   # Then run the printed QEMU command (use -serial stdio for interactive I/O)
# =============================================================================

import sys
import io
import os.qemu as qemu

let NL = chr(10)
let OUT = "/tmp/sageos_shell"

print "=== SageOS Standalone Shell Kernel ==="
print "Generating shell kernel source..."

# ---- Boot stub (same Multiboot1 pattern) ----
let boot_asm = ""
boot_asm = boot_asm + ".set MB_MAGIC,    0x1BADB002" + NL
boot_asm = boot_asm + ".set MB_FLAGS,    0x00000000" + NL
boot_asm = boot_asm + ".set MB_CHECKSUM, -(MB_MAGIC + MB_FLAGS)" + NL
boot_asm = boot_asm + ".section .multiboot" + NL
boot_asm = boot_asm + ".align 4" + NL
boot_asm = boot_asm + ".long MB_MAGIC" + NL
boot_asm = boot_asm + ".long MB_FLAGS" + NL
boot_asm = boot_asm + ".long MB_CHECKSUM" + NL
boot_asm = boot_asm + ".section .bss" + NL
boot_asm = boot_asm + ".align 16" + NL
boot_asm = boot_asm + "stack_bottom: .skip 32768" + NL
boot_asm = boot_asm + "stack_top:" + NL
boot_asm = boot_asm + ".section .text" + NL
boot_asm = boot_asm + ".global _start" + NL
boot_asm = boot_asm + "_start:" + NL
boot_asm = boot_asm + "    movl $stack_top, %esp" + NL
boot_asm = boot_asm + "    pushl $0" + NL
boot_asm = boot_asm + "    popf" + NL
boot_asm = boot_asm + "    pushl %ebx" + NL
boot_asm = boot_asm + "    pushl %eax" + NL
boot_asm = boot_asm + "    call shell_main" + NL
boot_asm = boot_asm + ".Lhalt: cli; hlt; jmp .Lhalt" + NL

# ---- Shell kernel C source ----
let shell_c = ""
shell_c = shell_c + "#include <stdint.h>" + NL
shell_c = shell_c + "#include <stddef.h>" + NL
shell_c = shell_c + NL
shell_c = shell_c + "#define COM1 0x3F8" + NL
shell_c = shell_c + "#define CMD_MAX 128" + NL
shell_c = shell_c + NL
shell_c = shell_c + "static inline void outb(uint16_t p, uint8_t v) {" + NL
shell_c = shell_c + "    __asm__ volatile(\"outb %0,%1\"::\"a\"(v),\"Nd\"(p)); }" + NL
shell_c = shell_c + "static inline uint8_t inb(uint16_t p) {" + NL
shell_c = shell_c + "    uint8_t r; __asm__ volatile(\"inb %1,%0\":\"=a\"(r):\"Nd\"(p)); return r; }" + NL
shell_c = shell_c + NL
shell_c = shell_c + "static void serial_init(void) {" + NL
shell_c = shell_c + "    outb(COM1+1,0); outb(COM1+3,0x80); outb(COM1+0,1);" + NL
shell_c = shell_c + "    outb(COM1+1,0); outb(COM1+3,3); outb(COM1+2,0xC7); outb(COM1+4,0xB);" + NL
shell_c = shell_c + "}" + NL
shell_c = shell_c + "static void putc(char c) {" + NL
shell_c = shell_c + "    while(!(inb(COM1+5)&0x20)); outb(COM1,(uint8_t)c); }" + NL
shell_c = shell_c + "static char getc(void) {" + NL
shell_c = shell_c + "    while(!(inb(COM1+5)&1)); return (char)inb(COM1); }" + NL
shell_c = shell_c + "static void puts(const char *s) {" + NL
shell_c = shell_c + "    while(*s){ if(*s=='\\n') putc('\\r'); putc(*s++); } }" + NL
shell_c = shell_c + "static void puthex32(uint32_t n) {" + NL
shell_c = shell_c + "    const char *h=\"0123456789ABCDEF\"; puts(\"0x\");" + NL
shell_c = shell_c + "    for(int i=28;i>=0;i-=4) putc(h[(n>>i)&0xF]); }" + NL
shell_c = shell_c + "static void putdec(uint32_t n) {" + NL
shell_c = shell_c + "    if(n==0){putc('0');return;}" + NL
shell_c = shell_c + "    char buf[12]; int i=0;" + NL
shell_c = shell_c + "    while(n){buf[i++]='0'+n%10;n/=10;}" + NL
shell_c = shell_c + "    for(int j=i-1;j>=0;j--) putc(buf[j]); }" + NL
shell_c = shell_c + NL
shell_c = shell_c + "static int streq(const char *a, const char *b) {" + NL
shell_c = shell_c + "    while(*a && *b && *a==*b){a++;b++;}" + NL
shell_c = shell_c + "    return *a==*b; }" + NL
shell_c = shell_c + "static int startswith(const char *s, const char *p) {" + NL
shell_c = shell_c + "    while(*p) if(*s++!=*p++) return 0; return 1; }" + NL
shell_c = shell_c + NL
shell_c = shell_c + "static uint32_t tick = 0;" + NL
shell_c = shell_c + NL
shell_c = shell_c + "static void cmd_help(void) {" + NL
shell_c = shell_c + "    puts(\"Commands:\\n\");" + NL
shell_c = shell_c + "    puts(\"  help          - Show this help\\n\");" + NL
shell_c = shell_c + "    puts(\"  echo <text>   - Print text\\n\");" + NL
shell_c = shell_c + "    puts(\"  mem           - Show memory info\\n\");" + NL
shell_c = shell_c + "    puts(\"  regs          - Show CPU register snapshot\\n\");" + NL
shell_c = shell_c + "    puts(\"  uptime        - Show tick counter\\n\");" + NL
shell_c = shell_c + "    puts(\"  clear         - Clear screen (serial)\\n\");" + NL
shell_c = shell_c + "    puts(\"  halt          - Halt the system\\n\");" + NL
shell_c = shell_c + "}" + NL
shell_c = shell_c + NL
shell_c = shell_c + "static void cmd_mem(uint32_t mem_lower, uint32_t mem_upper) {" + NL
shell_c = shell_c + "    puts(\"Memory map:\\n\");" + NL
shell_c = shell_c + "    puts(\"  Lower: \"); putdec(mem_lower); puts(\" KB\\n\");" + NL
shell_c = shell_c + "    puts(\"  Upper: \"); putdec(mem_upper); puts(\" KB (\");" + NL
shell_c = shell_c + "    putdec(mem_upper/1024); puts(\" MB)\\n\");" + NL
shell_c = shell_c + "    puts(\"  Total: \"); putdec((mem_lower+mem_upper)/1024); puts(\" MB\\n\");" + NL
shell_c = shell_c + "}" + NL
shell_c = shell_c + NL
shell_c = shell_c + "static void cmd_regs(void) {" + NL
shell_c = shell_c + "    uint32_t eax,ebx,ecx,edx,esp,ebp;" + NL
shell_c = shell_c + "    __asm__ volatile(\"mov %%eax,%0\":\"=r\"(eax));" + NL
shell_c = shell_c + "    __asm__ volatile(\"mov %%ebx,%0\":\"=r\"(ebx));" + NL
shell_c = shell_c + "    __asm__ volatile(\"mov %%ecx,%0\":\"=r\"(ecx));" + NL
shell_c = shell_c + "    __asm__ volatile(\"mov %%edx,%0\":\"=r\"(edx));" + NL
shell_c = shell_c + "    __asm__ volatile(\"mov %%esp,%0\":\"=r\"(esp));" + NL
shell_c = shell_c + "    __asm__ volatile(\"mov %%ebp,%0\":\"=r\"(ebp));" + NL
shell_c = shell_c + "    puts(\"Registers:\\n\");" + NL
shell_c = shell_c + "    puts(\"  EAX=\"); puthex32(eax); puts(\"  EBX=\"); puthex32(ebx); puts(\"\\n\");" + NL
shell_c = shell_c + "    puts(\"  ECX=\"); puthex32(ecx); puts(\"  EDX=\"); puthex32(edx); puts(\"\\n\");" + NL
shell_c = shell_c + "    puts(\"  ESP=\"); puthex32(esp); puts(\"  EBP=\"); puthex32(ebp); puts(\"\\n\");" + NL
shell_c = shell_c + "}" + NL
shell_c = shell_c + NL
shell_c = shell_c + "typedef struct { uint32_t flags,mem_lower,mem_upper; } mb_info_t;" + NL
shell_c = shell_c + "#define MB_MAGIC 0x2BADB002" + NL
shell_c = shell_c + NL
shell_c = shell_c + "void shell_main(uint32_t magic, mb_info_t *mbi) {" + NL
shell_c = shell_c + "    serial_init();" + NL
shell_c = shell_c + "    uint32_t mem_lower = 640, mem_upper = 32768;" + NL
shell_c = shell_c + "    if (magic == MB_MAGIC && mbi && (mbi->flags & 1)) {" + NL
shell_c = shell_c + "        mem_lower = mbi->mem_lower;" + NL
shell_c = shell_c + "        mem_upper = mbi->mem_upper;" + NL
shell_c = shell_c + "    }" + NL
shell_c = shell_c + "    puts(\"\\033[2J\\033[H\");" + NL
shell_c = shell_c + "    puts(\"========================================\\n\");" + NL
shell_c = shell_c + "    puts(\"  SageOS Shell v0.1.0\\n\");" + NL
shell_c = shell_c + "    puts(\"  Type 'help' for commands\\n\");" + NL
shell_c = shell_c + "    puts(\"========================================\\n\\n\");" + NL
shell_c = shell_c + "    char cmd[CMD_MAX];" + NL
shell_c = shell_c + "    while (1) {" + NL
shell_c = shell_c + "        puts(\"sage@os:~$ \");" + NL
shell_c = shell_c + "        int len = 0;" + NL
shell_c = shell_c + "        while (1) {" + NL
shell_c = shell_c + "            char c = getc();" + NL
shell_c = shell_c + "            if (c == '\\r' || c == '\\n') { puts(\"\\n\"); break; }" + NL
shell_c = shell_c + "            if (c == 127 || c == 8) {" + NL
shell_c = shell_c + "                if (len > 0) { len--; puts(\"\\b \\b\"); }" + NL
shell_c = shell_c + "                continue;" + NL
shell_c = shell_c + "            }" + NL
shell_c = shell_c + "            if (len < CMD_MAX-1) { cmd[len++] = c; putc(c); }" + NL
shell_c = shell_c + "        }" + NL
shell_c = shell_c + "        cmd[len] = 0;" + NL
shell_c = shell_c + "        tick++;" + NL
shell_c = shell_c + "        if (len == 0) continue;" + NL
shell_c = shell_c + "        if (streq(cmd,\"help\")) { cmd_help(); }" + NL
shell_c = shell_c + "        else if (streq(cmd,\"mem\")) { cmd_mem(mem_lower, mem_upper); }" + NL
shell_c = shell_c + "        else if (streq(cmd,\"regs\")) { cmd_regs(); }" + NL
shell_c = shell_c + "        else if (streq(cmd,\"uptime\")) {" + NL
shell_c = shell_c + "            puts(\"Commands executed: \"); putdec(tick); puts(\"\\n\"); }" + NL
shell_c = shell_c + "        else if (streq(cmd,\"clear\")) { puts(\"\\033[2J\\033[H\"); }" + NL
shell_c = shell_c + "        else if (streq(cmd,\"halt\")) {" + NL
shell_c = shell_c + "            puts(\"Halting...\\n\");" + NL
shell_c = shell_c + "            __asm__ volatile(\"cli; hlt\"); }" + NL
shell_c = shell_c + "        else if (startswith(cmd,\"echo \")) { puts(cmd+5); puts(\"\\n\"); }" + NL
shell_c = shell_c + "        else { puts(\"Unknown command: \"); puts(cmd); puts(\"\\n\"); }" + NL
shell_c = shell_c + "    }" + NL
shell_c = shell_c + "}" + NL

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
io.writefile(OUT + "/shell.c", shell_c)
io.writefile(OUT + "/kernel.ld", ld_script)
print "  Written: " + OUT + "/boot.s"
print "  Written: " + OUT + "/shell.c"
print "  Written: " + OUT + "/kernel.ld"

print "Compiling..."
let r1 = sys.exec("as --32 -o " + OUT + "/boot.o " + OUT + "/boot.s 2>&1")
let r2 = sys.exec("gcc -m32 -ffreestanding -fno-stack-protector -nostdlib -c -o " + OUT + "/shell.o " + OUT + "/shell.c 2>&1")
let r3 = sys.exec("ld -m elf_i386 -T " + OUT + "/kernel.ld -o " + OUT + "/shell.elf " + OUT + "/boot.o " + OUT + "/shell.o 2>&1")

if r1 == 0 and r2 == 0 and r3 == 0:
    print "  Compiled: " + OUT + "/shell.elf"
    print ""
    print "=== Run with QEMU (interactive) ==="
    let vm = qemu.create_vm("sageos-shell")
    vm = qemu.vm_set_arch(vm, qemu.ARCH_X86_64)
    vm = qemu.vm_set_machine(vm, qemu.MACH_Q35)
    vm = qemu.vm_set_memory(vm, "32M")
    vm = qemu.vm_set_display(vm, qemu.DISPLAY_NONE)
    vm = qemu.vm_set_serial(vm, qemu.SERIAL_STDIO)
    vm = qemu.vm_boot_kernel(vm, OUT + "/shell.elf", "")
    vm["no_reboot"] = true
    let cmd = qemu.vm_build_command(vm)
    print cmd
    print ""
    print "Interactive shell: type 'help' for commands, 'halt' to exit"
else:
    print "Compilation failed (exit codes: " + str(r1) + " " + str(r2) + " " + str(r3) + ")"
    print "Ensure gcc-multilib is installed: sudo apt install gcc-multilib"
end
