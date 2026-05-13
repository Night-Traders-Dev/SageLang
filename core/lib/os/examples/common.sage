gc_disable()
# =============================================================================
# common.sage — Multi-Architecture Kernel Builder for SageOS Examples
# =============================================================================
# Shared infrastructure for building bare-metal kernels for x86_64, aarch64,
# and riscv64. Each example imports this module and calls build_kernel().
#
# Usage:
#   import os.examples.common as common
#   let result = common.build_kernel("aarch64", "/tmp/mykernel", features)
#   common.run_commands(result["commands"])
#   print common.qemu_cmd("aarch64", result["elf"])
#
# Supported architectures: x86_64, aarch64, riscv64
# =============================================================================

import sys
import io
import os.qemu as qemu
import os.boot.start as start
import os.boot.linker as linker

let NL = chr(10)
let TAB = chr(9)

# ============================================================================
# Toolchain paths
# ============================================================================

proc get_as(arch):
    if arch == "x86_64":
        return "as"
    end
    if arch == "aarch64":
        return "aarch64-linux-gnu-as"
    end
    if arch == "riscv64":
        return "riscv64-unknown-elf-as"
    end
    return "as"
end

proc get_cc(arch):
    if arch == "x86_64":
        return "gcc"
    end
    if arch == "aarch64":
        return "aarch64-linux-gnu-gcc"
    end
    if arch == "riscv64":
        return "riscv64-unknown-elf-gcc"
    end
    return "gcc"
end

proc get_ld(arch):
    if arch == "x86_64":
        return "ld"
    end
    if arch == "aarch64":
        return "aarch64-linux-gnu-ld"
    end
    if arch == "riscv64":
        return "riscv64-unknown-elf-ld"
    end
    return "ld"
end

# ============================================================================
# Boot assembly generation
# ============================================================================

# x86_64: 32-bit multiboot1 ELF for QEMU -kernel direct loading
proc _gen_boot_x86_64(entry):
    let asm = ""
    asm = asm + "# x86_64 boot stub — Multiboot1 + 32-bit entry" + NL
    asm = asm + ".set MB_MAGIC,    0x1BADB002" + NL
    asm = asm + ".set MB_FLAGS,    0x00000000" + NL
    asm = asm + ".set MB_CHECKSUM, -(MB_MAGIC + MB_FLAGS)" + NL
    asm = asm + NL
    asm = asm + ".section .multiboot" + NL
    asm = asm + ".align 4" + NL
    asm = asm + ".long MB_MAGIC" + NL
    asm = asm + ".long MB_FLAGS" + NL
    asm = asm + ".long MB_CHECKSUM" + NL
    asm = asm + NL
    asm = asm + ".section .bss" + NL
    asm = asm + ".align 16" + NL
    asm = asm + "stack_bottom: .skip 65536" + NL
    asm = asm + "stack_top:" + NL
    asm = asm + NL
    asm = asm + ".section .text" + NL
    asm = asm + ".global _start" + NL
    asm = asm + "_start:" + NL
    asm = asm + "    movl $stack_top, %esp" + NL
    asm = asm + "    pushl $0" + NL
    asm = asm + "    popf" + NL
    asm = asm + "    # Clear BSS" + NL
    asm = asm + "    movl $__bss_start, %edi" + NL
    asm = asm + "    movl $__bss_end, %ecx" + NL
    asm = asm + "    subl %edi, %ecx" + NL
    asm = asm + "    shrl $2, %ecx" + NL
    asm = asm + "    xorl %eax, %eax" + NL
    asm = asm + "    rep stosl" + NL
    asm = asm + "    call " + entry + NL
    asm = asm + ".Lhalt:" + NL
    asm = asm + "    cli" + NL
    asm = asm + "    hlt" + NL
    asm = asm + "    jmp .Lhalt" + NL
    return asm
end

