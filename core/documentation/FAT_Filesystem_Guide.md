# FAT Filesystem Guide (Initial Support)

This guide covers the `fat` module in SageLang's OS development library suite (`lib/os/`).

## Scope

Current implementation focuses on boot-sector parsing and layout math for:

- FAT8
- FAT12
- FAT16
- FAT32

This is foundation work for later directory traversal, cluster-chain walking, and read/write file operations.

## Import

```sage
import os.fat
```

The module binds as `fat` (the last component of the dotted path), so all calls use `fat.*`.

## Directory Traversal (`os.fat_dir`)

The `fat_dir` module provides high-level directory and file operations.

```sage
import os.fat
import os.fat_dir

let disk = io.readfile("disk.img")
let info = fat.parse_boot_sector(disk)

# List root directory
let entries = fat_dir.list_root(disk, info)
for entry in entries:
    print entry["name"] + (entry["is_dir"] ? "/" : "")

# Find and read a file by path
let content = fat_dir.read_file_by_path(disk, info, "/SYSTEM/BOOT.CFG")

# List a specific directory
let sub_entries = fat_dir.list_dir_by_path(disk, info, "/HOME/USER")
```

### Directory Entry Structure

Each entry in a directory listing is a dictionary:

| Key | Type | Description |
|-----|------|-------------|
| `name` | string | Filename (lowercase 8.3) |
| `is_dir` | bool | True if it's a directory |
| `is_file` | bool | True if it's a regular file |
| `size` | int | File size in bytes |
| `cluster` | int | Starting cluster index |
| `year/month/day` | int | Creation date |
| `hour/minute/second`| int | Creation time |

## API

### `fat.parse_boot_sector(bytes_array)`

Parses a boot sector from an array of byte values (`0..255`) and returns a metadata dict.

### `fat.probe(path)`

Reads the beginning of a disk image / block dump file and parses boot-sector metadata.

### `fat.cluster_to_lba(info, cluster)`

Computes the absolute sector index for a given data cluster using parsed boot info.

### `fat.fat_entry_offset(info, cluster)`

Returns FAT table offset metadata for a cluster (including FAT12 odd/even handling).

## Constants

- `fat.FAT8`
- `fat.FAT12`
- `fat.FAT16`
- `fat.FAT32`

## Metadata Fields

The dict returned by `parse_boot_sector`/`probe` includes:

- `valid`
- `fat_type` (`"FAT8"`, `"FAT12"`, `"FAT16"`, `"FAT32"`, or `"UNKNOWN"`)
- `fat_bits`
- `bytes_per_sector`
- `sectors_per_cluster`
- `reserved_sector_count`
- `fat_count`
- `root_entry_count`
- `total_sectors`
- `sectors_per_fat`
- `root_dir_sectors`
- `first_data_sector`
- `data_sector_count`
- `cluster_count`
- `root_cluster`
- `media_descriptor`
- `fs_type_label`
- `volume_label`

`probe(path)` additionally includes `source_path`.

## Example

```sage
import os.fat
import io

let boot = io.readbytes("disk.img")
let info = fat.parse_boot_sector(boot)

if info["valid"]:
    print info["fat_type"]
    print info["cluster_count"]
    print fat.cluster_to_lba(info, 2)
```

## Future Work

- Write support (currently read-only).
- Long File Name (LFN) support.
- File deletion and allocation.
