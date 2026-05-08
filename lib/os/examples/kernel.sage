gc_disable()
# =============================================================================
# SageOS Example: Minimal Multi-Architecture Kernel
# =============================================================================
# Generates a bare-metal kernel for x86_64, aarch64, or riscv64 that:
#   - Prints "Hello from SageOS on {arch}!" over serial UART
#   - Runs a computation (sum 1..100 = 5050) to prove execution
#   - Prints memory info (x86_64: from Multiboot; aarch64/riscv64: hardcoded)
#   - Halts cleanly
#
# Usage:
#   sage lib/os/examples/kernel.sage              # defaults to x86_64
#   sage lib/os/examples/kernel.sage x86_64       # x86_64
#   sage lib/os/examples/kernel.sage aarch64      # AArch64
#   sage lib/os/examples/kernel.sage riscv64      # RISC-V 64
# =============================================================================

import sys
import io
import os.examples.common as common

let NL = chr(10)
let arch = common.arch_from_args("x86_64")

if not common.is_valid_arch(arch):
    print "Error: unsupported architecture: " + arch
    print "Supported: x86_64, aarch64, riscv64"
    sys.exit(1)
end

print "=== SageOS Minimal Kernel ==="
print "Architecture: " + arch
print ""

let out_dir = "/tmp/sageos_kernel_" + arch
sys.exec("mkdir -p " + out_dir)

# Define features for this kernel
let features = {}
features["entry"] = "kmain"
features["has_shell"] = false
features["has_vga"] = false

# Generate boot asm, kernel C, linker script
let result = common.build_kernel(arch, out_dir, features)

# Append the kmain function to the kernel C
let kernel_main_c = ""

# x86_64: parse multiboot info
if arch == "x86_64":
    kernel_main_c = kernel_main_c + "void kmain(uint32_t magic, mb_t *mbi) {" + NL
    kernel_main_c = kernel_main_c + "    parse_multiboot(magic, mbi);" + NL
else:
    kernel_main_c = kernel_main_c + "void kmain(void) {" + NL
end

kernel_main_c = kernel_main_c + "    serial_init();" + NL
kernel_main_c = kernel_main_c + "    serial_puts(\"\\n\");" + NL
kernel_main_c = kernel_main_c + "    serial_puts(\"========================================\\n\");" + NL
kernel_main_c = kernel_main_c + "    serial_puts(\"  SageOS Kernel v0.2.0\\n\");" + NL
kernel_main_c = kernel_main_c + "    serial_puts(\"  Architecture: " + arch + "\\n\");" + NL
kernel_main_c = kernel_main_c + "    serial_puts(\"  Built with Sage Programming Language\\n\");" + NL
kernel_main_c = kernel_main_c + "    serial_puts(\"========================================\\n\");" + NL
kernel_main_c = kernel_main_c + "    serial_puts(\"\\n\");" + NL

# Memory info
if arch == "x86_64":
    kernel_main_c = kernel_main_c + "    serial_puts(\"[OK] Memory: lower=\"); serial_putdec(mem_lower_kb);" + NL
    kernel_main_c = kernel_main_c + "    serial_puts(\"KB upper=\"); serial_putdec(mem_upper_kb); serial_puts(\"KB\\n\");" + NL
else:
    kernel_main_c = kernel_main_c + "    serial_puts(\"[OK] Memory: 128MB (QEMU default)\\n\");" + NL
end

# Computation: sum 1..100
kernel_main_c = kernel_main_c + "    uint32_t sum = 0;" + NL
kernel_main_c = kernel_main_c + "    for (uint32_t i = 1; i <= 100; i++) sum += i;" + NL
kernel_main_c = kernel_main_c + "    serial_puts(\"[OK] sum(1..100) = \"); serial_putdec(sum);" + NL
kernel_main_c = kernel_main_c + "    serial_puts(\" (expected 5050)\\n\");" + NL

kernel_main_c = kernel_main_c + "    serial_puts(\"\\n[OK] Kernel halting cleanly.\\n\");" + NL
if arch == "x86_64":
    kernel_main_c = kernel_main_c + "    __asm__ volatile(\"cli; hlt\");" + NL
end
if arch == "aarch64":
    kernel_main_c = kernel_main_c + "    while (1) __asm__ volatile(\"wfe\");" + NL
end
if arch == "riscv64":
    kernel_main_c = kernel_main_c + "    while (1) __asm__ volatile(\"wfi\");" + NL
end
kernel_main_c = kernel_main_c + "}" + NL

# Append kmain to the generated kernel C file
let kernel_c_path = result["kernel_c"]
let existing = io.readfile(kernel_c_path)
io.writefile(kernel_c_path, existing + NL + kernel_main_c)

# Build
print "Building..."
let rc = common.run_commands(result["commands"])
if rc != 0:
    print "Build FAILED (exit code: " + str(rc) + ")"
    print "Failed commands may need toolchain install:"
    if arch == "aarch64":
        print "  sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu"
    end
    if arch == "riscv64":
        print "  sudo apt install gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu"
    end
    sys.exit(1)
end

print "Build OK: " + result["elf"]
print ""
print "=== Run with QEMU ==="
print result["qemu"]
print ""
print "Expected output: SageOS Kernel v0.2.0 + arch + sum(1..100)=5050"
