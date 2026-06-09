# hello_kernel.sage — Build a minimal "Hello World" kernel for any architecture
#
# This example generates all files needed for a bare-metal kernel that
# prints "Hello from SageOS!" over serial UART and halts.
#
# Supported architectures: x86_64, aarch64, riscv64
#
# Usage:
#   sage hello_kernel.sage              # defaults to x86_64
#   sage hello_kernel.sage x86_64       # explicit x86_64
#   sage hello_kernel.sage aarch64      # AArch64 (ARM64)
#   sage hello_kernel.sage riscv64      # RISC-V 64-bit
#
# After running, follow the printed build commands to assemble, link, and
# launch in QEMU.

import sys
from os.boot.build import write_build_files, qemu_command

# Parse architecture from command line (default: x86_64)
let arch = "x86_64"
let args = sys.args
if len(args) > 1:
    arch = args[1]

if arch != "x86_64" and arch != "aarch64" and arch != "riscv64":
    print "Error: unsupported architecture: " + arch
    print "Supported: x86_64, aarch64, riscv64"
    sys.exit(1)

print "=== SageLang Bare-Metal Kernel Builder ==="
print "Architecture: " + arch
print ""

# Generate all build files
let output_dir = "build_" + arch
sys.exec("mkdir -p " + output_dir)

let files = write_build_files(arch, output_dir, "Hello from SageOS!")

print "Generated files:"
print "  Boot assembly:   " + files["boot_asm"]
print "  Kernel C:        " + files["kernel_c"]
print "  Linker script:   " + files["linker_script"]
print "  Output ELF:      " + files["output_elf"]
print ""

print "Build commands:"
for cmd in files["build_commands"]:
    print "  " + cmd

print ""
print "Run in QEMU:"
print "  " + files["qemu_command"]
print ""
print "To debug with GDB:"
print "  " + files["qemu_command"] + " -s -S &"
print "  gdb " + files["output_elf"] + " -ex 'target remote :1234'"
