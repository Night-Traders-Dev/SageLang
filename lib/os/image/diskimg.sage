gc_disable()

# diskimg.sage — Bootable disk image builder for Sage
# Supports MBR, GPT, FAT16 formatting, and file/kernel writing.

let SECTOR_SIZE = 512
let MBR_SIGNATURE = 43605
let PARTITION_FAT16 = 6
let PARTITION_FAT32 = 12
let PARTITION_EFI = 239
let GPT_HEADER_LBA = 1
let GPT_ENTRY_SIZE = 128
let GPT_ENTRIES_PER_SECTOR = 4
let FAT16_RESERVED_SECTORS = 1
let FAT16_ROOT_ENTRIES = 512
let FAT16_SECTORS_PER_CLUSTER = 4
let FAT16_NUM_FATS = 2

proc byte_to_int(b):
    if b < 0:
        return b + 256
    end
    return b
end

proc write_byte(image, offset, val):
    image[offset] = val % 256
    return image
end

proc write_word_le(image, offset, val):
    image[offset] = val % 256
    image[offset + 1] = (val / 256) % 256
    return image
end

proc write_dword_le(image, offset, val):
    image[offset] = val % 256
    image[offset + 1] = (val / 256) % 256
    image[offset + 2] = (val / 65536) % 256
    image[offset + 3] = (val / 16777216) % 256
    return image
end

proc read_byte(image, offset):
    return byte_to_int(image[offset])
end

proc read_word_le(image, offset):
    let lo = byte_to_int(image[offset])
    let hi = byte_to_int(image[offset + 1])
    return lo + hi * 256
end

proc read_dword_le(image, offset):
    let b0 = byte_to_int(image[offset])
    let b1 = byte_to_int(image[offset + 1])
    let b2 = byte_to_int(image[offset + 2])
    let b3 = byte_to_int(image[offset + 3])
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

proc create_image(size_mb):
    let total_bytes = size_mb * 1024 * 1024
    let image = []
    let i = 0
    for i in range(total_bytes):
        image = image + [0]
    end
    return image
end

proc write_mbr(image, bootloader_bytes):
    let i = 0
    let boot_len = len(bootloader_bytes)
    if boot_len > 446:
        boot_len = 446
    end
    for i in range(boot_len):
        image[i] = bootloader_bytes[i]
    end
    image[510] = 85
    image[511] = 170
    return image
end

proc lba_to_chs(lba):
    let heads = 16
    let sectors_per_track = 63
    let c = lba / (heads * sectors_per_track)
    let rem = lba % (heads * sectors_per_track)
    let h = rem / sectors_per_track
    let s = (rem % sectors_per_track) + 1
    if c > 1023:
        c = 1023
    end
    let result = []
    result = result + [h]
    result = result + [s + ((c / 256) * 64)]
    result = result + [c % 256]
    return result
end

proc create_partition(image, start_lba, size_lba, type_id, bootable):
    let slot = -1
    let i = 0
    for i in range(4):
        let entry_off = 446 + i * 16
        if image[entry_off + 4] == 0:
            slot = i
            break
        end
    end
    if slot == -1:
        print("Error: no free MBR partition slot")
        return image
    end
    let base = 446 + slot * 16
    if bootable:
        image[base] = 128
    end
    if bootable == false:
        image[base] = 0
    end
    let start_chs = lba_to_chs(start_lba)
    image[base + 1] = start_chs[0]
    image[base + 2] = start_chs[1]
    image[base + 3] = start_chs[2]
    image[base + 4] = type_id
    let end_lba = start_lba + size_lba - 1
    let end_chs = lba_to_chs(end_lba)
    image[base + 5] = end_chs[0]
    image[base + 6] = end_chs[1]
    image[base + 7] = end_chs[2]
    write_dword_le(image, base + 8, start_lba)
    write_dword_le(image, base + 12, size_lba)
    image[510] = 85
    image[511] = 170
    return image
end

