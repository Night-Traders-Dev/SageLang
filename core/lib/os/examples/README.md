# SageOS Examples — lib/os/examples/

Working QEMU-bootable OS examples written entirely in Sage.
Each example generates real C/assembly source, compiles it, and prints the QEMU command.

## Prerequisites

```bash
sudo apt install gcc-multilib binutils qemu-system-x86
```

## Examples

### 1. `bootloader.sage` — Standalone Multiboot2 Bootloader
Generates a 64-bit Multiboot2 bootloader that transitions from 32-bit protected
mode to 64-bit long mode, initializes COM1 serial, prints a message, and halts.

```bash
sage lib/os/examples/bootloader.sage
# Copy and run the printed QEMU command
```

Expected output: `SageOS Bootloader OK`

---

### 2. `kernel.sage` — Standalone Kernel
Generates a 32-bit Multiboot1 kernel in C that initializes serial, reads the
Multiboot memory map, runs a computation, and halts.

```bash
sage lib/os/examples/kernel.sage
```

Expected output:
```
SageOS Kernel v0.1.0
[OK] Multiboot magic verified
[OK] Memory: lower=0x280KB upper=0x7F00KB
[OK] sum(1..100) = 0x00001388 (expected 0x1388 = 5050)
[OK] Kernel halting cleanly.
```

---

### 3. `shell.sage` — Standalone Interactive Shell
Generates a kernel with a full interactive serial shell. Type commands at the
`sage@os:~$` prompt.

```bash
sage lib/os/examples/shell.sage
# Run the printed QEMU command — it's interactive!
```

Commands: `help`, `echo <text>`, `mem`, `regs`, `uptime`, `clear`, `halt`

---

### 4. `sageos.sage` — Combined Bootloader + Kernel + Shell ⭐
The complete SageOS: boot stub + kernel with VGA + serial shell, all in one
Sage program. Generates three QEMU commands (serial-only, VGA+serial, GDB debug).

```bash
sage lib/os/examples/sageos.sage
```

Commands: `help`, `echo`, `mem`, `heap`, `regs`, `vga`, `color`, `uptime`,
          `version`, `clear`, `halt`

---

## How It Works

Each example:
1. Uses `os.boot.start` / `os.boot.linker` to generate assembly/linker scripts
2. Uses `io.writefile` to write generated C and assembly to `/tmp/sageos_*/`
3. Uses `sys.exec` to invoke `as`, `gcc`, and `ld` to compile
4. Uses `os.qemu` to build and print the QEMU command line

The generated binaries are standard ELF files bootable by QEMU's `-kernel` flag
(Multiboot1 protocol) — no GRUB required.

## Output Files

All generated files go to `/tmp/sageos_*/`:
- `bootloader.sage` → `/tmp/sageos_bootloader/`
- `kernel.sage`     → `/tmp/sageos_kernel/`
- `shell.sage`      → `/tmp/sageos_shell/`
- `sageos.sage`     → `/tmp/sageos/`
