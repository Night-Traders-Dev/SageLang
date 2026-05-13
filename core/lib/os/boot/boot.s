# boot.s - SageOS UEFI Bootloader Entry Point
.section .text
.global efi_main
efi_main:
    # Shadow space for UEFI calls
    sub $40, %rsp
    
    # Call boot_main to load kernel
    # rcx is ImageHandle, rdx is SystemTable
    movq %rdx, %rcx          # Pass SystemTable as first arg
    subq $32, %rsp
    call load_kernel
    addq $32, %rsp

    # Jump to kernel at 0x100000
    movq $0x100000, %rax
    jmp *%rax
.align 16
msg:
    # "SageOS UEFI Booting..." in UTF-16LE
    .short 0x53, 0x61, 0x67, 0x65, 0x4f, 0x53, 0x20, 0x55, 0x45, 0x46, 0x49, 0x20, 0x42, 0x6f, 0x6f, 0x74, 0x69, 0x6e, 0x67, 0x2e, 0x2e, 0x2e, 0x0d, 0x0a, 0
