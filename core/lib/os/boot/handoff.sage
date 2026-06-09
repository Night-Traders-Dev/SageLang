## os.boot.handoff — Boot Information Protocol
## Defines the contract between the bootloader and the kernel.

## Create a fresh SageOS boot information structure
proc create():
    return {
        "magic": 0x534147454F534249, # "SAGEOSBI"
        "mmap_addr": 0,
        "mmap_size": 0,
        "fb_base": 0,
        "fb_width": 0,
        "fb_height": 0,
        "rsdp_addr": 0,
        "cmdline": ""
    }
end

## Set memory map information
proc set_memory_map(info, mmap_addr, mmap_size):
    info["mmap_addr"] = mmap_addr
    info["mmap_size"] = mmap_size
    return nil
end

## Set framebuffer information
proc set_framebuffer(info, base, width, height, pitch):
    info["fb_base"] = base
    info["fb_width"] = width
    info["fb_height"] = height
    return nil
end

## Set kernel ELF information
proc set_kernel_elf(info, phys, virt, size):
    info["kernel_phys"] = phys
    info["kernel_virt"] = virt
    info["kernel_size"] = size
    return nil
end

## Set ACPI RSDP address
proc set_rsdp(info, rsdp_addr):
    info["rsdp_addr"] = rsdp_addr
    return nil
end

## Set command line arguments
proc set_cmdline(info, cmdline):
    info["cmdline"] = cmdline
    return nil
end

## Jump to kernel entry point with info struct
proc jump(entry_virt, info_struct_addr):
    let asm = ""
    asm = asm + "# Jump to kernel" + chr(10)
    asm = asm + "movq $" + str(info_struct_addr) + ", %rdi" + chr(10)
    asm = asm + "jmp *" + str(entry_virt) + chr(10)
    return asm
end
