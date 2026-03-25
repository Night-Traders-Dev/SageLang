gc_disable()

# iso.sage — ISO 9660 image creation for CD/USB boot
# Supports El Torito boot records for bootable media.

let ISO_SECTOR = 2048
let SYSTEM_AREA_SIZE = 32768
let VOLUME_DESC_PRIMARY = 1
let VOLUME_DESC_BOOT = 0
let VOLUME_DESC_TERMINATOR = 255
let EL_TORITO_SPEC = "EL TORITO SPECIFICATION"
let BOOT_CATALOG_SECTOR = 20
let BOOT_IMAGE_SECTOR = 21

proc write_byte_iso(data, offset, val):
    data[offset] = val % 256
    return data

proc write_word_le_iso(data, offset, val):
    data[offset] = val % 256
    data[offset + 1] = (val / 256) % 256
    return data

proc write_word_be_iso(data, offset, val):
    data[offset] = (val / 256) % 256
    data[offset + 1] = val % 256
    return data

proc write_word_both(data, offset, val):
    write_word_le_iso(data, offset, val)
    write_word_be_iso(data, offset + 2, val)
    return data

proc write_dword_le_iso(data, offset, val):
    data[offset] = val % 256
    data[offset + 1] = (val / 256) % 256
    data[offset + 2] = (val / 65536) % 256
    data[offset + 3] = (val / 16777216) % 256
    return data

proc write_dword_be_iso(data, offset, val):
    data[offset] = (val / 16777216) % 256
    data[offset + 1] = (val / 65536) % 256
    data[offset + 2] = (val / 256) % 256
    data[offset + 3] = val % 256
    return data

proc write_dword_both(data, offset, val):
    write_dword_le_iso(data, offset, val)
    write_dword_be_iso(data, offset + 4, val)
    return data

proc write_string_pad(data, offset, s, pad_len):
    let i = 0
    for i in range(pad_len):
        if i < len(s):
            data[offset + i] = ord(s[i])
        if i >= len(s):
            data[offset + i] = 32
    return data

proc create_iso(label):
    let iso = {}
    iso["label"] = label
    iso["files"] = []
    iso["boot_binary"] = nil
    iso["volume_id"] = label
    return iso

proc add_file(iso, path, data):
    let entry = {}
    entry["path"] = path
    entry["data"] = data
    let files = iso["files"]
    files = files + [entry]
    iso["files"] = files
    return iso

proc add_boot_record(iso, boot_binary):
    iso["boot_binary"] = boot_binary
    return iso

proc set_volume_id(iso, name):
    iso["volume_id"] = name
    return iso

