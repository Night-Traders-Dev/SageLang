# boot.s - SageOS UEFI Bootloader Entry Point
.section .text
.global efi_main
efi_main:
    # Shadow space for UEFI calls
    sub $40, %rsp
    
    # Save ImageHandle and SystemTable
    mov %rcx, %r12
    mov %rdx, %r13
    
    # Get ConOut (offset 64 in SystemTable)
    mov 64(%r13), %rcx
    
    # Call OutputString (offset 8 in SimpleTextOutput protocol)
    # RCX = ConOut, RDX = pointer to UTF-16 string
    lea msg(%rip), %rdx
    mov 8(%rcx), %rax
    call *%rax
    
    # Hang for now
1:  jmp 1b
    
    add $40, %rsp
    ret

.section .data
.align 16
msg:
    # "SageOS UEFI Booting..." in UTF-16LE
    .short 0x53, 0x61, 0x67, 0x65, 0x4f, 0x53, 0x20, 0x55, 0x45, 0x46, 0x49, 0x20, 0x42, 0x6f, 0x6f, 0x74, 0x69, 0x6e, 0x67, 0x2e, 0x2e, 0x2e, 0x0d, 0x0a, 0