# aarch64: bare-metal entry for QEMU virt machine
proc _gen_boot_aarch64(entry):
    let asm = ""
    asm = asm + "# aarch64 boot stub — QEMU virt" + NL
    asm = asm + ".section .text" + NL
    asm = asm + ".global _start" + NL
    asm = asm + "_start:" + NL
    asm = asm + "    # Disable interrupts (DAIF)" + NL
    asm = asm + "    msr daifset, #0xf" + NL
    asm = asm + "    # Set stack pointer" + NL
    asm = asm + "    ldr x0, =stack_top" + NL
    asm = asm + "    mov sp, x0" + NL
    asm = asm + "    # Zero BSS" + NL
    asm = asm + "    ldr x1, =__bss_start" + NL
    asm = asm + "    ldr x2, =__bss_end" + NL
    asm = asm + ".Lbss_zero:" + NL
    asm = asm + "    cmp x1, x2" + NL
    asm = asm + "    b.ge .Lbss_done" + NL
    asm = asm + "    stp xzr, xzr, [x1], #16" + NL
    asm = asm + "    b .Lbss_zero" + NL
    asm = asm + ".Lbss_done:" + NL
    asm = asm + "    bl " + entry + NL
    asm = asm + ".Lhalt:" + NL
    asm = asm + "    wfe" + NL
    asm = asm + "    b .Lhalt" + NL
    asm = asm + NL
    asm = asm + ".section .bss" + NL
    asm = asm + ".align 16" + NL
    asm = asm + "stack_bottom: .skip 65536" + NL
    asm = asm + "stack_top:" + NL
    return asm
end

# riscv64: bare-metal entry for QEMU virt machine
proc _gen_boot_riscv64(entry):
    let asm = ""
    asm = asm + "# riscv64 boot stub — QEMU virt" + NL
    asm = asm + ".section .text" + NL
    asm = asm + ".global _start" + NL
    asm = asm + "_start:" + NL
    asm = asm + "    # Disable machine interrupts" + NL
    asm = asm + "    csrci mstatus, 0x8" + NL
    asm = asm + "    # Set stack pointer" + NL
    asm = asm + "    la sp, stack_top" + NL
    asm = asm + "    # Zero BSS" + NL
    asm = asm + "    la t0, __bss_start" + NL
    asm = asm + "    la t1, __bss_end" + NL
    asm = asm + ".Lbss_zero:" + NL
    asm = asm + "    bge t0, t1, .Lbss_done" + NL
    asm = asm + "    sd zero, 0(t0)" + NL
    asm = asm + "    addi t0, t0, 8" + NL
    asm = asm + "    j .Lbss_zero" + NL
    asm = asm + ".Lbss_done:" + NL
    asm = asm + "    call " + entry + NL
    asm = asm + ".Lhalt:" + NL
    asm = asm + "    wfi" + NL
    asm = asm + "    j .Lhalt" + NL
    asm = asm + NL
    asm = asm + ".section .bss" + NL
    asm = asm + ".align 16" + NL
    asm = asm + "stack_bottom: .skip 65536" + NL
    asm = asm + "stack_top:" + NL
    return asm
end

proc gen_boot_asm(arch, entry):
    if arch == "x86_64":
        return _gen_boot_x86_64(entry)
    end
    if arch == "aarch64":
        return _gen_boot_aarch64(entry)
    end
    if arch == "riscv64":
        return _gen_boot_riscv64(entry)
    end
    return ""
end

# ============================================================================
# Kernel C code generation
# ============================================================================

