gc_disable()
# FAT filesystem boot sector parser and utilities

proc read_u16(bs, off):
    return bs[off] + bs[off + 1] * 256
end

proc read_u32(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216
end

proc parse_boot_sector(bs):
    let sector_size = read_u16(bs, 11)
    let sectors_per_cluster = bs[13]
    let reserved_sectors = read_u16(bs, 14)
    let num_fats = bs[16]
    let root_entry_count = read_u16(bs, 17)
    let total_sectors_16 = read_u16(bs, 19)
    let media_type = bs[21]
    let fat_size_16 = read_u16(bs, 22)

    let total_sectors = total_sectors_16
    if total_sectors == 0:
        total_sectors = read_u32(bs, 32)
    end

    let fat_size = fat_size_16
    if fat_size == 0:
        fat_size = read_u32(bs, 36)
    end

    let root_dir_sectors = (((root_entry_count * 32) + (sector_size - 1)) / sector_size) | 0
    if root_entry_count == 0:
        root_dir_sectors = 0
    end

    let data_sectors = total_sectors - reserved_sectors - (num_fats * fat_size) - root_dir_sectors
    let total_clusters = (data_sectors / sectors_per_cluster) | 0

    let fat_type = "FAT16"
    if total_clusters < 128:
        fat_type = "FAT8"
    end
    if total_clusters >= 128:
        if total_clusters < 4085:
            fat_type = "FAT12"
        end
    end
    if total_clusters >= 4085:
        if total_clusters < 65525:
            fat_type = "FAT16"
        end
    end
    if total_clusters >= 65525:
        fat_type = "FAT32"
    end

    let root_cluster = 0
    if fat_type == "FAT32":
        root_cluster = read_u32(bs, 44)
    end

    let first_data_sector = reserved_sectors + (num_fats * fat_size) + root_dir_sectors

    let info = {}
    info["sector_size"] = sector_size
    info["sectors_per_cluster"] = sectors_per_cluster
    info["reserved_sectors"] = reserved_sectors
    info["num_fats"] = num_fats
    info["root_entry_count"] = root_entry_count
    info["total_sectors"] = total_sectors
    info["media_type"] = media_type
    info["fat_size"] = fat_size
    info["root_dir_sectors"] = root_dir_sectors
    info["data_sectors"] = data_sectors
    info["total_clusters"] = total_clusters
    info["fat_type"] = fat_type
    info["first_data_sector"] = first_data_sector
    info["root_cluster"] = root_cluster
    return info
end

proc cluster_to_lba(info, cluster):
    return info["first_data_sector"] + (cluster - 2) * info["sectors_per_cluster"]
end

proc fat_entry_offset(info, cluster):
    let result = {}
    let ft = info["fat_type"]
    if ft == "FAT12":
        result["byte_offset"] = cluster + (cluster >> 1)
        result["nibble"] = cluster & 1
    end
    if ft == "FAT16":
        result["byte_offset"] = cluster * 2
    end
    if ft == "FAT32":
        result["byte_offset"] = cluster * 4
    end
    if ft == "FAT8":
        result["byte_offset"] = cluster
    end
    return result
end