proc format_fat16(image, partition_start, partition_size):
    let base = partition_start * SECTOR_SIZE
    image[base + 0] = 235
    image[base + 1] = 60
    image[base + 2] = 144
    let oem = "SAGEOS  "
    let i = 0
    for i in range(8):
        image[base + 3 + i] = ord(oem[i])
    end
    write_word_le(image, base + 11, SECTOR_SIZE)
    image[base + 13] = FAT16_SECTORS_PER_CLUSTER
    write_word_le(image, base + 14, FAT16_RESERVED_SECTORS)
    image[base + 16] = FAT16_NUM_FATS
    write_word_le(image, base + 17, FAT16_ROOT_ENTRIES)
    if partition_size < 65536:
        write_word_le(image, base + 19, partition_size)
    end
    if partition_size >= 65536:
        write_word_le(image, base + 19, 0)
        write_dword_le(image, base + 32, partition_size)
    end
    image[base + 21] = 248
    let fat_size = (partition_size / FAT16_SECTORS_PER_CLUSTER + 2) / 256 + 1
    write_word_le(image, base + 22, fat_size)
    write_word_le(image, base + 24, 63)
    write_word_le(image, base + 26, 16)
    write_dword_le(image, base + 28, partition_start)
    image[base + 510] = 85
    image[base + 511] = 170
    let fat_off = base + FAT16_RESERVED_SECTORS * SECTOR_SIZE
    image[fat_off + 0] = 248
    image[fat_off + 1] = 255
    image[fat_off + 2] = 255
    image[fat_off + 3] = 255
    let fat2_off = fat_off + fat_size * SECTOR_SIZE
    image[fat2_off + 0] = 248
    image[fat2_off + 1] = 255
    image[fat2_off + 2] = 255
    image[fat2_off + 3] = 255
    return image
end

proc fat16_layout(partition_start, partition_size):
    let base = partition_start * SECTOR_SIZE
    let fat_size = (partition_size / FAT16_SECTORS_PER_CLUSTER + 2) / 256 + 1
    let root_dir_offset = base + (FAT16_RESERVED_SECTORS + FAT16_NUM_FATS * fat_size) * SECTOR_SIZE
    let root_dir_size = FAT16_ROOT_ENTRIES * 32
    let data_offset = root_dir_offset + root_dir_size
    let info = {}
    info["fat_offset"] = base + FAT16_RESERVED_SECTORS * SECTOR_SIZE
    info["fat_size"] = fat_size
    info["root_dir_offset"] = root_dir_offset
    info["data_offset"] = data_offset
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
        name = filename[0:dot_pos]
        ext = filename[dot_pos + 1:len(filename)]
    end
    if dot_pos < 0:
        name = filename
    end
    let result = ""
    for i in range(8):
        if i < len(name):
            result = result + name[i]
        end
        if i >= len(name):
            result = result + " "
        end
    end
    for i in range(3):
        if i < len(ext):
            result = result + ext[i]
        end
        if i >= len(ext):
            result = result + " "
        end
    end
    return result
end

proc write_file(image, partition_start, partition_size, filename, data):
    let layout = fat16_layout(partition_start, partition_size)
    let root_off = layout["root_dir_offset"]
    let data_off = layout["data_offset"]
    let fat_off = layout["fat_offset"]
    let slot = -1
    let i = 0
    for i in range(FAT16_ROOT_ENTRIES):
        let entry_base = root_off + i * 32
        if image[entry_base] == 0:
            slot = i
            break
        end
    end
    if slot == -1:
        print("Error: root directory full")
        return image
    end
    let entry_base = root_off + slot * 32
    let name83 = pad_filename_83(filename)
    for i in range(11):
        image[entry_base + i] = ord(name83[i])
    end
    image[entry_base + 11] = 32
    let data_len = len(data)
    let clusters_needed = data_len / (FAT16_SECTORS_PER_CLUSTER * SECTOR_SIZE) + 1
    let first_cluster = 2
    let c = 2
    let found = false
    for c in range(2, 2 + clusters_needed + 100):
        let fat_entry = fat_off + c * 2
        if read_word_le(image, fat_entry) == 0:
            if found == false:
                first_cluster = c
                found = true
            end
            break
        end
    end
    write_word_le(image, entry_base + 26, first_cluster)
    write_dword_le(image, entry_base + 28, data_len)
    let cluster = first_cluster
    let written = 0
    for c in range(clusters_needed):
        let cluster_off = data_off + (cluster - 2) * FAT16_SECTORS_PER_CLUSTER * SECTOR_SIZE
        let chunk = FAT16_SECTORS_PER_CLUSTER * SECTOR_SIZE
        for i in range(chunk):
            if written + i < data_len:
                image[cluster_off + i] = data[written + i]
            end
        end
        written = written + chunk
        if c < clusters_needed - 1:
            let next_cluster = cluster + 1
            write_word_le(image, fat_off + cluster * 2, next_cluster)
            cluster = next_cluster
        end
        if c == clusters_needed - 1:
            write_word_le(image, fat_off + cluster * 2, 65535)
        end
    end
    return image