# x86_64: COM1 serial (port I/O), VGA text mode optional
proc _gen_kernel_c_x86_64(features):
    let c = ""
    c = c + "/* SageOS kernel — x86_64 */" + NL
    c = c + "#include <stdint.h>" + NL
    c = c + "#include <stddef.h>" + NL
    c = c + NL
    c = c + "/* ===== Serial (COM1 @ 0x3F8) ===== */" + NL
    c = c + "#define COM1 0x3F8" + NL
    c = c + "static inline void outb(uint16_t p, uint8_t v) {" + NL
    c = c + "    __asm__ volatile(\"outb %0,%1\"::\"a\"(v),\"Nd\"(p)); }" + NL
    c = c + "static inline uint8_t inb(uint16_t p) {" + NL
    c = c + "    uint8_t r; __asm__ volatile(\"inb %1,%0\":\"=a\"(r):\"Nd\"(p)); return r; }" + NL
    c = c + "void serial_init(void) {" + NL
    c = c + "    outb(COM1+1,0); outb(COM1+3,0x80); outb(COM1+0,1); outb(COM1+1,0);" + NL
    c = c + "    outb(COM1+3,3); outb(COM1+2,0xC7); outb(COM1+4,0xB); }" + NL
    c = c + "void serial_putc(char c) {" + NL
    c = c + "    while(!(inb(COM1+5)&0x20)); outb(COM1,(uint8_t)c); }" + NL
    c = c + "char serial_getc(void) {" + NL
    c = c + "    while(!(inb(COM1+5)&1)); return (char)inb(COM1); }" + NL
    c = c + "void serial_puts(const char *s) {" + NL
    c = c + "    while(*s){ if(*s=='\\n') serial_putc('\\r'); serial_putc(*s++); } }" + NL
    c = c + "void serial_puthex(uint32_t n) {" + NL
    c = c + "    const char *h=\"0123456789ABCDEF\"; serial_puts(\"0x\");" + NL
    c = c + "    for(int i=28;i>=0;i-=4) serial_putc(h[(n>>i)&0xF]); }" + NL
    c = c + "void serial_putdec(uint32_t n) {" + NL
    c = c + "    if(n==0){serial_putc('0');return;}" + NL
    c = c + "    char b[12]; int i=0; while(n){b[i++]='0'+n%10;n/=10;}" + NL
    c = c + "    for(int j=i-1;j>=0;j--) serial_putc(b[j]); }" + NL
    c = c + NL

    if features["has_vga"]:
        c = c + "/* ===== VGA Text Mode (80x25) ===== */" + NL
        c = c + "#define VGA_BASE ((volatile uint16_t*)0xB8000)" + NL
        c = c + "#define VGA_W 80" + NL
        c = c + "#define VGA_H 25" + NL
        c = c + "static int vga_x=0, vga_y=0;" + NL
        c = c + "static uint8_t vga_color = 0x0F;" + NL
        c = c + "void vga_clear(void) {" + NL
        c = c + "    for(int i=0;i<VGA_W*VGA_H;i++) VGA_BASE[i]=(uint16_t)(vga_color<<8)|' ';" + NL
        c = c + "    vga_x=vga_y=0; }" + NL
        c = c + "void vga_scroll(void) {" + NL
        c = c + "    for(int y=1;y<VGA_H;y++)" + NL
        c = c + "        for(int x=0;x<VGA_W;x++) VGA_BASE[(y-1)*VGA_W+x]=VGA_BASE[y*VGA_W+x];" + NL
        c = c + "    for(int x=0;x<VGA_W;x++) VGA_BASE[(VGA_H-1)*VGA_W+x]=(uint16_t)(vga_color<<8)|' ';" + NL
        c = c + "    vga_y=VGA_H-1; }" + NL
        c = c + "void vga_putc(char c) {" + NL
        c = c + "    if(c=='\\n'){vga_x=0;vga_y++;} else if(c=='\\r'){vga_x=0;}" + NL
        c = c + "    else{VGA_BASE[vga_y*VGA_W+vga_x]=(uint16_t)(vga_color<<8)|(uint8_t)c;vga_x++;}" + NL
        c = c + "    if(vga_x>=VGA_W){vga_x=0;vga_y++;} if(vga_y>=VGA_H) vga_scroll(); }" + NL
        c = c + "void vga_puts(const char *s) { while(*s) vga_putc(*s++); }" + NL
        c = c + "void vga_set_color(uint8_t fg,uint8_t bg) { vga_color=(uint8_t)((bg<<4)|fg); }" + NL
        c = c + NL
    end

    c = c + "/* ===== String helpers ===== */" + NL
    c = c + "static int streq(const char *a,const char *b) {" + NL
    c = c + "    while(*a&&*b&&*a==*b){a++;b++;} return *a==*b; }" + NL
    c = c + "static int startswith(const char *s,const char *p) {" + NL
    c = c + "    while(*p) if(*s++!=*p++) return 0; return 1; }" + NL
    c = c + "static int _strlen(const char *s) { int n=0; while(*s++)n++; return n; }" + NL
    c = c + NL

    c = c + "/* ===== Memory info from Multiboot ===== */" + NL
    c = c + "typedef struct { uint32_t flags, mem_lower, mem_upper; } mb_t;" + NL
    c = c + "#define MB_MAGIC 0x2BADB002" + NL
    c = c + "static uint32_t mem_lower_kb=640, mem_upper_kb=32768;" + NL
    c = c + "void parse_multiboot(uint32_t magic, mb_t *mbi) {" + NL
    c = c + "    if (magic == MB_MAGIC && mbi && (mbi->flags & 1)) {" + NL
    c = c + "        mem_lower_kb = mbi->mem_lower; mem_upper_kb = mbi->mem_upper; } }" + NL
    c = c + NL

    if features["has_shell"]:
        c = c + "/* ===== Register dump ===== */" + NL
        c = c + "void dump_regs(void) {" + NL
        c = c + "    uint32_t eax,ebx,ecx,edx,esp,ebp,eflags;" + NL
        c = c + "    __asm__ volatile(\"mov %%eax,%0\":\"=r\"(eax));" + NL
        c = c + "    __asm__ volatile(\"mov %%ebx,%0\":\"=r\"(ebx));" + NL
        c = c + "    __asm__ volatile(\"mov %%ecx,%0\":\"=r\"(ecx));" + NL
        c = c + "    __asm__ volatile(\"mov %%edx,%0\":\"=r\"(edx));" + NL
        c = c + "    __asm__ volatile(\"mov %%esp,%0\":\"=r\"(esp));" + NL
        c = c + "    __asm__ volatile(\"mov %%ebp,%0\":\"=r\"(ebp));" + NL
        c = c + "    __asm__ volatile(\"pushfl; popl %0\":\"=r\"(eflags));" + NL
        c = c + "    serial_puts(\"Registers:\\n\");" + NL
        c = c + "    serial_puts(\"  EAX=\"); serial_puthex(eax); serial_puts(\" EBX=\"); serial_puthex(ebx); serial_puts(\"\\n\");" + NL
        c = c + "    serial_puts(\"  ECX=\"); serial_puthex(ecx); serial_puts(\" EDX=\"); serial_puthex(edx); serial_puts(\"\\n\");" + NL
        c = c + "    serial_puts(\"  ESP=\"); serial_puthex(esp); serial_puts(\" EBP=\"); serial_puthex(ebp); serial_puts(\"\\n\");" + NL
        c = c + "    serial_puts(\"  EFLAGS=\"); serial_puthex(eflags); serial_puts(\"\\n\"); }" + NL
        c = c + NL
    end
    return c
