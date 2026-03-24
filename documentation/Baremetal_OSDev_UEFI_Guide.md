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
import os.mbr     # MBR partition table, CHS decode, bootable partition finder
import os.gpt     # GPT header, GUID parsing, partition type identification
```

### Hardware & Platform

```sage
import os.pci     # PCI config space (Type 0/1), BAR decode, capability lists
import os.acpi    # MADT (APIC), FADT, HPET, MCFG table parsers
import os.uefi    # EFI memory map, config tables, RSDP, ACPI SDT headers
import os.paging  # x86-64 page table entries, PTE flags, address decomposition
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

## Current Limitations

- Non-hosted targets are currently object-oriented output only (no final bootable image linker flow yet).
- UEFI output is not yet a finalized `.efi` artifact in this stage.
- Native backend coverage is still evolving; some language constructs remain unsupported in this backend path.

## Recommended Next Steps

1. Add profile-aware linker script integration for bare-metal and OSdev targets.
2. Add PE/COFF image emission/link path for UEFI (`.efi` output).
3. Expand native backend construct coverage and runtime surface for non-hosted use cases.
4. Add directory traversal and FAT chain walking to `os.fat`.
5. Add SMBIOS table parsing to `os.uefi`.
6. Add interrupt descriptor table (IDT) helpers to `os.paging`.
