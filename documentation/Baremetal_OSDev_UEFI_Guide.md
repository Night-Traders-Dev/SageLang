# Bare-Metal / OSdev / UEFI Guide (Initial Support)

This guide describes the first implementation stage for non-hosted native targets in SageLang.

## Target Syntax

Use `--target <arch[-profile]>` on native backend commands.

Base architectures:

- `x86-64` / `x86_64`
- `aarch64` / `arm64`
- `rv64` / `riscv64`

Profile suffixes:

- `-baremetal`
- `-osdev`
- `-uefi`

Examples:

```bash
# Emit assembly for x86_64 bare-metal entry
sage --emit-asm kernel.sage --target x86_64-baremetal -o kernel.s

# Build freestanding object for OSdev flow
sage --compile-native kernel.sage --target x86_64-osdev -o kernel.o

# Emit UEFI-oriented entry symbol
sage --emit-asm boot.sage --target x86_64-uefi -o boot_uefi.s
```

## Current Profile Behavior

### Hosted (default)

- No profile suffix.
- Uses normal hosted assumptions and executable-oriented flow.

### `-baremetal` and `-osdev`

- Assembly entry symbol switches to `sage_entry`.
- `--compile-native` currently emits a freestanding object (`.o`) as the initial support step.

### `-uefi`

- Assembly entry symbol switches to `efi_main`.
- `--compile-native` currently emits a freestanding object (`.o`).
- Full PE/COFF EFI image linking is planned as a follow-up step.
- `rv64-uefi` is currently rejected (x86_64/aarch64 only).

## What This Enables Today

- Early kernel/boot pipeline integration via generated assembly/object artifacts.
- Stable entry symbol selection per target profile.
- A clear bridge to external link scripts and custom boot chain tooling.

## OS Development Library Suite (`lib/os/`)

SageLang ships with a comprehensive set of binary format parsers and hardware abstraction modules for OS kernel and bootloader development. All modules are imported with the `os.` prefix:

### Binary Format Parsers

```sage
import os.elf     # ELF32/64 headers, program/section headers, string tables
import os.pe      # PE/COFF: DOS header, COFF header, optional header, sections
import os.fat     # FAT8/12/16/32 boot sector parser, cluster math
import os.fat_dir # FAT directory traversal, file reading, path resolution
import os.mbr     # MBR partition table, CHS decode, bootable partition finder
import os.gpt     # GPT header, GUID parsing, partition type identification
```

### Hardware & Platform

```sage
import os.pci     # PCI config space (Type 0/1), BAR decode, capability lists
import os.acpi    # MADT (APIC), FADT, HPET, MCFG table parsers
import os.uefi    # EFI memory map, config tables, RSDP, ACPI SDT headers
import os.paging  # x86-64 page table entries, PTE flags, address decomposition
import os.idt     # x86-64 IDT gate construction, exception vectors, PIC remap
import os.serial  # UART/COM port config, init sequences, debug output
import os.dtb     # Flattened Device Tree parser (ARM64/RISC-V)
```

### Kernel Infrastructure

```sage
import os.alloc   # Bump, free-list, and bitmap page allocators
import os.vfs     # Virtual filesystem abstraction with pluggable backends
```

### Example: Inspect an ELF kernel

```sage
import os.elf
import io

let binary = io.readbytes("kernel.elf")
let hdr = elf.parse_header(binary)
print hdr["machine_name"]     # x86_64
print hdr["entry"]            # entry point address
print hdr["phnum"]            # number of program headers

let phdrs = elf.parse_phdrs(binary, hdr)
for i in range(len(phdrs)):
    let ph = phdrs[i]
    print ph["type_name"] + " vaddr=" + str(ph["vaddr"])
```

### Example: Parse a disk image

```sage
import os.mbr
import os.fat
import io

let disk = io.readbytes("disk.img")
let m = mbr.parse_mbr(disk)
let boot_part = mbr.find_bootable(m)
print boot_part["type_name"]    # Linux
print boot_part["lba_start"]

# Parse FAT filesystem on partition
let fat_start = boot_part["lba_start"] * 512
let boot_sector = []
for i in range(512):
    push(boot_sector, disk[fat_start + i])
let info = fat.parse_boot_sector(boot_sector)
print info["fat_type"]
```

### Example: Enumerate ACPI processors

```sage
import os.acpi

# madt_bytes from ACPI table discovery
let madt = acpi.parse_madt(madt_bytes, 0)
let cpu_count = acpi.count_processors(madt)
print "CPUs: " + str(cpu_count)

let io_apics = acpi.get_io_apics(madt)
for i in range(len(io_apics)):
    print "I/O APIC at " + str(io_apics[i]["io_apic_address"])
```

### Example: Build page tables

```sage
import os.paging

# Describe virtual address structure
let desc = paging.describe_vaddr(4294967296)
print desc["pml4_index"]
print desc["pdpt_index"]

# Create a PTE
let entry = paging.make_pte(4096, 3)  # present + writable
let decoded = paging.decode_pte(entry)
print decoded["present"]    # true
print decoded["writable"]   # true
```