end

proc write_kernel(image, partition_start, partition_size, kernel_bytes):
    return write_file(image, partition_start, partition_size, "KERNEL  BIN", kernel_bytes)
end

proc save_image(image, path):
    let data = ""
    let i = 0
    for i in range(len(image)):
        data = data + chr(image[i])
    end
    writefile(path, data)
    return true
end

proc create_bootable(kernel_path, output_path, size_mb):
    let kernel_data_str = readfile(kernel_path)
    let kernel_bytes = []
    let i = 0
    for i in range(len(kernel_data_str)):
        kernel_bytes = kernel_bytes + [ord(kernel_data_str[i])]
    end
    let image = create_image(size_mb)
    let boot = []
    for i in range(446):
        boot = boot + [0]
    end
    image = write_mbr(image, boot)
    let total_sectors = size_mb * 1024 * 1024 / SECTOR_SIZE
    let start_lba = 2048
    let part_size = total_sectors - start_lba
    image = create_partition(image, start_lba, part_size, PARTITION_FAT16, true)
    image = format_fat16(image, start_lba, part_size)
    image = write_kernel(image, start_lba, part_size, kernel_bytes)
    save_image(image, output_path)
    return true
end

proc create_gpt_image(size_mb):
    let image = create_image(size_mb)
    let i = 0
    image[0] = 238
    image[510] = 85
    image[511] = 170
    let pmbr_base = 446
    image[pmbr_base] = 0
    image[pmbr_base + 4] = 238
    write_dword_le(image, pmbr_base + 8, 1)
    let total_sectors = size_mb * 1024 * 1024 / SECTOR_SIZE
    write_dword_le(image, pmbr_base + 12, total_sectors - 1)
    let hdr = GPT_HEADER_LBA * SECTOR_SIZE
    let sig = "EFI PART"
    for i in range(8):
        image[hdr + i] = ord(sig[i])
    end
    write_dword_le(image, hdr + 8, 65536)
    write_dword_le(image, hdr + 12, 92)
    write_dword_le(image, hdr + 24, 1)
    write_dword_le(image, hdr + 32, total_sectors - 1)
    write_dword_le(image, hdr + 40, 34)
    write_dword_le(image, hdr + 48, total_sectors - 34)
    write_dword_le(image, hdr + 72, 2)
    write_dword_le(image, hdr + 80, 128)
    write_dword_le(image, hdr + 84, 128)
    return image
end

proc add_efi_partition(image, efi_binary):
    let hdr = GPT_HEADER_LBA * SECTOR_SIZE
    let entry_lba = 2
    let entry_base = entry_lba * SECTOR_SIZE
    let efi_type_guid = [40, 115, 42, 193, 31, 248, 210, 17, 186, 75, 0, 160, 201, 62, 201, 59]
    let i = 0
    for i in range(16):
        image[entry_base + i] = efi_type_guid[i]
    end
    for i in range(16):
        image[entry_base + 16 + i] = (i + 1) % 256
    end
    let part_start_lba = 2048
    write_dword_le(image, entry_base + 32, part_start_lba)
    let efi_size_sectors = len(efi_binary) / SECTOR_SIZE + 1
    let part_end_lba = part_start_lba + efi_size_sectors
    write_dword_le(image, entry_base + 40, part_end_lba)
    let data_off = part_start_lba * SECTOR_SIZE
    for i in range(len(efi_binary)):
        image[data_off + i] = efi_binary[i]
    end
    return image
end
