# diskimg.sage — Sparse Bootable disk image builder for Sage
# Uses a dictionary of sectors to avoid giant memory allocations.

import io

let SECTOR_SIZE = 512
let MBR_SIGNATURE = 43605
let PARTITION_FAT16 = 6
let PARTITION_EFI = 239

# GPT Constants
let GPT_HEADER_LBA = 1
let GPT_ENTRY_LBA = 2
let GPT_ENTRY_SIZE = 128
let GPT_ENTRIES_PER_SECTOR = 4 # 512 / 128

# CRC32 table for UEFI
let CRC32_TABLE = [
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
    0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988, 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
    0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
    0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172, 0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
    0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
    0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924, 0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
    0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
    0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e, 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
    0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
    0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0, 0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
    0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
    0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a, 0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
    0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
    0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc, 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
    0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
    0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236, 0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
    0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
    0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38, 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
    0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
    0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2, 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
    0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
    0xb3667a2e, 0xc4614abb, 0x5d681b02, 0x2a6f2b94, 0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d
]

proc crc32_init():
    return 4294967295 # 0xFFFFFFFF
end

proc crc32_update(crc, b):
    return (crc >> 8) ^ CRC32_TABLE[(crc ^ b) & 255]
end

proc crc32_finalize(crc):
    return crc ^ 4294967295 # 0xFFFFFFFF
end

proc byte_to_int(b):
    if b < 0:
        return b + 256
    end
    return b
end

proc write_byte(img, offset, val):
    let sector_idx = int(offset / 512)
    let sector_off = int(offset % 512)
    let s_key = str(sector_idx)
    if not dict_has(img["sectors"], s_key):
        let s = []
        let i = 0
        for i in range(512):
            push(s, 0)
        end
        img["sectors"][s_key] = s
    end
    let s = img["sectors"][s_key]
    s[sector_off] = int(val % 256)
    return img
end

proc write_word_le(img, offset, val):
    write_byte(img, offset, val % 256)
    write_byte(img, offset + 1, (val / 256) % 256)
    return img
end

proc write_dword_le(img, offset, val):
    write_byte(img, offset, val & 255)
    write_byte(img, offset + 1, (val >> 8) & 255)
    write_byte(img, offset + 2, (val >> 16) & 255)
    write_byte(img, offset + 3, (val >> 24) & 255)
end

proc write_qword_le(img, off, val):
    write_dword_le(img, off, val & 4294967295)
    let high = int(val / 4294967296)
    write_dword_le(img, off + 4, high)
end

proc read_byte(img, offset):
    let sector_idx = int(offset / 512)
    let sector_off = int(offset % 512)
    let s_key = str(sector_idx)
    if not dict_has(img["sectors"], s_key):
        return 0
    end
    return img["sectors"][s_key][sector_off]
end

proc read_word_le(img, offset):
    return read_byte(img, offset) + read_byte(img, offset + 1) * 256
end

proc read_dword_le(img, offset):
    return read_word_le(img, offset) + read_word_le(img, offset + 2) * 65536
end

proc create_image(size_mb):
    let img = {
        "size_mb": size_mb,
        "sectors": {}
    }
    return img
end

proc write_mbr(img, bootloader_bytes):
    let boot_len = len(bootloader_bytes)
    if boot_len > 446:
        print("Warning: Bootloader too long for MBR")
    end
    let i = 0
    for i in range(boot_len):
        write_byte(img, i, bootloader_bytes[i])
    end
    # MBR Signature
    write_word_le(img, 510, MBR_SIGNATURE)
    return img
end

proc lba_to_chs(lba):
    let c = int(lba / (16 * 63))
    let h = int((lba / 63) % 16)
    let s = int((lba % 63) + 1)
    if c > 1023:
        c = 1023
        h = 15
        s = 63
    end
    let res = []
    push(res, h)
    push(res, s + (int(c / 256) * 64))
    push(res, c % 256)
    return res
end

