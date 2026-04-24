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
    write_word_le(img, offset, val % 65536)
    write_word_le(img, offset + 2, (val / 65536) % 65536)
    return img
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
    
    # FATs
    let fat1_start = partition_start + 512
    let fat2_start = fat1_start + (fat_size * 512)
    
    write_byte(img, fat1_start, 248)
    write_byte(img, fat1_start + 1, 255)
    write_byte(img, fat1_start + 2, 255)
    write_byte(img, fat1_start + 3, 255)
    
    write_byte(img, fat2_start, 248)
    write_byte(img, fat2_start + 1, 255)
    write_byte(img, fat2_start + 2, 255)
    write_byte(img, fat2_start + 3, 255)
    
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

proc write_file_to_cluster(img, partition_start_lba, partition_size_lba, dir_cluster, filename, data_bytes):
    let layout = fat16_layout(partition_start_lba, partition_size_lba)
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
    let fat_base = layout["fat_start"] * 512
    
    let prev_cluster = -1
    let first_cluster = -1
    let data_written = 0
    
    let c = 2
    for c in range(2, 65536):
        if data_written >= len(data_bytes):
            break
        end
        
        let fat_entry = fat_base + (c * 2)
        if read_word_le(img, fat_entry) == 0:
            if first_cluster == -1:
                first_cluster = c
            end
            
            if prev_cluster != -1:
                write_word_le(img, fat_base + (prev_cluster * 2), c)
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
            write_word_le(img, fat_base + (c * 2), 65535)
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
    
    let fat_base = layout["fat_start"] * 512
    let found_cluster = -1
    let c = 2
    for c in range(2, 65536):
        if read_word_le(img, fat_base + (c * 2)) == 0:
            found_cluster = c
            break
        end
    end
    
    write_word_le(img, fat_base + (found_cluster * 2), 65535)
    write_word_le(img, entry + 26, found_cluster)
    write_word_le(img, entry + 28, 0)
    write_word_le(img, entry + 30, 0)
    
    let dir_offset = layout["data_offset"] + ((found_cluster - 2) * 4096)
    for i in range(4096):
        write_byte(img, dir_offset + i, 0)
    end
    
    return found_cluster
end

proc create_gpt_image(size_mb):
    let img = create_image(size_mb)
    # PMBR
    create_partition(img, 1, (size_mb * 1024 * 1024 / 512) - 1, 238, false)
    write_word_le(img, 510, MBR_SIGNATURE)
    
    # GPT Header
    let hdr = GPT_HEADER_LBA * 512
    let sig = "EFI PART"
    let i = 0
    for i in range(8):
        write_byte(img, hdr + i, ord(sig[i]))
    end
    write_dword_le(img, hdr + 8, 65536) # Revision 1.0
    write_dword_le(img, hdr + 12, 92)   # Header size
    # CRC32 would go at 16, but we omit for now
    write_dword_le(img, hdr + 24, 1)    # Current LBA
    write_dword_le(img, hdr + 32, (size_mb * 1024 * 1024 / 512) - 1) # Backup LBA
    write_dword_le(img, hdr + 40, 34)   # First usable LBA
    write_dword_le(img, hdr + 48, (size_mb * 1024 * 1024 / 512) - 34) # Last usable LBA
    # GUID at 56
    write_dword_le(img, hdr + 72, 2)    # Partition entries starting LBA
    write_dword_le(img, hdr + 80, 128)  # Number of partition entries
    write_dword_le(img, hdr + 84, 128)  # Size of each entry
    
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

proc add_efi_partition(img, efi_binary_bytes):
    # GPT Entry for EFI System Partition
    let entry_lba = GPT_ENTRY_LBA
    let entry_off = entry_lba * 512
    
    # EFI System Partition GUID: C12A7328-F81F-11D2-BA4B-00A0C93EC93B
    # (Mixed endian: 28 73 2A C1 1F F8 D2 11 BA 4B 00 A0 C9 3E C9 3B)
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
    
    write_dword_le(img, entry_off + 32, part_start_lba)
    write_dword_le(img, entry_off + 40, part_start_lba + part_size_lba - 1)
    
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