end

# aarch64: PL011 serial (MMIO)
proc _gen_kernel_c_aarch64(features):
    let c = ""
    c = c + "/* SageOS kernel — aarch64 */" + NL
    c = c + "#include <stdint.h>" + NL
    c = c + "#include <stddef.h>" + NL
    c = c + NL
    c = c + "/* ===== PL011 UART @ 0x09000000 ===== */" + NL
    c = c + "#define UART_BASE 0x09000000" + NL
    c = c + "#define UART_DR   (*((volatile uint32_t*)(UART_BASE + 0x00)))" + NL
    c = c + "#define UART_FR   (*((volatile uint32_t*)(UART_BASE + 0x18)))" + NL
    c = c + "#define UART_IBRD (*((volatile uint32_t*)(UART_BASE + 0x24)))" + NL
    c = c + "#define UART_FBRD (*((volatile uint32_t*)(UART_BASE + 0x28)))" + NL
    c = c + "#define UART_LCRH (*((volatile uint32_t*)(UART_BASE + 0x2C)))" + NL
    c = c + "#define UART_CR   (*((volatile uint32_t*)(UART_BASE + 0x30)))" + NL
    c = c + "void serial_init(void) {" + NL
    c = c + "    UART_CR = 0;" + NL
    c = c + "    UART_IBRD = 26;" + NL
    c = c + "    UART_FBRD = 3;" + NL
    c = c + "    UART_LCRH = 0x70;" + NL
    c = c + "    UART_CR = 0x301; }" + NL
    c = c + "void serial_putc(char c) {" + NL
    c = c + "    while (UART_FR & 0x20); UART_DR = (uint32_t)c; }" + NL
    c = c + "char serial_getc(void) {" + NL
    c = c + "    while (UART_FR & 0x10); return (char)UART_DR; }" + NL
    c = c + "void serial_puts(const char *s) {" + NL
    c = c + "    while (*s) { if (*s=='\\n') serial_putc('\\r'); serial_putc(*s++); } }" + NL
    c = c + "void serial_puthex(uint64_t n) {" + NL
    c = c + "    const char *h=\"0123456789ABCDEF\"; serial_puts(\"0x\");" + NL
    c = c + "    for (int i=60; i>=0; i-=4) serial_putc(h[(n>>i)&0xF]); }" + NL
    c = c + "void serial_putdec(uint64_t n) {" + NL
    c = c + "    if (n==0) { serial_putc('0'); return; }" + NL
    c = c + "    char b[24]; int i=0; while(n){b[i++]='0'+n%10;n/=10;}" + NL
    c = c + "    for(int j=i-1;j>=0;j--) serial_putc(b[j]); }" + NL
    c = c + NL
    c = c + "/* ===== String helpers ===== */" + NL
    c = c + "static int streq(const char *a,const char *b) {" + NL
    c = c + "    while(*a&&*b&&*a==*b){a++;b++;} return *a==*b; }" + NL
    c = c + "static int startswith(const char *s,const char *p) {" + NL
    c = c + "    while(*p) if(*s++!=*p++) return 0; return 1; }" + NL
    c = c + "static int _strlen(const char *s) { int n=0; while(*s++)n++; return n; }" + NL
    c = c + NL

    if features["has_shell"]:
        c = c + "/* ===== Register dump ===== */" + NL
        c = c + "void dump_regs(void) {" + NL
        c = c + "    uint64_t x0,x1,x2,x3,sp,el;" + NL
        c = c + "    __asm__ volatile(\"mov %0, x0\":\"=r\"(x0));" + NL
        c = c + "    __asm__ volatile(\"mov %0, x1\":\"=r\"(x1));" + NL
        c = c + "    __asm__ volatile(\"mov %0, x2\":\"=r\"(x2));" + NL
        c = c + "    __asm__ volatile(\"mov %0, x3\":\"=r\"(x3));" + NL
        c = c + "    __asm__ volatile(\"mov %0, sp\":\"=r\"(sp));" + NL
        c = c + "    __asm__ volatile(\"mrs %0, CurrentEL\":\"=r\"(el));" + NL
        c = c + "    serial_puts(\"Registers:\\n\");" + NL
        c = c + "    serial_puts(\"  X0 =\"); serial_puthex(x0); serial_puts(\" X1 =\"); serial_puthex(x1); serial_puts(\"\\n\");" + NL
        c = c + "    serial_puts(\"  X2 =\"); serial_puthex(x2); serial_puts(\" X3 =\"); serial_puthex(x3); serial_puts(\"\\n\");" + NL
        c = c + "    serial_puts(\"  SP =\"); serial_puthex(sp); serial_puts(\" EL =\"); serial_puthex(el>>2); serial_puts(\"\\n\"); }" + NL
        c = c + NL
    end
    return c
