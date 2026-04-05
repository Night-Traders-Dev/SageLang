# EXPECT: x86_64 boot assembly generated
# EXPECT: aarch64 boot assembly generated
# EXPECT: riscv64 boot assembly generated
# EXPECT: x86_64 serial assembly generated
# EXPECT: aarch64 serial assembly generated
# EXPECT: riscv64 serial assembly generated
# EXPECT: x86_64 kernel C generated
# EXPECT: aarch64 kernel C generated
# EXPECT: riscv64 kernel C generated
# EXPECT: x86_64 QEMU command generated
# EXPECT: aarch64 QEMU command generated
# EXPECT: riscv64 QEMU command generated
gc_disable()
# Test boot build integration layer

from os.boot.build import generate_serial_boot_x86, generate_serial_boot_aarch64, generate_serial_boot_riscv64
from os.boot.build import generate_kernel_c, qemu_command
from os.boot.start import generate_boot_asm, emit_start_aarch64, emit_start_riscv64

# Test boot assembly generation for all architectures
let x86_asm = generate_boot_asm(nil)
if len(x86_asm) > 100:
    print "x86_64 boot assembly generated"

let aarch64_asm = emit_start_aarch64("kmain", "stack_top")
if len(aarch64_asm) > 50:
    print "aarch64 boot assembly generated"

let riscv64_asm = emit_start_riscv64("kmain", "stack_top")
if len(riscv64_asm) > 50:
    print "riscv64 boot assembly generated"

# Test serial assembly generation
let x86_serial = generate_serial_boot_x86()
if contains(x86_serial, "serial_putchar") and contains(x86_serial, "serial_puts"):
    print "x86_64 serial assembly generated"

let aarch64_serial = generate_serial_boot_aarch64()
if contains(aarch64_serial, "serial_putchar") and contains(aarch64_serial, "serial_puts"):
    print "aarch64 serial assembly generated"

let riscv64_serial = generate_serial_boot_riscv64()
if contains(riscv64_serial, "serial_putchar") and contains(riscv64_serial, "serial_puts"):
    print "riscv64 serial assembly generated"

# Test kernel C generation
let x86_c = generate_kernel_c("x86_64", "Hello from x86_64")
if contains(x86_c, "kmain") and contains(x86_c, "hlt"):
    print "x86_64 kernel C generated"

let aarch64_c = generate_kernel_c("aarch64", "Hello from aarch64")
if contains(aarch64_c, "kmain") and contains(aarch64_c, "wfe"):
    print "aarch64 kernel C generated"

let riscv64_c = generate_kernel_c("riscv64", "Hello from riscv64")
if contains(riscv64_c, "kmain") and contains(riscv64_c, "wfi"):
    print "riscv64 kernel C generated"

# Test QEMU command generation
let x86_qemu = qemu_command("x86_64", "kernel.elf")
if contains(x86_qemu, "qemu-system-x86_64") and contains(x86_qemu, "-serial stdio"):
    print "x86_64 QEMU command generated"

let aarch64_qemu = qemu_command("aarch64", "kernel.elf")
if contains(aarch64_qemu, "qemu-system-aarch64") and contains(aarch64_qemu, "virt"):
    print "aarch64 QEMU command generated"

let riscv64_qemu = qemu_command("riscv64", "kernel.elf")
if contains(riscv64_qemu, "qemu-system-riscv64") and contains(riscv64_qemu, "-bios none"):
    print "riscv64 QEMU command generated"
