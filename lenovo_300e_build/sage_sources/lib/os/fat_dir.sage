gc_disable()
# FAT directory traversal and file reading
# Works on raw byte arrays (disk images) using parsed boot sector info from os.fat

proc read_u16(bs, off):
    return bs[off] + bs[off + 1] * 256
end

proc read_u32(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216
end

# Directory entry attribute flags
let ATTR_READ_ONLY = 1
let ATTR_HIDDEN = 2
let ATTR_SYSTEM = 4
let ATTR_VOLUME_ID = 8
let ATTR_DIRECTORY = 16
let ATTR_ARCHIVE = 32
let ATTR_LFN = 15

# End-of-cluster markers
let FAT12_EOC = 4088
let FAT16_EOC = 65528
let FAT32_EOC = 268435448

# Read a single byte sector from the disk image
proc read_sector(disk, info, lba):
    let ss = info["sector_size"]
    let off = lba * ss
    let data = []
    for i in range(ss):
        if off + i < len(disk):
            push(data, disk[off + i])
        else:
            push(data, 0)
        end
    end
    return data
end

# Read an entire cluster from the disk image
proc read_cluster(disk, info, cluster):
    let spc = info["sectors_per_cluster"]
    let ss = info["sector_size"]
    let lba = info["first_data_sector"] + (cluster - 2) * spc
    let data = []
    for s in range(spc):
        let off = (lba + s) * ss
        for i in range(ss):
            if off + i < len(disk):
                push(data, disk[off + i])
            else:
                push(data, 0)
            end
        end
    end
    return data
end

# Read a FAT entry for a given cluster
proc read_fat_entry(disk, info, cluster):
    let ft = info["fat_type"]
    let fat_start = info["reserved_sectors"] * info["sector_size"]

    if ft == "FAT12":
        let off = fat_start + cluster + (cluster >> 1)
        if off + 1 >= len(disk):
            return 4095
        end
        let val = disk[off] + disk[off + 1] * 256
        if (cluster & 1) != 0:
            val = (val >> 4) & 4095
        else:
            val = val & 4095
        end
        return val
    end

    if ft == "FAT16":
        let off = fat_start + cluster * 2
        if off + 1 >= len(disk):
            return 65535
        end
        return read_u16(disk, off)
    end

    if ft == "FAT32":
        let off = fat_start + cluster * 4
        if off + 3 >= len(disk):
            return 268435455
        end
        return read_u32(disk, off) & 268435455
    end

    # FAT8
    let off = fat_start + cluster
    if off >= len(disk):
        return 255
    end
    return disk[off]
end

# Check if a FAT entry marks end of chain
proc is_end_of_chain(info, entry):
    let ft = info["fat_type"]
    if ft == "FAT12":
        return entry >= 4088
    end
    if ft == "FAT16":
        return entry >= 65528
    end
    if ft == "FAT32":
        return entry >= 268435448
    end
    return entry >= 248
end

# Walk the FAT chain starting from a cluster, returns list of clusters
proc follow_chain(disk, info, start_cluster):
    let chain = []
    let cluster = start_cluster
    let max_iter = info["total_clusters"] + 2
    let count = 0
    while not is_end_of_chain(info, cluster) and cluster >= 2 and count < max_iter:
        push(chain, cluster)
        cluster = read_fat_entry(disk, info, cluster)
        count = count + 1
    end
    return chain
end

# Read all data for a file given its starting cluster and size
proc read_file_data(disk, info, start_cluster, file_size):
    let chain = follow_chain(disk, info, start_cluster)
    let cluster_size = info["sectors_per_cluster"] * info["sector_size"]
    let data = []
    let remaining = file_size
    for i in range(len(chain)):
        let cdata = read_cluster(disk, info, chain[i])
        let to_copy = remaining
        if to_copy > cluster_size:
            to_copy = cluster_size
        end
        for j in range(to_copy):
            push(data, cdata[j])
        end
        remaining = remaining - to_copy
        if remaining <= 0:
            return data
        end
    end
    return data
end

# Extract 8.3 filename from a directory entry (11 bytes at offset)
proc read_83_name(bs, off):
    # First 8 bytes = name, last 3 = extension
    let name = ""
    for i in range(8):
        let c = bs[off + i]
        if c != 32:
            name = name + chr(c)
        end
    end
    let ext = ""
    for i in range(3):
        let c = bs[off + 8 + i]
        if c != 32:
            ext = ext + chr(c)
        end
    end
    if len(ext) > 0:
        return name + "." + ext
    end
    return name
end

# Convert 8.3 name to lowercase
proc name_to_lower(name):
    let result = ""
    for i in range(len(name)):
        let c = name[i]
        # A=65, Z=90
        let code = ord(c)
        if code >= 65 and code <= 90:
            result = result + chr(code + 32)
        else:
            result = result + c
        end
    end
    return result
end

# Parse a single 32-byte directory entry
proc parse_dir_entry(bs, off):
    if bs[off] == 0:
        return nil
    end
    if bs[off] == 229:
        return nil
    end
    let attrs = bs[off + 11]
    if attrs == 15:
        return nil
    end
    let entry = {}
    entry["raw_name"] = read_83_name(bs, off)
    entry["name"] = name_to_lower(read_83_name(bs, off))
    entry["attr"] = attrs
    entry["is_dir"] = (attrs & 16) != 0
    entry["is_file"] = (attrs & 16) == 0 and (attrs & 8) == 0
    entry["is_volume"] = (attrs & 8) != 0
    entry["is_hidden"] = (attrs & 2) != 0
    entry["is_system"] = (attrs & 4) != 0
    entry["is_readonly"] = (attrs & 1) != 0
    # Cluster: high 16 bits at offset 20, low 16 bits at offset 26
    let cluster_hi = read_u16(bs, off + 20)
    let cluster_lo = read_u16(bs, off + 26)
    entry["cluster"] = cluster_hi * 65536 + cluster_lo
    entry["size"] = read_u32(bs, off + 28)
    # Time/date
    let raw_time = read_u16(bs, off + 22)
    let raw_date = read_u16(bs, off + 24)
    entry["hour"] = (raw_time >> 11) & 31
    entry["minute"] = (raw_time >> 5) & 63
    entry["second"] = (raw_time & 31) * 2
    entry["year"] = ((raw_date >> 9) & 127) + 1980
    entry["month"] = (raw_date >> 5) & 15
    entry["day"] = raw_date & 31
    return entry
end

# Read root directory entries (FAT12/FAT16 fixed root)
proc read_root_dir_fixed(disk, info):
    let entries = []
    let root_start = (info["reserved_sectors"] + info["num_fats"] * info["fat_size"]) * info["sector_size"]
    let max_entries = info["root_entry_count"]
    for i in range(max_entries):
        let off = root_start + i * 32
        if off + 32 > len(disk):
            return entries
        end
        if disk[off] == 0:
            return entries
        end
        let entry = parse_dir_entry(disk, off)
        if entry != nil and not entry["is_volume"]:
            push(entries, entry)
        end
    end
    return entries
end

# Read directory entries from a cluster chain (FAT32 or subdirectory)
proc read_dir_from_chain(disk, info, start_cluster):
    let chain = follow_chain(disk, info, start_cluster)
    let cluster_size = info["sectors_per_cluster"] * info["sector_size"]
    let entries = []
    for ci in range(len(chain)):
        let cdata = read_cluster(disk, info, chain[ci])
        let num_entries = (cluster_size / 32) | 0
        for i in range(num_entries):
            let off = i * 32
            if cdata[off] == 0:
                return entries
            end
            let entry = parse_dir_entry(cdata, off)
            if entry != nil and not entry["is_volume"]:
                if entry["name"] != "." and entry["name"] != "..":
                    push(entries, entry)
                end
            end
        end
    end
    return entries
end

# List the root directory
proc list_root(disk, info):
    if info["fat_type"] == "FAT32":
        return read_dir_from_chain(disk, info, info["root_cluster"])
    end
    return read_root_dir_fixed(disk, info)
end

# List a subdirectory given its starting cluster
proc list_dir(disk, info, cluster):
    return read_dir_from_chain(disk, info, cluster)
end

# Read a file by directory entry
proc read_file(disk, info, entry):
    if entry["is_dir"]:
        return nil
    end
    return read_file_data(disk, info, entry["cluster"], entry["size"])
end

# Find an entry by name in a directory listing
proc find_entry(entries, name):
    let lower = name_to_lower(name)
    for i in range(len(entries)):
        if entries[i]["name"] == lower:
            return entries[i]
        end
    end
    return nil
end

# Resolve a path like "/subdir/file.txt" to a directory entry
proc resolve_path(disk, info, path):
    # Split path by /
    let parts = []
    let current = ""
    for i in range(len(path)):
        if path[i] == "/":
            if len(current) > 0:
                push(parts, current)
            end
            current = ""
        else:
            current = current + path[i]
        end
    end
    if len(current) > 0:
        push(parts, current)
    end
    if len(parts) == 0:
        return nil
    end
    # Walk from root
    let entries = list_root(disk, info)
    for i in range(len(parts) - 1):
        let entry = find_entry(entries, parts[i])
        if entry == nil:
            return nil
        end
        if not entry["is_dir"]:
            return nil
        end
        entries = list_dir(disk, info, entry["cluster"])
    end
    return find_entry(entries, parts[len(parts) - 1])
end

# Read a file by path
proc read_file_by_path(disk, info, path):
    let entry = resolve_path(disk, info, path)
    if entry == nil:
        return nil
    end
    return read_file(disk, info, entry)
end

# List a directory by path (returns entries or nil)
proc list_dir_by_path(disk, info, path):
    if path == "/" or path == "":
        return list_root(disk, info)
    end
    let entry = resolve_path(disk, info, path)
    if entry == nil:
        return nil
    end
    if not entry["is_dir"]:
        return nil
    end
    return list_dir(disk, info, entry["cluster"])
end