end

# riscv64: 16550 serial (MMIO)
proc _gen_kernel_c_riscv64(features):
    let c = ""
    c = c + "/* SageOS kernel — riscv64 */" + NL
    c = c + "#include <stdint.h>" + NL
    c = c + "#include <stddef.h>" + NL
    c = c + NL
    c = c + "/* ===== 16550 UART @ 0x10000000 ===== */" + NL
    c = c + "#define UART_BASE ((volatile uint8_t*)0x10000000ULL)" + NL
    c = c + "static inline uint8_t uart_read(int off) { return UART_BASE[off]; }" + NL
    c = c + "static inline void uart_write(int off, uint8_t v) { UART_BASE[off] = v; }" + NL
    c = c + "void serial_init(void) {" + NL
    c = c + "    uart_write(1, 0); uart_write(3, 0x80);" + NL
    c = c + "    uart_write(0, 1); uart_write(1, 0);" + NL
    c = c + "    uart_write(3, 3); uart_write(2, 0xC7); uart_write(4, 0xB); }" + NL
    c = c + "void serial_putc(char c) {" + NL
    c = c + "    while (!(uart_read(5) & 0x20)); uart_write(0, (uint8_t)c); }" + NL
    c = c + "char serial_getc(void) {" + NL
    c = c + "    while (!(uart_read(5) & 1)); return (char)uart_read(0); }" + NL
    c = c + "void serial_puts(const char *s) {" + NL
    c = c + "    while (*s) { if (*s=='\\n') serial_putc('\\r'); serial_putc(*s++); } }" + NL
    c = c + "void serial_puthex(uint64_t n) {" + NL
    c = c + "    const char *h=\"0123456789ABCDEF\"; serial_puts(\"0x\");" + NL
    c = c + "    for (int i=60; i>=0; i-=4) serial_putc(h[(n>>i)&0xF]); }" + NL
    c = c + "void serial_putdec(uint64_t n) {" + NL
    c = c + "    if (n==0) { serial_putc('0'); return; }" + NL
    c = c + "    char b[24]; int i=0; while(n){b[i++]='0'+n%10;n/=10;}" + NL
    c = c + "    for(int j=i-1;j>=0;j--) serial_putc(b[j]); }" + NL
    c = c + NL
    c = c + "/* ===== String helpers ===== */" + NL
    c = c + "static int streq(const char *a,const char *b) {" + NL
    c = c + "    while(*a&&*b&&*a==*b){a++;b++;} return *a==*b; }" + NL
    c = c + "static int startswith(const char *s,const char *p) {" + NL
    c = c + "    while(*p) if(*s++!=*p++) return 0; return 1; }" + NL
    c = c + "static int _strlen(const char *s) { int n=0; while(*s++)n++; return n; }" + NL
    c = c + NL

    if features["has_shell"]:
        c = c + "/* ===== Register dump ===== */" + NL
        c = c + "void dump_regs(void) {" + NL
        c = c + "    uint64_t a0,a1,a2,a3,sp,pc;" + NL
        c = c + "    __asm__ volatile(\"mv %0, a0\":\"=r\"(a0));" + NL
        c = c + "    __asm__ volatile(\"mv %0, a1\":\"=r\"(a1));" + NL
        c = c + "    __asm__ volatile(\"mv %0, a2\":\"=r\"(a2));" + NL
        c = c + "    __asm__ volatile(\"mv %0, a3\":\"=r\"(a3));" + NL
        c = c + "    __asm__ volatile(\"mv %0, sp\":\"=r\"(sp));" + NL
        c = c + "    __asm__ volatile(\"csrr %0, mstatus\":\"=r\"(pc));" + NL
        c = c + "    serial_puts(\"Registers:\\n\");" + NL
        c = c + "    serial_puts(\"  A0=\"); serial_puthex(a0); serial_puts(\" A1=\"); serial_puthex(a1); serial_puts(\"\\n\");" + NL
        c = c + "    serial_puts(\"  A2=\"); serial_puthex(a2); serial_puts(\" A3=\"); serial_puthex(a3); serial_puts(\"\\n\");" + NL
        c = c + "    serial_puts(\"  SP=\"); serial_puthex(sp); serial_puts(\" MSTATUS=\"); serial_puthex(pc); serial_puts(\"\\n\"); }" + NL
        c = c + NL
    end
    return c