proc create_partition(img, start_lba, size_lba, type_id, bootable):
    let slot = -1
    let i = 0
    for i in range(4):
        let entry_off = 446 + (i * 16)
        if read_byte(img, entry_off + 4) == 0:
            slot = i
            break
        end
    end
    if slot == -1:
        print("Error: no free MBR partition slot")
        return img
    end
    
    let base = 446 + (slot * 16)
    if bootable:
        write_byte(img, base, 128)
    else:
        write_byte(img, base, 0)
    end
    
    let chs_start = lba_to_chs(start_lba)
    write_byte(img, base + 1, chs_start[0])
    write_byte(img, base + 2, chs_start[1])
    write_byte(img, base + 3, chs_start[2])
    
    write_byte(img, base + 4, type_id)
    
    let chs_end = lba_to_chs(start_lba + size_lba - 1)
    write_byte(img, base + 5, chs_end[0])
    write_byte(img, base + 6, chs_end[1])
    write_byte(img, base + 7, chs_end[2])
    
    write_dword_le(img, base + 8, start_lba)
    write_dword_le(img, base + 12, size_lba)
    return img
end

proc format_fat16(img, partition_start_lba, partition_size_lba):
    let partition_start = partition_start_lba * 512
    # Simple FAT16 BPB
    write_byte(img, partition_start + 0, 235) # JMP
    write_byte(img, partition_start + 1, 60)
    write_byte(img, partition_start + 2, 144)
    let oem = "SAGE  OS"
    let i = 0
    for i in range(8):
        write_byte(img, partition_start + 3 + i, ord(oem[i]))
    end
    
    write_word_le(img, partition_start + 11, 512) # Bytes per sector
    write_byte(img, partition_start + 13, 8)     # Sectors per cluster
    write_word_le(img, partition_start + 14, 1)   # Reserved sectors
    write_byte(img, partition_start + 16, 2)     # Number of FATs
    write_word_le(img, partition_start + 17, 512) # Root entries
    
    if partition_size_lba < 65536:
        write_word_le(img, partition_start + 19, partition_size_lba)
    else:
        write_word_le(img, partition_start + 19, 0)
        write_dword_le(img, partition_start + 32, partition_size_lba)
    end
    
    write_byte(img, partition_start + 21, 248) # Media descriptor
    let fat_size = int((partition_size_lba / 256) + 1)
    write_word_le(img, partition_start + 22, fat_size)
    
    write_word_le(img, partition_start + 24, 63) # Sectors per track
    write_word_le(img, partition_start + 26, 16) # Heads
    
    # Write FATs
    let fat_start = 1
    let f = 0
    for f in range(2):
        let f_base = (partition_start_lba + fat_start + (f * fat_size)) * 512
        write_byte(img, f_base, 248) # F8
        write_byte(img, f_base + 1, 255) # FF
        write_byte(img, f_base + 2, 255) # FF
        write_byte(img, f_base + 3, 255) # FF
    end
    
    # Boot signature
    write_word_le(img, partition_start + 510, MBR_SIGNATURE)
    return img
end

proc fat16_layout(partition_start_lba, partition_size_lba):
    let reserved = 1
    let fat_size = int((partition_size_lba / 256) + 1)
    let fat_count = 2
    let root_entries = 512
    let root_size_sectors = int((root_entries * 32) / 512)
    
    let fat_start = partition_start_lba + reserved
    let root_start = fat_start + (fat_count * fat_size)
    let data_start = root_start + root_size_sectors
    
    let info = {}
    info["fat_start"] = fat_start
    info["fat_size"] = fat_size
    info["fat_count"] = fat_count
    info["root_start"] = root_start
    info["data_start"] = data_start
    info["data_offset"] = data_start * 512
    return info
end

proc pad_filename_83(filename):
    let name = ""
    let ext = ""
    let dot_pos = -1
    let i = 0
    for i in range(len(filename)):
        if filename[i] == ".":
            dot_pos = i
        end
    end
    if dot_pos >= 0:
        for i in range(dot_pos):
            name = name + filename[i]
        end
        for i in range(dot_pos + 1, len(filename)):
            ext = ext + filename[i]
        end
    end
    if dot_pos < 0:
        name = filename
    end
    
    let res = ""
    for i in range(8):
        if i < len(name):
            res = res + upper(name[i])
        else:
            res = res + " "
        end
    end
    for i in range(3):
        if i < len(ext):
            res = res + upper(ext[i])
        else:
            res = res + " "
        end
    end
    return res