### Example: Set up IDT and serial debug output

```sage
import os.idt
import os.serial

# Configure COM1 for debug output
let com1 = serial.default_config()
let init_seq = serial.init_sequence(com1)
# init_seq is a list of {port, value} pairs for port I/O

# Build IDT with handlers
let handlers = {}
handlers[0] = 4096       # Divide error handler at 0x1000
handlers[14] = 8192      # Page fault handler at 0x2000
handlers[32] = 12288     # Timer IRQ handler at 0x3000
let idt_table = idt.build_idt(handlers, 8)
let idt_bytes = idt.idt_to_bytes(idt_table)
print len(idt_bytes)     # 4096

# Remap PIC to vector 32
let pic_seq = idt.pic_remap_sequence(32)
```

### Example: Kernel page allocator

```sage
import os.alloc

# Create a bitmap allocator for 256 MB of physical memory
let pages = alloc.bitmap_create(1048576, 65536, 4096)

# Reserve first 1 MB for kernel
alloc.bitmap_mark_used(pages, 1048576, 1048576)

# Allocate pages for user process
let stack = alloc.bitmap_alloc_pages(pages, 4)   # 16 KB stack
let heap = alloc.bitmap_alloc_pages(pages, 16)    # 64 KB heap

let stats = alloc.bitmap_stats(pages)
print stats["free_pages"]
```

### Example: Read files from FAT disk image

```sage
import os.fat
import os.fat_dir
import io

let disk = io.readbytes("boot.img")
let info = fat.parse_boot_sector(disk)

# List root directory
let entries = fat_dir.list_root(disk, info)
for i in range(len(entries)):
    let e = entries[i]
    if e["is_dir"]:
        print "[DIR] " + e["name"]
    else:
        print e["name"] + " (" + str(e["size"]) + " bytes)"

# Read a file by path
let data = fat_dir.read_file_by_path(disk, info, "/config.txt")
```

### Example: Parse Device Tree (ARM64/RISC-V)

```sage
import os.dtb

let blob = io.readbytes("board.dtb")
let hdr = dtb.parse_header(blob)
let tree = dtb.parse_tree(blob, hdr)

print dtb.get_model(tree)
print dtb.count_cpus(tree)

# Find all UART devices
let uarts = dtb.find_compatible(tree, "ns16550a")
for i in range(len(uarts)):
    let reg = dtb.get_prop(uarts[i], "reg")
    if reg != nil:
        let addrs = dtb.parse_reg(reg, 2, 2)
        print "UART at " + str(addrs[0]["address"])
```

## Compiler Flags for Bare-Metal and UEFI Output

Two dedicated compiler commands produce final linked artifacts without requiring external toolchain steps:

```bash
# Produce a freestanding ELF kernel binary (x86_64 or aarch64)
sage --compile-bare kernel.sage -o kernel.elf --target x86_64

# Produce a UEFI PE application (x86_64 or aarch64 only)
sage --compile-uefi boot.sage -o boot.efi --target x86_64
```

Both flags link against `src/c/bare_metal.c`, a freestanding C runtime that supplies `memcpy`, `memset`, `memcmp`, basic integer formatting, and a panic handler — no libc dependency.

## Boot Modules (`lib/os/boot/`)

Four modules generate the low-level structures needed before a kernel's main entry point:

| Module | Import | Description |
|--------|--------|-------------|
| `multiboot.sage` | `import os.boot.multiboot` | Multiboot2 header and tag generation, boot info struct parsing |
| `gdt.sage` | `import os.boot.gdt` | x86_64 GDT descriptor construction, TSS entries, LGDT sequence builder |
| `start.sage` | `import os.boot.start` | x86_64 startup assembly generation (long mode switch, stack setup, jump to kmain) |
| `linker.sage` | `import os.boot.linker` | Linker script generation (`.text`, `.rodata`, `.data`, `.bss` sections, load/VMA addresses) |

```sage
import os.boot.multiboot
import os.boot.gdt
import os.boot.start
import os.boot.linker

# Generate a Multiboot2 header
let mb_header = multiboot.make_header({"flags": 0, "load_addr": 0x100000})
let mb_bytes = multiboot.header_to_bytes(mb_header)

# Build a minimal GDT (null + 64-bit code + data)
let gdt = gdt.make_gdt64()
let lgdt_seq = gdt.lgdt_sequence(gdt)

# Emit startup assembly
let asm_src = start.emit_start64("kmain", 0x90000)

# Emit a linker script
let lds = linker.emit_script({"load_addr": 0x100000, "sections": ["text", "rodata", "data", "bss"]})
```

## Kernel Modules (`lib/os/kernel/`)

Seven modules provide the core drivers and subsystems for a minimal x86_64 kernel:

