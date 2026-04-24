# uefi.sage — Minimal UEFI Bootloader for SageOS

# UEFI Entry Point
# RCX = ImageHandle, RDX = SystemTable
proc efi_main(handle, st):
    # For now, just return success
    return 0
end
