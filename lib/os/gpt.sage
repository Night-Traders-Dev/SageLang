gc_disable()
# GPT (GUID Partition Table) parser
# Parses GPT header and partition entries per UEFI specification

proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256

proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216

proc read_u64_le(bs, off):
    let lo = read_u32_le(bs, off)
    let hi = read_u32_le(bs, off + 4)
    return lo + hi * 4294967296

# Read a GUID (16 bytes) as a formatted string
# GUID format: DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD
# First 3 fields are little-endian, last 2 are big-endian
proc hex_byte(b):
    let hi = (b >> 4) & 15
    let lo = b & 15
    let digits = "0123456789abcdef"
    return digits[hi] + digits[lo]

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

proc gpt_type_name(guid):
    if guid == "00000000-0000-0000-0000-000000000000":
        return "Unused"
    if guid == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b":
        return "EFI System"
    if guid == "21686148-6449-6e6f-744e-656564454649":
        return "BIOS Boot"
    if guid == "0fc63daf-8483-4772-8e79-3d69d8477de4":
        return "Linux filesystem"
    if guid == "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f":
        return "Linux swap"
    if guid == "4f68bce3-e8cd-4db1-96e7-fbcaf984b709":
        return "Linux root (x86-64)"
    if guid == "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7":
        return "Microsoft basic data"
    if guid == "e3c9e316-0b5c-4db8-817d-f92df00215ae":
        return "Microsoft reserved"
    return "Unknown"

# Check GPT signature at offset 0 of GPT header
proc is_valid_gpt(bs, off):
    if len(bs) < off + 92:
        return false
    let sig_lo = read_u32_le(bs, off)
    let sig_hi = read_u32_le(bs, off + 4)
    return sig_lo == 541673029 and sig_hi == 1414676816

# Parse GPT header (typically at LBA 1 = byte offset 512)
proc parse_header(bs, off):
    if not is_valid_gpt(bs, off):
        return nil
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
    entry["name"] = name
    # Size in sectors
    if entry["first_lba"] > 0:
        entry["sector_count"] = entry["last_lba"] - entry["first_lba"] + 1
    else:
        entry["sector_count"] = 0
    return entry

# Parse all GPT partition entries
proc parse_entries(bs, hdr):
    let entries = []
    let base = hdr["partition_entry_lba"] * 512
    let entry_size = hdr["partition_entry_size"]
    for i in range(hdr["num_partition_entries"]):
        let off = base + i * entry_size
        if off + entry_size > len(bs):
            return entries
        let entry = parse_entry(bs, off, entry_size)
        # Skip unused entries
        if entry["type_guid"] != "00000000-0000-0000-0000-000000000000":
            push(entries, entry)
    return entries

# Check if an entry has the system partition attribute
proc is_system_partition(entry):
    return (entry["attributes"] & 1) != 0

# Check if entry is a specific well-known type
proc is_efi_system(entry):
    return entry["type_guid"] == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"

proc is_linux_fs(entry):
    return entry["type_guid"] == "0fc63daf-8483-4772-8e79-3d69d8477de4"