end

proc write_fat_entry(img, fat_start_lba, fat_size, fat_count, cluster, value):
    let i = 0
    for i in range(fat_count):
        let fat_base = (fat_start_lba + (i * fat_size)) * 512
        write_word_le(img, fat_base + (cluster * 2), value)
    end
end

proc write_file_to_cluster(img, partition_start_lba, partition_size_lba, dir_cluster, filename, data_bytes):
    let layout = fat16_layout(partition_start_lba, partition_size_lba)
    let fat_start_lba = layout["fat_start"]
    let fat_size = layout["fat_size"]
    let fat_count = layout["fat_count"]
    
    let dir_start = 0
    if dir_cluster == 0:
        dir_start = layout["root_start"] * 512
    else:
        dir_start = layout["data_offset"] + ((dir_cluster - 2) * 4096)
    end
    
    let name83 = pad_filename_83(filename)
    let slot = -1
    let i = 0
    let max_slots = 512
    if dir_cluster != 0:
        max_slots = 128 # 4096 / 32
    end
    
    for i in range(max_slots):
        let entry_base = dir_start + (i * 32)
        if read_byte(img, entry_base) == 0:
            slot = i
            break
        end
    end
    if slot == -1:
        print("Error: directory full")
        return img
    end
    
    let entry = dir_start + (slot * 32)
    for i in range(11):
        write_byte(img, entry + i, ord(name83[i]))
    end
    
    let clusters_needed = int((len(data_bytes) + 4095) / 4096)
    let prev_cluster = -1
    let first_cluster = -1
    let data_written = 0
    
    let c = 2
    for c in range(2, 65536):
        if data_written >= len(data_bytes):
            break
        end
        
        let fat_base0 = fat_start_lba * 512
        if read_word_le(img, fat_base0 + (c * 2)) == 0:
            if first_cluster == -1:
                first_cluster = c
            end
            
            if prev_cluster != -1:
                write_fat_entry(img, fat_start_lba, fat_size, fat_count, prev_cluster, c)
            end
            
            # Write data to this cluster
            let cluster_data_start = layout["data_offset"] + ((c - 2) * 4096)
            let j = 0
            for j in range(4096):
                if data_written < len(data_bytes):
                    write_byte(img, cluster_data_start + j, data_bytes[data_written])
                    data_written = data_written + 1
                else:
                    break
                end
            end
            
            prev_cluster = c
            # Mark as EOF for now, will be overwritten if there's a next cluster
            write_fat_entry(img, fat_start_lba, fat_size, fat_count, c, 65535)
        end
    end
    
    write_word_le(img, entry + 26, first_cluster)
    write_dword_le(img, entry + 28, len(data_bytes))
    
    return img
end

proc write_file(img, partition_start_lba, partition_size_lba, filename, data_bytes):
    return write_file_to_cluster(img, partition_start_lba, partition_size_lba, 0, filename, data_bytes)
end

proc mkdir(img, partition_start_lba, partition_size_lba, parent_cluster, dirname):
    let layout = fat16_layout(partition_start_lba, partition_size_lba)
    let fat_start_lba = layout["fat_start"]
    let fat_size = layout["fat_size"]
    let fat_count = layout["fat_count"]
    
    let dir_start = 0
    if parent_cluster == 0:
        dir_start = layout["root_start"] * 512
    else:
        dir_start = layout["data_offset"] + ((parent_cluster - 2) * 4096)
    end
    
    let name83 = pad_filename_83(dirname)
    let slot = -1
    let i = 0
    let max_slots = 512
    if parent_cluster != 0:
        max_slots = 128
    end
    
    for i in range(max_slots):
        let entry_base = dir_start + (i * 32)
        if read_byte(img, entry_base) == 0:
            slot = i
            break
        end
    end
    
    let entry = dir_start + (slot * 32)
    for i in range(11):
        write_byte(img, entry + i, ord(name83[i]))
    end
    write_byte(img, entry + 11, 16) # ATTR_DIRECTORY
    
    let found_cluster = -1
    let c = 2
    let fat_base0 = fat_start_lba * 512
    for c in range(2, 65536):
        if read_word_le(img, fat_base0 + (c * 2)) == 0:
            found_cluster = c
            break
        end
    end
    
    write_fat_entry(img, fat_start_lba, fat_size, fat_count, found_cluster, 65535)
    write_word_le(img, entry + 26, found_cluster)
    write_word_le(img, entry + 28, 0)
    write_word_le(img, entry + 30, 0)
    
    let dir_offset = layout["data_offset"] + ((found_cluster - 2) * 4096)
    for i in range(4096):
        write_byte(img, dir_offset + i, 0)
    end
    
    return found_cluster
