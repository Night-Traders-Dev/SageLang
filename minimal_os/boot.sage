import os.boot.start as boot
import os.boot.config as config
import io

## Generate the boot assembly for x86_64
## We use a minimal config for the boot stub.
let boot_asm = boot.emit_start("x86_64", "kmain", "stack_top")

## Add BSS symbols to boot_asm
boot_asm = boot_asm + ".section .bss" + "\n"
boot_asm = boot_asm + ".global __bss_start" + "\n"
boot_asm = boot_asm + "__bss_start:" + "\n"
boot_asm = boot_asm + ".global __bss_end" + "\n"
boot_asm = boot_asm + "__bss_end:" + "\n"

## Write the assembly to a file
io.writefile("/home/elf_g/sagelang/minimal_os/boot.s", boot_asm)

print("Boot assembly generated: minimal_os/boot.s")