| Module | Import | Description |
|--------|--------|-------------|
| `kmain.sage` | `import os.kernel.kmain` | Kernel entry scaffolding; handoff from Multiboot2 boot info |
| `console.sage` | `import os.kernel.console` | VGA text-mode console, 80×25, 16 color attributes, scrolling |
| `keyboard.sage` | `import os.kernel.keyboard` | PS/2 keyboard driver, scancode set 2, key event dispatch |
| `timer.sage` | `import os.kernel.timer` | PIT channel 0 configuration, IRQ0 handler, millisecond tick counter |
| `syscall.sage` | `import os.kernel.syscall` | SYSCALL/SYSRET dispatch table, argument register marshalling |
| `pmm.sage` | `import os.kernel.pmm` | Physical memory manager — bitmap allocator seeded from Multiboot2 memory map |
| `vmm.sage` | `import os.kernel.vmm` | Virtual memory manager — 4-level page tables, map/unmap, page fault handler |

```sage
import os.kernel.console
import os.kernel.timer
import os.kernel.pmm

# Initialize VGA console
let con = console.init()
console.puts(con, "Sage kernel booting...")

# Set PIT to 1000 Hz
let timer_cfg = timer.configure(1000)
let irq0_handler = timer.make_handler(timer_cfg)

# Seed physical memory manager from Multiboot2 map
let pmm_state = pmm.init_from_mmap(mmap_bytes, mmap_count, 4096)
let page = pmm.alloc_page(pmm_state)
print str(page)   # physical address of allocated page
```

## Image Builders (`lib/os/image/`)

Two modules produce bootable media artifacts:

| Module | Import | Description |
|--------|--------|-------------|
| `diskimg.sage` | `import os.image.diskimg` | Bootable .img builder — MBR partition table, FAT12/16 boot partition, kernel file |
| `iso.sage` | `import os.image.iso` | ISO 9660 image with El Torito boot record for CD/DVD/USB emulation |

```sage
import os.image.diskimg
import os.image.iso

# Build a 64 MB bootable disk image
let img = diskimg.create({"size_mb": 64, "kernel": "kernel.elf", "bootloader": "boot/mbr.bin"})
diskimg.write(img, "os.img")

# Build an ISO 9660 image
let iso_img = iso.create({"boot_image": "boot.bin", "files": ["kernel.elf", "initrd.img"]})
iso.write(iso_img, "os.iso")
```

## Filesystem Modules (ext, btrfs, f2fs)

Three new filesystem parsers extend the `lib/os/` suite for reading Linux-style filesystems:

| Module | Import | Description |
|--------|--------|-------------|
| `ext.sage` | `import os.ext` | ext2/3/4 superblock, inode table, directory entries, extent tree traversal |
| `btrfs.sage` | `import os.btrfs` | Btrfs superblock, chunk/root tree walking, subvolume listing, checksums |
| `f2fs.sage` | `import os.f2fs` | F2FS superblock, checkpoint, segment info table, node/data block addressing |

```sage
import os.ext
import io

let disk = io.readbytes("linux.img")
let sb = ext.parse_superblock(disk, 1024)
print sb["rev_level"]        # 1 (ext2/3/4 dynamic)
print sb["feature_compat"]

let inode = ext.read_inode(disk, sb, 2)   # root inode
let entries = ext.list_dir(disk, sb, inode)
for i in range(len(entries)):
    print entries[i]["name"]
```

## Quick-Start: Minimal Sage Kernel

The following steps build a bootable x86_64 kernel from a single Sage source file:

```bash
# 1. Write kernel.sage (import os.kernel.* modules, define kmain)
# 2. Compile to freestanding ELF
sage --compile-bare kernel.sage -o kernel.elf --target x86_64

# 3. Build a bootable disk image
sage -c "import os.image.diskimg; let img = diskimg.create({\"kernel\": \"kernel.elf\", \"size_mb\": 32}); diskimg.write(img, \"os.img\")"

# 4. Run in QEMU
qemu-system-x86_64 -drive format=raw,file=os.img -m 128M
```

For UEFI targets:

```bash
# Compile to UEFI PE application
sage --compile-uefi efi_main.sage -o BOOTX64.EFI --target x86_64

# Place on FAT ESP and boot via OVMF
qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -drive format=raw,file=esp.img
```

## Bare-Metal C Runtime (`src/c/bare_metal.c`)

`src/c/bare_metal.c` is a freestanding C runtime automatically linked by `--compile-bare` and `--compile-uefi`. It has no libc dependency and provides:

- `memcpy`, `memset`, `memcmp`, `memmove` — standard memory primitives
- `sage_rt_itoa`, `sage_rt_utoa` — integer-to-string conversion for kernel debug output
- `sage_rt_panic` — prints a message to the VGA console and halts the CPU (`cli; hlt`)
- Minimal `__stack_chk_fail` stub to satisfy compiler SSP requirements in freestanding mode

## Current Limitations

- UEFI `.efi` PE output requires `lld-link` or `llvm-objcopy` available in `PATH` for final image packaging.
- Native backend coverage is still evolving; some language constructs remain unsupported in this backend path.
- `rv64-uefi` is not supported (x86_64 and aarch64 only for UEFI targets).

## Recommended Next Steps

1. Add SMBIOS table parsing to `os.uefi`.
2. Add kernel ELF loader (load segments into page-allocated memory).
3. Expand native backend construct coverage for non-hosted use cases.
4. Add NVMe and AHCI driver modules to `lib/os/kernel/`.
