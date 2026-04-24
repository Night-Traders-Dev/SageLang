# uefi.sage — Minimal UEFI Bootloader for SageOS

# UEFI Entry Point
# RCX = ImageHandle, RDX = SystemTable
proc efi_main(handle, st):
    # Loop forever so we can see it reached our code in QEMU
    while true:
        pass
    end
    return 0
end