end

proc gen_kernel_c(arch, features):
    if arch == "x86_64":
        return _gen_kernel_c_x86_64(features)
    end
    if arch == "aarch64":
        return _gen_kernel_c_aarch64(features)
    end
    if arch == "riscv64":
        return _gen_kernel_c_riscv64(features)
    end
    return ""
end

# ============================================================================
# Linker scripts
# ============================================================================

proc gen_linker_script(arch):
    let s = ""
    if arch == "x86_64":
        s = s + "ENTRY(_start)" + NL
        s = s + "OUTPUT_FORMAT(\"elf32-i386\")" + NL
        s = s + "SECTIONS {" + NL
        s = s + "    . = 1048576;" + NL
        s = s + "    .multiboot ALIGN(4) : { *(.multiboot) }" + NL
        s = s + "    .text ALIGN(16) : { *(.text .text.*) }" + NL
        s = s + "    .rodata ALIGN(16) : { *(.rodata .rodata.*) }" + NL
        s = s + "    .data ALIGN(16) : { *(.data .data.*) }" + NL
        s = s + "    .bss ALIGN(16) : {" + NL
        s = s + "        __bss_start = .;" + NL
        s = s + "        *(.bss .bss.*) *(COMMON)" + NL
        s = s + "        __bss_end = .;" + NL
        s = s + "    }" + NL
        s = s + "}" + NL
        return s
    end
    if arch == "aarch64":
        s = s + "OUTPUT_FORMAT(\"elf64-littleaarch64\")" + NL
        s = s + "ENTRY(_start)" + NL
        s = s + "SECTIONS {" + NL
        s = s + "    . = 0x40000000;" + NL
        s = s + "    .text ALIGN(4096) : { *(.text .text.*) }" + NL
        s = s + "    .rodata ALIGN(4096) : { *(.rodata .rodata.*) }" + NL
        s = s + "    .data ALIGN(4096) : { *(.data .data.*) }" + NL
        s = s + "    .bss ALIGN(4096) : {" + NL
        s = s + "        __bss_start = .;" + NL
        s = s + "        *(.bss .bss.*) *(COMMON)" + NL
        s = s + "        __bss_end = .;" + NL
        s = s + "    }" + NL
        s = s + "}" + NL
        return s
    end
    if arch == "riscv64":
        s = s + "OUTPUT_FORMAT(\"elf64-littleriscv\")" + NL
        s = s + "ENTRY(_start)" + NL
        s = s + "SECTIONS {" + NL
        s = s + "    . = 0x80000000;" + NL
        s = s + "    .text ALIGN(4096) : { *(.text .text.*) }" + NL
        s = s + "    .rodata ALIGN(4096) : { *(.rodata .rodata.*) }" + NL
        s = s + "    .data ALIGN(4096) : { *(.data .data.*) }" + NL
        s = s + "    .bss ALIGN(4096) : {" + NL
        s = s + "        __bss_start = .;" + NL
        s = s + "        *(.bss .bss.*) *(COMMON)" + NL
        s = s + "        __bss_end = .;" + NL
        s = s + "    }" + NL
        s = s + "}" + NL
        return s
    end
    return ""