end

proc create_gpt_header(img, lba, backup_lba, entry_lba, last_lba, entry_count, entry_size, entries_crc):
    let hdr = lba * 512
    # Zero the header first
    for i in range(512):
        write_byte(img, hdr + i, 0)
    end
    
    let sig = "EFI PART"
    for i in range(8):
        write_byte(img, hdr + i, ord(sig[i]))
    end
    write_dword_le(img, hdr + 8, 65536) # Revision 1.0
    write_dword_le(img, hdr + 12, 92)   # Header size
    write_dword_le(img, hdr + 16, 0)    # CRC32 placeholder
    write_dword_le(img, hdr + 20, 0)    # Reserved
    write_qword_le(img, hdr + 24, lba)
    write_qword_le(img, hdr + 32, backup_lba)
    write_qword_le(img, hdr + 40, 34)   # First usable
    write_qword_le(img, hdr + 48, last_lba)
    # GUID at 56 (Disk GUID)
    for i in range(16):
        write_byte(img, hdr + 56 + i, (i * 13) % 256)
    end
    write_qword_le(img, hdr + 72, entry_lba)
    write_dword_le(img, hdr + 80, entry_count)
    write_dword_le(img, hdr + 84, entry_size)
    write_dword_le(img, hdr + 88, entries_crc)
    
    # Calculate Header CRC
    let crc = crc32_init()
    for i in range(92):
        crc = crc32_update(crc, read_byte(img, hdr + i))
    end
    write_dword_le(img, hdr + 16, crc32_finalize(crc))
end

proc create_gpt_image(size_mb):
    let img = create_image(size_mb)
    let total_sectors = int(size_mb * 1024 * 1024 / 512)
    
    # PMBR
    create_partition(img, 1, total_sectors - 1, 238, false)
    write_word_le(img, 510, MBR_SIGNATURE)
    
    # Empty Partition Entry Array (LBA 2 to 33)
    # We will fill it later in add_efi_partition, but for now we need its CRC.
    # Actually, let's just initialize it with zeros.
    let entry_bytes = 128 * 128
    let entry_sectors = 32
    for i in range(entry_sectors * 512):
        write_byte(img, 2 * 512 + i, 0)
    end
    
    let entries_crc = crc32_init()
    for i in range(entry_bytes):
        entries_crc = crc32_update(entries_crc, read_byte(img, 2 * 512 + i))
    end
    let final_entries_crc = crc32_finalize(entries_crc)
    
    create_gpt_header(img, 1, total_sectors - 1, 2, total_sectors - 34, 128, 128, final_entries_crc)
    # Backup header at the end
    create_gpt_header(img, total_sectors - 1, 1, total_sectors - 33, total_sectors - 34, 128, 128, final_entries_crc)
    
    # Backup partition entries
    for i in range(entry_sectors * 512):
        write_byte(img, (total_sectors - 33) * 512 + i, read_byte(img, 2 * 512 + i))
    end
    
    return img
end

proc get_efi_partition_info(img):
    let part_start_lba = 2048
    let total_sectors = int(img["size_mb"] * 1024 * 1024 / 512)
    let part_size_lba = total_sectors - part_start_lba - 34
    let res = {}
    res["start"] = part_start_lba
    res["size"] = part_size_lba
    return res
end

