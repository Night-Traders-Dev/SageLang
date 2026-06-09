gc_disable()
# MBR (Master Boot Record) partition table parser
# Parses the 512-byte MBR structure including partition entries and boot signature

@inline
proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256
end

@inline
proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216
end

comptime:
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
end

proc partition_type_name(t):
    if t == 0:
        return "Empty"
    end
    if t == 1:
        return "FAT12"
    end
    if t == 4:
        return "FAT16 (<32MB)"
    end
    if t == 5:
        return "Extended"
    end
    if t == 6:
        return "FAT16 (>32MB)"
    end
    if t == 7:
        return "NTFS/exFAT"
    end
    if t == 11:
        return "FAT32"
    end
    if t == 12:
        return "FAT32 (LBA)"
    end
    if t == 14:
        return "FAT16 (LBA)"
    end
    if t == 15:
        return "Extended (LBA)"
    end
    if t == 130:
        return "Linux swap"
    end
    if t == 131:
        return "Linux"
    end
    if t == 142:
        return "Linux LVM"
    end
    if t == 238:
        return "EFI GPT protective"
    end
    if t == 239:
        return "EFI System"
    end
    return "Unknown"
end

# Decode CHS (Cylinder-Head-Sector) address from 3 bytes
proc decode_chs(bs, off):
    let chs = {}
    chs["head"] = bs[off]
    chs["sector"] = bs[off + 1] & 63
    chs["cylinder"] = ((bs[off + 1] & 192) << 2) + bs[off + 2]
    return chs
end

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
end

# Check if MBR has valid boot signature
proc is_valid_mbr(bs):
    if len(bs) < 512:
        return false
    end
    let sig = read_u16_le(bs, 510)
    return sig == 43605
end

# Parse all 4 MBR partition entries
proc parse_mbr(bs):
    if not is_valid_mbr(bs):
        return nil
    end
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
        end
    end
    mbr["active_count"] = active
    return mbr
end

# Find the bootable (active) partition
proc find_bootable(mbr):
    let parts = mbr["partitions"]
    for i in range(4):
        if parts[i]["bootable"]:
            return parts[i]
        end
    end
    return nil
end

# Convert LBA to CHS (given disk geometry)
proc lba_to_chs(lba, heads_per_cylinder, sectors_per_track):
    let chs = {}
    chs["cylinder"] = (lba / (heads_per_cylinder * sectors_per_track)) | 0
    let temp = lba - chs["cylinder"] * heads_per_cylinder * sectors_per_track
    chs["head"] = (temp / sectors_per_track) | 0
    chs["sector"] = (temp - chs["head"] * sectors_per_track) + 1
    return chs
end

# Convert CHS to LBA (given disk geometry)
proc chs_to_lba(chs, heads_per_cylinder, sectors_per_track):
    return (chs["cylinder"] * heads_per_cylinder + chs["head"]) * sectors_per_track + chs["sector"] - 1
end

# ========== Extended Partitions ==========

@inline
proc is_extended(partition):
    let t = partition["type"]
    return t == 5 or t == 15 or t == 133
end

proc parse_extended_partitions(bs, ext_partition):
    let logicals = []
    let ext_start = ext_partition["lba_start"]
    let ebr_lba = ext_start
    let max_iter = 128
    let iter = 0
    while ebr_lba > 0 and iter < max_iter:
        let off = ebr_lba * 512
        if off + 512 > len(bs):
            break
        end
        # EBR has same structure as MBR: 2 partition entries at offset 446
        let p1 = parse_partition(bs, off + 446)
        let p2 = parse_partition(bs, off + 462)
        # First entry: logical partition (relative to EBR)
        if p1["type"] != 0:
            let logical = {}
            logical["type"] = p1["type"]
            logical["type_name"] = partition_type_name(p1["type"])
            logical["bootable"] = p1["bootable"]
            logical["lba_start"] = ebr_lba + p1["lba_start"]
            logical["sector_count"] = p1["sector_count"]
            push(logicals, logical)
        end
        # Second entry: next EBR (relative to extended partition start)
        if p2["type"] != 0 and p2["lba_start"] > 0:
            ebr_lba = ext_start + p2["lba_start"]
        else:
            ebr_lba = 0
        end
        iter = iter + 1
    end
    return logicals
end

# Get all partitions including logical partitions in extended
proc get_all_partitions(bs):
    let mbr = parse_mbr(bs)
    let all_parts = []
    for i in range(len(mbr["partitions"])):
        let p = mbr["partitions"][i]
        if p["type"] == 0:
            continue
        end
        if is_extended(p):
            let logicals = parse_extended_partitions(bs, p)
            for j in range(len(logicals)):
                push(all_parts, logicals[j])
            end
        else:
            push(all_parts, p)
        end
    end
    return all_parts
end

# ========== MBR Writer ==========

@inline
proc _write_u16_le(bs, off, val):
    bs[off] = val & 255
    bs[off + 1] = (val >> 8) & 255
end

@inline
proc _write_u32_le(bs, off, val):
    bs[off] = val & 255
    bs[off + 1] = (val >> 8) & 255
    bs[off + 2] = (val >> 16) & 255
    bs[off + 3] = (val >> 24) & 255
end

proc create_mbr():
    let mbr = []
    for i in range(512):
        push(mbr, 0)
    end
    # Boot signature
    mbr[510] = 85
    mbr[511] = 170
    return mbr
end

proc write_partition(mbr, index, bootable, ptype, lba_start, sector_count):
    let off = 446 + index * 16
    if bootable:
        mbr[off] = 128
    else:
        mbr[off] = 0
    end
    # CHS start/end (use LBA mode: FE FF FF)
    mbr[off + 1] = 254
    mbr[off + 2] = 255
    mbr[off + 3] = 255
    mbr[off + 4] = ptype
    mbr[off + 5] = 254
    mbr[off + 6] = 255
    mbr[off + 7] = 255
    _write_u32_le(mbr, off + 8, lba_start)
    _write_u32_le(mbr, off + 12, sector_count)
end

proc write_boot_code(mbr, code):
    let max_len = 440
    if len(code) < max_len:
        max_len = len(code)
    end
    for i in range(max_len):
        mbr[i] = code[i]
    end
end