end

# ============================================================================
# Build commands
# ============================================================================

proc build_commands(arch, out_dir, boot_asm, kernel_c, ld_script):
    let as_cmd = get_as(arch)
    let cc = get_cc(arch)
    let ld = get_ld(arch)
    let cmds = []
    let boot_o = out_dir + "/boot.o"
    let kernel_o = out_dir + "/kernel.o"
    let elf = out_dir + "/kernel.elf"

    # Assemble boot stub
    if arch == "x86_64":
        push(cmds, as_cmd + " --32 -o " + boot_o + " " + boot_asm)
    end
    if arch == "aarch64":
        push(cmds, as_cmd + " -o " + boot_o + " " + boot_asm)
    end
    if arch == "riscv64":
        push(cmds, as_cmd + " -march=rv64gc -mabi=lp64d -o " + boot_o + " " + boot_asm)
    end

    # Compile kernel C
    let cflags = " -ffreestanding -nostdlib -O2 -c"
    if arch == "x86_64":
        cflags = cflags + " -m32"
    end
    if arch == "riscv64":
        cflags = cflags + " -march=rv64gc -mabi=lp64d -mcmodel=medany"
    end
    push(cmds, cc + cflags + " -o " + kernel_o + " " + kernel_c)

    # Link
    if arch == "x86_64":
        push(cmds, ld + " -m elf_i386 -T " + ld_script + " -o " + elf + " " + boot_o + " " + kernel_o)
    end
    if arch == "aarch64":
        push(cmds, ld + " -T " + ld_script + " -o " + elf + " " + boot_o + " " + kernel_o)
    end
    if arch == "riscv64":
        push(cmds, ld + " -m elf64lriscv -T " + ld_script + " -o " + elf + " " + boot_o + " " + kernel_o)
    end

    return cmds