proc serialize(iso):
    let file_list = iso["files"]
    let num_files = len(file_list)
    let data_start_sector = 22 + num_files
    let total_data_sectors = 0
    let i = 0
    for i in range(num_files):
        let f = file_list[i]
        let fdata = f["data"]
        total_data_sectors = total_data_sectors + len(fdata) / ISO_SECTOR + 1
    let total_sectors = data_start_sector + total_data_sectors + 1
    let total_bytes = total_sectors * ISO_SECTOR
    let img = []
    for i in range(total_bytes):
        img = img + [0]
    let pvd_off = 16 * ISO_SECTOR
    img[pvd_off] = VOLUME_DESC_PRIMARY
    let cd001 = "CD001"
    let j = 0
    for j in range(5):
        img[pvd_off + 1 + j] = ord(cd001[j])
    img[pvd_off + 6] = 1
    write_string_pad(img, pvd_off + 8, "        ", 32)
    let vol_id = iso["volume_id"]
    write_string_pad(img, pvd_off + 40, vol_id, 32)
    write_dword_both(img, pvd_off + 80, total_sectors)
    write_word_both(img, pvd_off + 120, 1)
    write_word_both(img, pvd_off + 124, 1)
    write_word_both(img, pvd_off + 128, ISO_SECTOR)
    let root_dir_sector = 19
    let root_rec_off = pvd_off + 156
    img[root_rec_off] = 34
    write_dword_both(img, root_rec_off + 2, root_dir_sector)
    write_dword_both(img, root_rec_off + 10, ISO_SECTOR)
    img[root_rec_off + 25] = 2
    img[root_rec_off + 32] = 1
    img[root_rec_off + 33] = 0
    if iso["boot_binary"] != nil:
        let bvd_off = 17 * ISO_SECTOR
        img[bvd_off] = VOLUME_DESC_BOOT
        for j in range(5):
            img[bvd_off + 1 + j] = ord(cd001[j])
        img[bvd_off + 6] = 1
        let eltorito = EL_TORITO_SPEC
        for j in range(len(eltorito)):
            img[bvd_off + 7 + j] = ord(eltorito[j])
        write_dword_le_iso(img, bvd_off + 71, BOOT_CATALOG_SECTOR)
        let cat_off = BOOT_CATALOG_SECTOR * ISO_SECTOR
        img[cat_off] = 1
        img[cat_off + 1] = 0
        img[cat_off + 28] = 170
        img[cat_off + 29] = 85
        img[cat_off + 30] = 85
        img[cat_off + 31] = 170
        let init_entry = cat_off + 32
        img[init_entry] = 136
        img[init_entry + 1] = 0
        write_word_le_iso(img, init_entry + 2, 1)
        write_word_le_iso(img, init_entry + 6, 4)
        write_dword_le_iso(img, init_entry + 8, BOOT_IMAGE_SECTOR)
        let boot_data = iso["boot_binary"]
        let boot_off = BOOT_IMAGE_SECTOR * ISO_SECTOR
        for j in range(len(boot_data)):
            img[boot_off + j] = boot_data[j]
    let term_off = 18 * ISO_SECTOR
    img[term_off] = VOLUME_DESC_TERMINATOR
    for j in range(5):
        img[term_off + 1 + j] = ord(cd001[j])
    img[term_off + 6] = 1
    let root_off = root_dir_sector * ISO_SECTOR
    img[root_off] = 34
    write_dword_both(img, root_off + 2, root_dir_sector)
    write_dword_both(img, root_off + 10, ISO_SECTOR)
    img[root_off + 25] = 2
    img[root_off + 32] = 1
    img[root_off + 33] = 0
    let cur_sector = data_start_sector
    let dir_pos = 34
    for i in range(num_files):
        let f = file_list[i]
        let fdata = f["data"]
        let fpath = f["path"]
        let flen = len(fdata)
        let fsectors = flen / ISO_SECTOR + 1
        let data_offset = cur_sector * ISO_SECTOR
        for j in range(flen):
            img[data_offset + j] = fdata[j]
        let rec_off = root_off + dir_pos
        let name_len = len(fpath)
        let rec_len = 33 + name_len
        if rec_len % 2 == 1:
            rec_len = rec_len + 1
        img[rec_off] = rec_len
        write_dword_both(img, rec_off + 2, cur_sector)
        write_dword_both(img, rec_off + 10, flen)
        img[rec_off + 25] = 0
        img[rec_off + 32] = name_len
        for j in range(name_len):
            img[rec_off + 33 + j] = ord(fpath[j])
        dir_pos = dir_pos + rec_len
        cur_sector = cur_sector + fsectors
    return img

proc save(iso_img, path):
    let data = ""
    let i = 0
    for i in range(len(iso_img)):
        data = data + chr(iso_img[i])
    writefile(path, data)
    return true

proc create_bootable_iso(kernel_path, output_path, label):
    let kernel_str = readfile(kernel_path)
    let kernel_bytes = []
    let i = 0
    for i in range(len(kernel_str)):
        kernel_bytes = kernel_bytes + [ord(kernel_str[i])]
    let iso = create_iso(label)
    iso = add_boot_record(iso, kernel_bytes)
    iso = add_file(iso, "KERNEL.BIN", kernel_bytes)
    let img = serialize(iso)
    save(img, output_path)
    return true
