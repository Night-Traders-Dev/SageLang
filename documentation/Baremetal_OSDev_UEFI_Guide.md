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

## Current Limitations

- Non-hosted targets are currently object-oriented output only (no final bootable image linker flow yet).
- UEFI output is not yet a finalized `.efi` artifact in this stage.
- Native backend coverage is still evolving; some language constructs remain unsupported in this backend path.

## Recommended Next Steps

1. Add profile-aware linker script integration for bare-metal and OSdev targets.
2. Add PE/COFF image emission/link path for UEFI (`.efi` output).
3. Expand native backend construct coverage and runtime surface for non-hosted use cases.
4. Add SMBIOS table parsing to `os.uefi`.
5. Add ext2/ext4 filesystem backend for `os.vfs`.
6. Add kernel ELF loader (load segments into page-allocated memory).