end

proc run_commands(cmds):
    let rc = 0
    for cmd in cmds:
        rc = sys.exec(cmd + " 2>&1")
        if rc != 0:
            return rc
        end
    end
    return 0
end

# ============================================================================
# QEMU launch commands
# ============================================================================

proc qemu_cmd(arch, elf_path):
    if arch == "x86_64":
        return "qemu-system-x86_64 -machine q35 -m 64M -display none -serial mon:stdio -no-reboot -kernel " + elf_path
    end
    if arch == "aarch64":
        return "qemu-system-aarch64 -machine virt -cpu cortex-a57 -m 128M -display none -serial mon:stdio -no-reboot -kernel " + elf_path
    end
    if arch == "riscv64":
        return "qemu-system-riscv64 -machine virt -m 128M -display none -serial mon:stdio -bios none -no-reboot -kernel " + elf_path
    end
    return ""
end

proc qemu_cmd_debug(arch, elf_path, port):
    return qemu_cmd(arch, elf_path) + " -s -S -gdb tcp::" + str(port)
end

# ============================================================================
# High-level build pipeline
# ============================================================================

proc build_kernel(arch, out_dir, features):
    let result = {}
    result["arch"] = arch
    result["out_dir"] = out_dir
    result["features"] = features

    # Generate files
    let boot_asm = out_dir + "/boot.s"
    let kernel_c = out_dir + "/kernel.c"
    let ld_script = out_dir + "/linker.ld"
    let elf = out_dir + "/kernel.elf"

    io.writefile(boot_asm, gen_boot_asm(arch, features["entry"]))
    io.writefile(kernel_c, gen_kernel_c(arch, features))
    io.writefile(ld_script, gen_linker_script(arch))

    result["boot_asm"] = boot_asm
    result["kernel_c"] = kernel_c
    result["linker_script"] = ld_script
    result["elf"] = elf
    result["commands"] = build_commands(arch, out_dir, boot_asm, kernel_c, ld_script)
    result["qemu"] = qemu_cmd(arch, elf)
    result["qemu_debug"] = qemu_cmd_debug(arch, elf, 1234)
    return result
end

proc compile_and_run(arch, out_dir, features):
    let result = build_kernel(arch, out_dir, features)
    print "Building " + arch + " kernel..."
    let rc = run_commands(result["commands"])
    if rc != 0:
        print "Build FAILED (exit code: " + str(rc) + ")"
        return result
    end
    print "Build OK: " + result["elf"]
    print ""
    print "Run in QEMU:"
    print "  " + result["qemu"]
    return result
end

# ============================================================================
# Architecture validation
# ============================================================================

proc is_valid_arch(arch):
    return arch == "x86_64" or arch == "aarch64" or arch == "riscv64"
end

proc arch_from_args(default_arch):
    let args = sys.args()
    # args[0] = "./sage", args[1] = script_name, args[2] = first user arg
    if len(args) > 2:
        return args[2]
    end
    return default_arch
end