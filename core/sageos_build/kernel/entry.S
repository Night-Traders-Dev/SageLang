.global _start
.extern kmain

.section .text
.code64

_start:
    cld

    lea stack_top(%rip), %rsp
    andq $-16, %rsp

    /*
     * UEFI loader is built for Microsoft x64 ABI.
     * It passes the first argument in RCX.
     *
     * Kernel C is built for SysV x86_64 ABI.
     * SysV expects the first argument in RDI.
     */
    mov %rcx, %rdi

    call kmain

.hang:
    hlt
    jmp .hang

.section .bss
.align 16
stack_bottom:
    .skip 65536
stack_top:
