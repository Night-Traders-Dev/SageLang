gc_disable()
# GPT (GUID Partition Table) parser
# Parses GPT header and partition entries per UEFI specification

@inline
proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256
end

@inline
proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216
end

proc read_u64_le(bs, off):
    let lo = read_u32_le(bs, off)
    let hi = read_u32_le(bs, off + 4)
    return lo + hi * 4294967296
end

# Read a GUID (16 bytes) as a formatted string
# GUID format: DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD
# First 3 fields are little-endian, last 2 are big-endian
@inline
proc hex_byte(b):
    let hi = (b >> 4) & 15
    let lo = b & 15
    let digits = "0123456789abcdef"
    return digits[hi] + digits[lo]
end

proc read_guid(bs, off):
    # Time-low (4 bytes LE)
    let g = hex_byte(bs[off + 3]) + hex_byte(bs[off + 2]) + hex_byte(bs[off + 1]) + hex_byte(bs[off])
    g = g + "-"
    # Time-mid (2 bytes LE)
    g = g + hex_byte(bs[off + 5]) + hex_byte(bs[off + 4])
    g = g + "-"
    # Time-hi (2 bytes LE)
    g = g + hex_byte(bs[off + 7]) + hex_byte(bs[off + 6])
    g = g + "-"
    # Clock-seq (2 bytes BE)
    g = g + hex_byte(bs[off + 8]) + hex_byte(bs[off + 9])
    g = g + "-"
    # Node (6 bytes BE)
    g = g + hex_byte(bs[off + 10]) + hex_byte(bs[off + 11]) + hex_byte(bs[off + 12])
    g = g + hex_byte(bs[off + 13]) + hex_byte(bs[off + 14]) + hex_byte(bs[off + 15])
    return g
end

comptime:
    # Well-known partition type GUIDs
    let GPT_TYPE_UNUSED = "00000000-0000-0000-0000-000000000000"
    let GPT_TYPE_EFI_SYSTEM = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    let GPT_TYPE_BIOS_BOOT = "21686148-6449-6e6f-744e-656564454649"
    let GPT_TYPE_LINUX_FS = "0fc63daf-8483-4772-8e79-3d69d8477de4"
    let GPT_TYPE_LINUX_SWAP = "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
    let GPT_TYPE_LINUX_ROOT_X86_64 = "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
    let GPT_TYPE_MS_BASIC_DATA = "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
    let GPT_TYPE_MS_RESERVED = "e3c9e316-0b5c-4db8-817d-f92df00215ae"

    # GPT signature: "EFI PART" = 0x5452415020494645
    # "EFI PART" as two LE u32s: 0x20494645, 0x54524150
    let GPT_SIGNATURE_LO = 541673029
    let GPT_SIGNATURE_HI = 1414676816
end

proc gpt_type_name(guid):
    if guid == "00000000-0000-0000-0000-000000000000":
        return "Unused"
    end
    if guid == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b":
        return "EFI System"
    end
    if guid == "21686148-6449-6e6f-744e-656564454649":
        return "BIOS Boot"
    end
    if guid == "0fc63daf-8483-4772-8e79-3d69d8477de4":
        return "Linux filesystem"
    end
    if guid == "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f":
        return "Linux swap"
    end
    if guid == "4f68bce3-e8cd-4db1-96e7-fbcaf984b709":
        return "Linux root (x86-64)"
    end
    if guid == "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7":
        return "Microsoft basic data"
    end
    if guid == "e3c9e316-0b5c-4db8-817d-f92df00215ae":
        return "Microsoft reserved"
    end
    return "Unknown"
end

# Check GPT signature at offset 0 of GPT header
proc is_valid_gpt(bs, off):
    if len(bs) < off + 92:
        return false
    end
    let sig_lo = read_u32_le(bs, off)
    let sig_hi = read_u32_le(bs, off + 4)
    return sig_lo == 541673029 and sig_hi == 1414676816
end

# Parse GPT header (typically at LBA 1 = byte offset 512)
proc parse_header(bs, off):
    if not is_valid_gpt(bs, off):
        return nil
    end
    let hdr = {}
    hdr["revision"] = read_u32_le(bs, off + 8)
    hdr["header_size"] = read_u32_le(bs, off + 12)
    hdr["header_crc32"] = read_u32_le(bs, off + 16)
    hdr["my_lba"] = read_u64_le(bs, off + 24)
    hdr["alternate_lba"] = read_u64_le(bs, off + 32)
    hdr["first_usable_lba"] = read_u64_le(bs, off + 40)
    hdr["last_usable_lba"] = read_u64_le(bs, off + 48)
    hdr["disk_guid"] = read_guid(bs, off + 56)
    hdr["partition_entry_lba"] = read_u64_le(bs, off + 72)
    hdr["num_partition_entries"] = read_u32_le(bs, off + 80)
    hdr["partition_entry_size"] = read_u32_le(bs, off + 84)
    hdr["partition_array_crc32"] = read_u32_le(bs, off + 88)
    return hdr
end

# Parse a single GPT partition entry
proc parse_entry(bs, off, entry_size):
    let entry = {}
    entry["type_guid"] = read_guid(bs, off)
    entry["unique_guid"] = read_guid(bs, off + 16)
    entry["first_lba"] = read_u64_le(bs, off + 32)
    entry["last_lba"] = read_u64_le(bs, off + 40)
    entry["attributes"] = read_u64_le(bs, off + 48)
    entry["type_name"] = gpt_type_name(entry["type_guid"])
    # Read partition name (UTF-16LE, up to 36 chars at offset 56)
    let name = ""
    let i = 0
    while i < 72:
        if off + 56 + i + 1 >= len(bs):
            i = 72
        else:
            let ch = read_u16_le(bs, off + 56 + i)
            if ch == 0:
                i = 72
            else:
                name = name + chr(ch)
                i = i + 2
            end
        end
    end
    entry["name"] = name
    # Size in sectors
    if entry["first_lba"] > 0:
        entry["sector_count"] = entry["last_lba"] - entry["first_lba"] + 1
    else:
        entry["sector_count"] = 0
    end
    return entry
end

# Parse all GPT partition entries
proc parse_entries(bs, hdr):
    let entries = []
    let base = hdr["partition_entry_lba"] * 512
    let entry_size = hdr["partition_entry_size"]
    for i in range(hdr["num_partition_entries"]):
        let off = base + i * entry_size
        if off + entry_size > len(bs):
            return entries
        end
        let entry = parse_entry(bs, off, entry_size)
        # Skip unused entries
        if entry["type_guid"] != "00000000-0000-0000-0000-000000000000":
            push(entries, entry)
        end
    end
    return entries
end

# Check if an entry has the system partition attribute
@inline
proc is_system_partition(entry):
    return (entry["attributes"] & 1) != 0
end

# Check if entry is a specific well-known type
@inline
proc is_efi_system(entry):
    return entry["type_guid"] == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
end

@inline
proc is_linux_fs(entry):
    return entry["type_guid"] == "0fc63daf-8483-4772-8e79-3d69d8477de4"
end

# ========== CRC32 Validation ==========

let _gpt_crc_table = []
let _gpt_crc_init = false

proc _init_gpt_crc32():
    if _gpt_crc_init:
        return
    end
    for i in range(256):
        let crc = i
        for j in range(8):
            if (crc & 1) != 0:
                crc = (crc >> 1) ^ 3988292384
            else:
                crc = crc >> 1
            end
        end
        push(_gpt_crc_table, crc)
    end
    _gpt_crc_init = true
end

proc gpt_crc32(data, start, length):
    _init_gpt_crc32()
    let crc = 4294967295
    for i in range(length):
        let idx = (crc ^ data[start + i]) & 255
        crc = (crc >> 8) ^ _gpt_crc_table[idx]
    end
    return crc ^ 4294967295
end

proc validate_header_crc(bs, off):
    let stored_crc = read_u32_le(bs, off + 16)
    # Zero out CRC field for calculation
    let header_copy = []
    let header_size = read_u32_le(bs, off + 12)
    for i in range(header_size):
        push(header_copy, bs[off + i])
    end
    # Zero CRC field (bytes 16-19)
    header_copy[16] = 0
    header_copy[17] = 0
    header_copy[18] = 0
    header_copy[19] = 0
    let calc_crc = gpt_crc32(header_copy, 0, header_size)
    return calc_crc == stored_crc
end

proc validate_entries_crc(bs, hdr):
    let stored_crc = hdr["partition_entry_crc32"]
    let base = hdr["partition_entry_lba"] * 512
    let total_size = hdr["num_partition_entries"] * hdr["partition_entry_size"]
    let calc_crc = gpt_crc32(bs, base, total_size)
    return calc_crc == stored_crc
end

# ========== Partition CRUD ==========

proc _write_u32_le(bs, off, val):
    bs[off] = val & 255
    bs[off + 1] = (val >> 8) & 255
    bs[off + 2] = (val >> 16) & 255
    bs[off + 3] = (val >> 24) & 255
end

proc _write_u64_le(bs, off, val):
    for i in range(8):
        bs[off + i] = (val >> (i * 8)) & 255
    end
end

proc _hex_val(c):
    if c == "0":
        return 0
    end
    if c == "1":
        return 1
    end
    if c == "2":
        return 2
    end
    if c == "3":
        return 3
    end
    if c == "4":
        return 4
    end
    if c == "5":
        return 5
    end
    if c == "6":
        return 6
    end
    if c == "7":
        return 7
    end
    if c == "8":
        return 8
    end
    if c == "9":
        return 9
    end
    if c == "a" or c == "A":
        return 10
    end
    if c == "b" or c == "B":
        return 11
    end
    if c == "c" or c == "C":
        return 12
    end
    if c == "d" or c == "D":
        return 13
    end
    if c == "e" or c == "E":
        return 14
    end
    if c == "f" or c == "F":
        return 15
    end
    return -1
end

proc _hex_byte(s, idx):
    let hi = _hex_val(s[idx])
    let lo = _hex_val(s[idx + 1])
    if hi < 0 or lo < 0:
        return -1
    end
    return hi * 16 + lo
end

proc _write_guid(bs, off, guid_str):
    # Parse GUID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" to 16 bytes
    # Mixed-endian: first 3 fields LE, last 2 fields BE
    # Expected format: 8-4-4-4-12 hex digits with dashes = 36 chars
    if guid_str == nil or len(guid_str) != 36:
        for i in range(16):
            bs[off + i] = 0
        end
        return
    end
    # Strip dashes to get 32 hex chars
    let hex = ""
    let i = 0
    while i < 36:
        if guid_str[i] != "-":
            hex = hex + guid_str[i]
        end
        i = i + 1
    end
    if len(hex) != 32:
        for i in range(16):
            bs[off + i] = 0
        end
        return
    end
    # First 4 bytes (from first 8 hex chars) - little-endian
    let b0 = _hex_byte(hex, 0)
    let b1 = _hex_byte(hex, 2)
    let b2 = _hex_byte(hex, 4)
    let b3 = _hex_byte(hex, 6)
    if b0 < 0 or b1 < 0 or b2 < 0 or b3 < 0:
        for i in range(16):
            bs[off + i] = 0
        end
        return
    end
    bs[off + 0] = b3
    bs[off + 1] = b2
    bs[off + 2] = b1
    bs[off + 3] = b0
    # Next 2 bytes (from next 4 hex chars) - little-endian
    let b4 = _hex_byte(hex, 8)
    let b5 = _hex_byte(hex, 10)
    if b4 < 0 or b5 < 0:
        for i in range(16):
            bs[off + i] = 0
        end
        return
    end
    bs[off + 4] = b5
    bs[off + 5] = b4
    # Next 2 bytes (from next 4 hex chars) - little-endian
    let b6 = _hex_byte(hex, 12)
    let b7 = _hex_byte(hex, 14)
    if b6 < 0 or b7 < 0:
        for i in range(16):
            bs[off + i] = 0
        end
        return
    end
    bs[off + 6] = b7
    bs[off + 7] = b6
    # Last 8 bytes (from last 16 hex chars) - big-endian
    let j = 0
    while j < 8:
        let bv = _hex_byte(hex, 16 + j * 2)
        if bv < 0:
            for i in range(16):
                bs[off + i] = 0
            end
            return
        end
        bs[off + 8 + j] = bv
        j = j + 1
    end
end

proc create_partition_entry(bs, hdr, index, type_guid, first_lba, last_lba, name):
    let base = hdr["partition_entry_lba"] * 512
    let off = base + index * hdr["partition_entry_size"]
    # Write type GUID
    _write_guid(bs, off, type_guid)
    # Write unique GUID (random-ish)
    for i in range(16):
        bs[off + 16 + i] = (index * 37 + i * 13 + 7) & 255
    end
    # Write LBA range
    _write_u64_le(bs, off + 32, first_lba)
    _write_u64_le(bs, off + 40, last_lba)
    # Write attributes
    _write_u64_le(bs, off + 48, 0)
    # Write name (UTF-16LE)
    for i in range(len(name)):
        if i < 36:
            bs[off + 56 + i * 2] = ord(name[i])
            bs[off + 56 + i * 2 + 1] = 0
        end
    end
end

proc delete_partition(bs, hdr, index):
    let base = hdr["partition_entry_lba"] * 512
    let off = base + index * hdr["partition_entry_size"]
    for i in range(hdr["partition_entry_size"]):
        bs[off + i] = 0
    end
end

proc update_header_crc(bs, off, hdr):
    # Recalculate partition entries CRC
    let entries_base = hdr["partition_entry_lba"] * 512
    let entries_size = hdr["num_partition_entries"] * hdr["partition_entry_size"]
    let entries_crc = gpt_crc32(bs, entries_base, entries_size)
    _write_u32_le(bs, off + 88, entries_crc)
    # Zero header CRC, calculate, write back
    _write_u32_le(bs, off + 16, 0)
    let header_size = read_u32_le(bs, off + 12)
    let header_crc = gpt_crc32(bs, off, header_size)
    _write_u32_le(bs, off + 16, header_crc)
end

# ========== Backup Header ==========

proc parse_backup_header(bs):
    # Backup header is at last LBA of disk
    let disk_size = len(bs)
    let backup_off = disk_size - 512
    if backup_off < 512:
        return nil
    end
    if not is_valid_gpt(bs, backup_off):
        return nil
    end
    return parse_header(bs, backup_off)
end

@inline
proc is_linux_swap(entry):
    return entry["type_guid"] == "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
end

@inline
proc is_windows_basic(entry):
    return entry["type_guid"] == "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
end
