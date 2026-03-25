gc_disable()
# MBR (Master Boot Record) partition table parser
# Parses the 512-byte MBR structure including partition entries and boot signature

proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256

proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216

# MBR boot signature
let MBR_SIGNATURE = 43605

# Partition type constants
let PART_EMPTY = 0
let PART_FAT12 = 1
let PART_FAT16_SMALL = 4
let PART_EXTENDED = 5
let PART_FAT16_LARGE = 6
let PART_NTFS = 7
let PART_FAT32 = 11
let PART_FAT32_LBA = 12
let PART_FAT16_LBA = 14
let PART_EXTENDED_LBA = 15
let PART_LINUX_SWAP = 130
let PART_LINUX = 131
let PART_LINUX_LVM = 142
let PART_EFI_GPT = 238
let PART_EFI_SYSTEM = 239

proc partition_type_name(t):
    if t == 0:
        return "Empty"
    if t == 1:
        return "FAT12"
    if t == 4:
        return "FAT16 (<32MB)"
    if t == 5:
        return "Extended"
    if t == 6:
        return "FAT16 (>32MB)"
    if t == 7:
        return "NTFS/exFAT"
    if t == 11:
        return "FAT32"
    if t == 12:
        return "FAT32 (LBA)"
    if t == 14:
        return "FAT16 (LBA)"
    if t == 15:
        return "Extended (LBA)"
    if t == 130:
        return "Linux swap"
    if t == 131:
        return "Linux"
    if t == 142:
        return "Linux LVM"
    if t == 238:
        return "EFI GPT protective"
    if t == 239:
        return "EFI System"
    return "Unknown"

# Decode CHS (Cylinder-Head-Sector) address from 3 bytes
proc decode_chs(bs, off):
    let chs = {}
    chs["head"] = bs[off]
    chs["sector"] = bs[off + 1] & 63
    chs["cylinder"] = ((bs[off + 1] & 192) << 2) + bs[off + 2]
    return chs

# Parse a single MBR partition entry (16 bytes starting at offset)
proc parse_partition(bs, off):
    let part = {}
    part["status"] = bs[off]
    part["bootable"] = (bs[off] & 128) != 0
    part["chs_start"] = decode_chs(bs, off + 1)
    part["type"] = bs[off + 4]
    part["type_name"] = partition_type_name(bs[off + 4])
    part["chs_end"] = decode_chs(bs, off + 5)
    part["lba_start"] = read_u32_le(bs, off + 8)
    part["sector_count"] = read_u32_le(bs, off + 12)
    part["size_bytes"] = read_u32_le(bs, off + 12) * 512
    return part

# Check if MBR has valid boot signature
proc is_valid_mbr(bs):
    if len(bs) < 512:
        return false
    let sig = read_u16_le(bs, 510)
    return sig == 43605

# Parse all 4 MBR partition entries
proc parse_mbr(bs):
    if not is_valid_mbr(bs):
        return nil
    let mbr = {}
    mbr["boot_code"] = 446
    mbr["signature"] = read_u16_le(bs, 510)
    let partitions = []
    push(partitions, parse_partition(bs, 446))
    push(partitions, parse_partition(bs, 462))
    push(partitions, parse_partition(bs, 478))
    push(partitions, parse_partition(bs, 494))
    mbr["partitions"] = partitions
    # Count active (non-empty) partitions
    let active = 0
    for i in range(4):
        if partitions[i]["type"] != 0:
            active = active + 1
    mbr["active_count"] = active
    return mbr

# Find the bootable (active) partition
proc find_bootable(mbr):
    let parts = mbr["partitions"]
    for i in range(4):
        if parts[i]["bootable"]:
            return parts[i]
    return nil

# Convert LBA to CHS (given disk geometry)
proc lba_to_chs(lba, heads_per_cylinder, sectors_per_track):
    let chs = {}
    chs["cylinder"] = (lba / (heads_per_cylinder * sectors_per_track)) | 0
    let temp = lba - chs["cylinder"] * heads_per_cylinder * sectors_per_track
    chs["head"] = (temp / sectors_per_track) | 0
    chs["sector"] = (temp - chs["head"] * sectors_per_track) + 1
    return chs

# Convert CHS to LBA (given disk geometry)
proc chs_to_lba(chs, heads_per_cylinder, sectors_per_track):
    return (chs["cylinder"] * heads_per_cylinder + chs["head"]) * sectors_per_track + chs["sector"] - 1