proc finalize_gpt(img):
    let size_mb = img["size_mb"]
    let total_sectors = int(size_mb * 1024 * 1024 / 512)
    
    # Calculate Partition Entry Array CRC
    let entry_bytes = 128 * 128
    let entries_crc = crc32_init()
    for i in range(entry_bytes):
        entries_crc = crc32_update(entries_crc, read_byte(img, 2 * 512 + i))
    end
    let final_entries_crc = crc32_finalize(entries_crc)
    
    # Update headers
    create_gpt_header(img, 1, total_sectors - 1, 2, total_sectors - 34, 128, 128, final_entries_crc)
    create_gpt_header(img, total_sectors - 1, 1, total_sectors - 33, total_sectors - 34, 128, 128, final_entries_crc)
    
    # Backup partition entries at the end
    let entry_sectors = 32
    for i in range(entry_sectors * 512):
        write_byte(img, (total_sectors - 33) * 512 + i, read_byte(img, 2 * 512 + i))
    end
end

proc add_efi_partition(img, efi_binary_bytes):
    # GPT Entry for EFI System Partition (at LBA 2)
    let entry_off = 2 * 512
    
    # EFI System Partition GUID: C12A7328-F81F-11D2-BA4B-00A0C93EC93B
    let efi_guid = [40, 115, 42, 193, 31, 248, 210, 17, 186, 75, 0, 160, 201, 62, 201, 59]
    let i = 0
    for i in range(16):
        write_byte(img, entry_off + i, efi_guid[i])
    end
    
    # Unique Partition GUID (randomish)
    for i in range(16):
        write_byte(img, entry_off + 16 + i, (i * 17) % 256)
    end
    
    let info = get_efi_partition_info(img)
    let part_start_lba = info["start"]
    let part_size_lba = info["size"]
    
    write_qword_le(img, entry_off + 32, part_start_lba)
    write_qword_le(img, entry_off + 40, part_start_lba + part_size_lba - 1)
    
    # Partition name "EFI System Partition" (UTF-16LE)
    let name = "EFI System Partition"
    for i in range(len(name)):
        write_byte(img, entry_off + 56 + (i * 2), ord(name[i]))
        write_byte(img, entry_off + 56 + (i * 2) + 1, 0)
    end
    
    # Format the partition as FAT16
    img = format_fat16(img, part_start_lba, part_size_lba)
    
    # Create /EFI/BOOT/ directory structure
    let efi_dir = mkdir(img, part_start_lba, part_size_lba, 0, "EFI")
    let boot_dir = mkdir(img, part_start_lba, part_size_lba, efi_dir, "BOOT")
    
    # Write the EFI binary to /EFI/BOOT/BOOTX64.EFI
    img = write_file_to_cluster(img, part_start_lba, part_size_lba, boot_dir, "BOOTX64.EFI", efi_binary_bytes)
    
    # Recalculate CRCs
    finalize_gpt(img)
    
    return img
end

proc save_image(img, path):
    let total_sectors = int(img["size_mb"] * 1024 * 1024 / 512)
    print("Saving sparse image to " + path + " (" + str(total_sectors) + " sectors)...")
    
    let zero_sector = []
    let i = 0
    for i in range(512):
        push(zero_sector, 0)
    end
    
    io.writebytes(path, []) # Create/clear file
    
    let buf = []
    let buf_count = 0
    let last_printed = 0
    
    for i in range(total_sectors):
        let s_key = str(i)
        if dict_has(img["sectors"], s_key):
            let s = img["sectors"][s_key]
            array_extend(buf, s)
        else:
            array_extend(buf, zero_sector)
        end
        buf_count = buf_count + 1
        
        # Flush every 1024 sectors (512KB)
        if buf_count >= 1024:
            io.appendbytes(path, buf)
            buf = []
            buf_count = 0
            if (int(i * 100 / total_sectors)) > last_printed:
                last_printed = int(i * 100 / total_sectors)
                print("Saving: " + str(last_printed) + "%")
            end
        end
    end
    
    if len(buf) > 0:
        io.appendbytes(path, buf)
    end
    
    print("Image saved successfully.")
    return true
end

proc create_bootable(kernel_path, output_path, size_mb):
    let kernel_bytes = io.readbytes(kernel_path)
    let img = create_gpt_image(size_mb)
    
    # Add EFI binary (placeholder or actual)
    # For now, let's just assume we want to write the kernel as BOOTX64.EFI if no separate bootloader is provided
    # But usually we have a separate one.
    
    img = add_efi_partition(img, kernel_bytes)
    save_image(img, output_path)
    return true
end
