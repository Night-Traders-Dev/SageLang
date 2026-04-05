gc_disable()

# ext.sage - ext2/ext3/ext4 filesystem support
# Provides parsing, reading, writing, and formatting for ext family filesystems

# Constants
let EXT_MAGIC = 61267
let INODE_SIZE_EXT2 = 128
let INODE_SIZE_EXT4 = 256
let BLOCK_SIZE = 4096
let SUPERBLOCK_OFFSET = 1024
let SUPERBLOCK_SIZE = 1024
let GROUP_DESC_SIZE = 32
let DIR_ENTRY_HEADER = 8
let EXTENT_MAGIC = 62218
let ROOT_INODE = 2

# Inode type flags
let S_IFREG = 32768
let S_IFDIR = 16384
let S_IFLNK = 40960
let S_IFIFO = 4096
let S_IFSOCK = 49152
let S_IFBLK = 24576
let S_IFCHR = 8192

# Directory entry file types
let FT_UNKNOWN = 0
let FT_REG_FILE = 1
let FT_DIR = 2
let FT_CHRDEV = 3
let FT_BLKDEV = 4
let FT_FIFO = 5
let FT_SOCK = 6
let FT_SYMLINK = 7

# Number of direct block pointers in inode
let DIRECT_BLOCKS = 12
let INDIRECT_BLOCK_IDX = 12
let DOUBLE_INDIRECT_IDX = 13
let TRIPLE_INDIRECT_IDX = 14
let PTRS_PER_BLOCK = 1024

proc _read_u16(bytes, off):
    let b0 = bytes[off]
    let b1 = bytes[off + 1]
    return b0 + b1 * 256
end

proc _read_u32(bytes, off):
    let b0 = bytes[off]
    let b1 = bytes[off + 1]
    let b2 = bytes[off + 2]
    let b3 = bytes[off + 3]
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

proc _write_u16(bytes, off, val):
    bytes[off] = val % 256
    bytes[off + 1] = (val / 256) % 256
end

proc _write_u32(bytes, off, val):
    bytes[off] = val % 256
    bytes[off + 1] = (val / 256) % 256
    bytes[off + 2] = (val / 65536) % 256
    bytes[off + 3] = (val / 16777216) % 256
end

proc _zero_bytes(count):
    let result = []
    let i = 0
    while i < count:
        result = result + [0]
        i = i + 1
    end
    return result
end

proc parse_superblock(bytes, offset):
    # Parse ext2/ext3/ext4 superblock at given offset (typically 1024)
    let sb = {}
    sb["inodes_count"] = _read_u32(bytes, offset + 0)
    sb["blocks_count"] = _read_u32(bytes, offset + 4)
    sb["r_blocks_count"] = _read_u32(bytes, offset + 8)
    sb["free_blocks_count"] = _read_u32(bytes, offset + 12)
    sb["free_inodes_count"] = _read_u32(bytes, offset + 16)
    sb["first_data_block"] = _read_u32(bytes, offset + 20)
    sb["log_block_size"] = _read_u32(bytes, offset + 24)
    sb["block_size"] = 1024 * (2 ** sb["log_block_size"])
    sb["blocks_per_group"] = _read_u32(bytes, offset + 32)
    sb["inodes_per_group"] = _read_u32(bytes, offset + 40)
    sb["magic"] = _read_u16(bytes, offset + 56)
    sb["state"] = _read_u16(bytes, offset + 58)
    sb["errors"] = _read_u16(bytes, offset + 60)
    sb["rev_level"] = _read_u32(bytes, offset + 76)
    sb["first_ino"] = _read_u32(bytes, offset + 84)
    sb["inode_size"] = _read_u16(bytes, offset + 88)
    sb["feature_compat"] = _read_u32(bytes, offset + 92)
    sb["feature_incompat"] = _read_u32(bytes, offset + 96)
    sb["feature_ro_compat"] = _read_u32(bytes, offset + 100)
    if sb["magic"] != EXT_MAGIC:
        print("Warning: invalid ext magic " + str(sb["magic"]))
    end
    # Detect ext version
    let has_journal = (sb["feature_compat"] / 4) % 2
    let has_extents = (sb["feature_incompat"] / 64) % 2
    if has_extents:
        sb["version"] = "ext4"
    elif has_journal:
        sb["version"] = "ext3"
    else:
        sb["version"] = "ext2"
    end
    return sb
end

proc _parse_group_desc(bytes, offset):
    let gd = {}
    gd["block_bitmap"] = _read_u32(bytes, offset + 0)
    gd["inode_bitmap"] = _read_u32(bytes, offset + 4)
    gd["inode_table"] = _read_u32(bytes, offset + 8)
    gd["free_blocks_count"] = _read_u16(bytes, offset + 12)
    gd["free_inodes_count"] = _read_u16(bytes, offset + 14)
    gd["used_dirs_count"] = _read_u16(bytes, offset + 16)
    return gd
end

proc _get_group_descs(fs):
    let sb = fs["superblock"]
    let bs = sb["block_size"]
    let num_groups = (sb["blocks_count"] + sb["blocks_per_group"] - 1) / sb["blocks_per_group"]
    let gdt_block = sb["first_data_block"] + 1
    let gdt_offset = gdt_block * bs
    let descs = []
    let i = 0
    while i < num_groups:
        let gd = _parse_group_desc(fs["data"], gdt_offset + i * GROUP_DESC_SIZE)
        descs = descs + [gd]
        i = i + 1
    end
    return descs
end

proc read_block(fs, block_num):
    let bs = fs["superblock"]["block_size"]
    let offset = block_num * bs
    let result = []
    let i = 0
    while i < bs:
        result = result + [fs["data"][offset + i]]
        i = i + 1
    end
    return result
end

proc read_inode(fs, inode_num):
    let sb = fs["superblock"]
    let bs = sb["block_size"]
    let inodes_per_group = sb["inodes_per_group"]
    let inode_size = sb["inode_size"]
    if inode_size < 128:
        inode_size = 128
    end
    let group = (inode_num - 1) / inodes_per_group
    let index = (inode_num - 1) % inodes_per_group
    let descs = _get_group_descs(fs)
    let table_block = descs[group]["inode_table"]
    let offset = table_block * bs + index * inode_size
    let d = fs["data"]
    let inode = {}
    inode["mode"] = _read_u16(d, offset + 0)
    inode["uid"] = _read_u16(d, offset + 2)
    inode["size"] = _read_u32(d, offset + 4)
    inode["atime"] = _read_u32(d, offset + 8)
    inode["ctime"] = _read_u32(d, offset + 12)
    inode["mtime"] = _read_u32(d, offset + 16)
    inode["links_count"] = _read_u16(d, offset + 26)
    inode["blocks"] = _read_u32(d, offset + 28)
    inode["flags"] = _read_u32(d, offset + 32)
    # Read 15 block pointers (direct + indirect)
    let blk_ptrs = []
    let i = 0
    while i < 15:
        let ptr = _read_u32(d, offset + 40 + i * 4)
        blk_ptrs = blk_ptrs + [ptr]
        i = i + 1
    end
    inode["block_ptrs"] = blk_ptrs
    inode["inode_num"] = inode_num
    # Check for extent tree (ext4)
    let eh_magic_val = _read_u16(d, offset + 40)
    inode["uses_extents"] = (eh_magic_val == EXTENT_MAGIC)
    if inode["uses_extents"]:
        inode["extent_header"] = _parse_extent_header(d, offset + 40)
        inode["extents"] = _parse_extents(d, offset + 40)
    end
    return inode
end

proc _parse_extent_header(data, offset):
    let eh = {}
    eh["magic"] = _read_u16(data, offset + 0)
    eh["entries"] = _read_u16(data, offset + 2)
    eh["max"] = _read_u16(data, offset + 4)
    eh["depth"] = _read_u16(data, offset + 6)
    return eh
end

proc _parse_extents(data, offset):
    let eh = _parse_extent_header(data, offset)
    let extents = []
    let i = 0
    while i < eh["entries"]:
        let eoff = offset + 12 + i * 12
        let ext = {}
        ext["block"] = _read_u32(data, eoff + 0)
        ext["len"] = _read_u16(data, eoff + 4)
        ext["start_hi"] = _read_u16(data, eoff + 6)
        ext["start_lo"] = _read_u32(data, eoff + 8)
        ext["start"] = ext["start_lo"] + ext["start_hi"] * 4294967296
        extents = extents + [ext]
        i = i + 1
    end
    return extents
end

proc _read_indirect_blocks(fs, block_num, depth):
    if block_num == 0:
        return []
    end
    let bs = fs["superblock"]["block_size"]
    let blk = read_block(fs, block_num)
    let ptrs_per = bs / 4
    let result = []
    let i = 0
    while i < ptrs_per:
        let ptr = _read_u32(blk, i * 4)
        if ptr == 0:
            i = i + 1
            continue
        end
        if depth == 1:
            result = result + [ptr]
        else:
            let sub = _read_indirect_blocks(fs, ptr, depth - 1)
            result = result + sub
        end
        i = i + 1
    end
    return result
end

proc _get_file_blocks(fs, inode):
    if inode["uses_extents"]:
        let blocks = []
        let exts = inode["extents"]
        let i = 0
        while i < len(exts):
            let ext = exts[i]
            let j = 0
            while j < ext["len"]:
                blocks = blocks + [ext["start"] + j]
                j = j + 1
            end
            i = i + 1
        end
        return blocks
    end
    # Traditional block pointers
    let blocks = []
    let i = 0
    while i < DIRECT_BLOCKS:
        let ptr = inode["block_ptrs"][i]
        if ptr != 0:
            blocks = blocks + [ptr]
        end
        i = i + 1
    end
    # Single indirect
    let ind1 = inode["block_ptrs"][INDIRECT_BLOCK_IDX]
    if ind1 != 0:
        blocks = blocks + _read_indirect_blocks(fs, ind1, 1)
    end
    # Double indirect
    let ind2 = inode["block_ptrs"][DOUBLE_INDIRECT_IDX]
    if ind2 != 0:
        blocks = blocks + _read_indirect_blocks(fs, ind2, 2)
    end
    # Triple indirect
    let ind3 = inode["block_ptrs"][TRIPLE_INDIRECT_IDX]
    if ind3 != 0:
        blocks = blocks + _read_indirect_blocks(fs, ind3, 3)
    end
    return blocks
end

proc read_file(fs, inode):
    let size = inode["size"]
    let blocks = _get_file_blocks(fs, inode)
    let bs = fs["superblock"]["block_size"]
    let result = []
    let remaining = size
    let i = 0
    while i < len(blocks):
        if remaining <= 0:
            break
        end
        let blk = read_block(fs, blocks[i])
        let to_copy = bs
        if remaining < bs:
            to_copy = remaining
        end
        let j = 0
        while j < to_copy:
            result = result + [blk[j]]
            j = j + 1
        end
        remaining = remaining - to_copy
        i = i + 1
    end
    return result
end

proc list_dir(fs, inode):
    let data = read_file(fs, inode)
    let entries = []
    let pos = 0
    let total = len(data)
    while pos < total:
        if pos + DIR_ENTRY_HEADER > total:
            break
        end
        let entry_inode = _read_u32(data, pos)
        let rec_len = _read_u16(data, pos + 4)
        let name_len = data[pos + 6]
        let file_type = data[pos + 7]
        if rec_len < 8:
            break
        end
        if entry_inode != 0:
            let name = ""
            let k = 0
            while k < name_len:
                name = name + chr(data[pos + 8 + k])
                k = k + 1
            end
            let entry = {}
            entry["inode"] = entry_inode
            entry["name"] = name
            entry["type"] = file_type
            entries = entries + [entry]
        end
        pos = pos + rec_len
    end
    return entries
end

proc _allocate_block(fs):
    let sb = fs["superblock"]
    let descs = _get_group_descs(fs)
    let bs = sb["block_size"]
    let g = 0
    let num_groups = len(descs)
    while g < num_groups:
        if descs[g]["free_blocks_count"] > 0:
            let bmp_block = descs[g]["block_bitmap"]
            let bmp = read_block(fs, bmp_block)
            let bit = 0
            while bit < sb["blocks_per_group"]:
                let byte_idx = bit / 8
                let bit_idx = bit % 8
                if (bmp[byte_idx] / (2 ** bit_idx)) % 2 == 0:
                    bmp[byte_idx] = bmp[byte_idx] + (2 ** bit_idx)
                    let bmp_off = bmp_block * bs
                    let w = 0
                    while w < bs:
                        fs["data"][bmp_off + w] = bmp[w]
                        w = w + 1
                    end
                    let blk_num = g * sb["blocks_per_group"] + bit + sb["first_data_block"]
                    return blk_num
                end
                bit = bit + 1
            end
        end
        g = g + 1
    end
    return -1
end

proc _allocate_inode(fs):
    let sb = fs["superblock"]
    let descs = _get_group_descs(fs)
    let bs = sb["block_size"]
    let g = 0
    let num_groups = len(descs)
    while g < num_groups:
        if descs[g]["free_inodes_count"] > 0:
            let bmp_block = descs[g]["inode_bitmap"]
            let bmp = read_block(fs, bmp_block)
            let bit = 0
            while bit < sb["inodes_per_group"]:
                let byte_idx = bit / 8
                let bit_idx = bit % 8
                if (bmp[byte_idx] / (2 ** bit_idx)) % 2 == 0:
                    bmp[byte_idx] = bmp[byte_idx] + (2 ** bit_idx)
                    let bmp_off = bmp_block * bs
                    let w = 0
                    while w < bs:
                        fs["data"][bmp_off + w] = bmp[w]
                        w = w + 1
                    end
                    let ino = g * sb["inodes_per_group"] + bit + 1
                    return ino
                end
                bit = bit + 1
            end
        end
        g = g + 1
    end
    return -1
end

proc write_file(fs, parent_inode, name, data):
    let new_ino = _allocate_inode(fs)
    if new_ino == -1:
        print("Error: no free inodes")
        return -1
    end
    let sb = fs["superblock"]
    let bs = sb["block_size"]
    let size = len(data)
    let num_blocks = (size + bs - 1) / bs
    let allocated = []
    let i = 0
    while i < num_blocks:
        let blk = _allocate_block(fs)
        if blk == -1:
            print("Error: no free blocks")
            return -1
        end
        allocated = allocated + [blk]
        i = i + 1
    end
    # Write data to allocated blocks
    let written = 0
    let bi = 0
    while bi < len(allocated):
        let offset = allocated[bi] * bs
        let j = 0
        while j < bs:
            if written < size:
                fs["data"][offset + j] = data[written]
            else:
                fs["data"][offset + j] = 0
            end
            written = written + 1
            j = j + 1
        end
        bi = bi + 1
    end
    # Write inode
    let inode_size = sb["inode_size"]
    if inode_size < 128:
        inode_size = 128
    end
    let group = (new_ino - 1) / sb["inodes_per_group"]
    let index = (new_ino - 1) % sb["inodes_per_group"]
    let descs = _get_group_descs(fs)
    let table_block = descs[group]["inode_table"]
    let ino_off = table_block * bs + index * inode_size
    _write_u16(fs["data"], ino_off + 0, S_IFREG + 438)
    _write_u32(fs["data"], ino_off + 4, size)
    _write_u32(fs["data"], ino_off + 28, num_blocks * (bs / 512))
    let pi = 0
    while pi < len(allocated):
        if pi < DIRECT_BLOCKS:
            _write_u32(fs["data"], ino_off + 40 + pi * 4, allocated[pi])
        end
        pi = pi + 1
    end
    # Add directory entry to parent
    _add_dir_entry(fs, parent_inode, name, new_ino, FT_REG_FILE)
    return new_ino
end

proc _add_dir_entry(fs, parent_inode, name, ino, file_type):
    let parent = read_inode(fs, parent_inode["inode_num"])
    let blocks = _get_file_blocks(fs, parent)
    let bs = fs["superblock"]["block_size"]
    let name_len = len(name)
    let needed = ((8 + name_len + 3) / 4) * 4
    let bi = 0
    while bi < len(blocks):
        let blk_data = read_block(fs, blocks[bi])
        let pos = 0
        while pos < bs:
            let rec_len = _read_u16(blk_data, pos + 4)
            if rec_len < 8:
                break
            end
            let existing_name_len = blk_data[pos + 6]
            let actual_size = ((8 + existing_name_len + 3) / 4) * 4
            if rec_len - actual_size >= needed:
                let new_rec_start = pos + actual_size
                _write_u16(blk_data, pos + 4, actual_size)
                _write_u32(blk_data, new_rec_start, ino)
                _write_u16(blk_data, new_rec_start + 4, rec_len - actual_size)
                blk_data[new_rec_start + 6] = name_len
                blk_data[new_rec_start + 7] = file_type
                let c = 0
                while c < name_len:
                    blk_data[new_rec_start + 8 + c] = ord(name[c])
                    c = c + 1
                end
                # Write block back
                let blk_off = blocks[bi] * bs
                let w = 0
                while w < bs:
                    fs["data"][blk_off + w] = blk_data[w]
                    w = w + 1
                end
                return true
            end
            pos = pos + rec_len
        end
        bi = bi + 1
    end
    return false
end

proc mkdir(fs, parent_inode, name):
    let new_ino = _allocate_inode(fs)
    if new_ino == -1:
        print("Error: no free inodes")
        return -1
    end
    let blk = _allocate_block(fs)
    if blk == -1:
        print("Error: no free blocks")
        return -1
    end
    let sb = fs["superblock"]
    let bs = sb["block_size"]
    # Write inode
    let inode_size = sb["inode_size"]
    if inode_size < 128:
        inode_size = 128
    end
    let group = (new_ino - 1) / sb["inodes_per_group"]
    let index = (new_ino - 1) % sb["inodes_per_group"]
    let descs = _get_group_descs(fs)
    let table_block = descs[group]["inode_table"]
    let ino_off = table_block * bs + index * inode_size
    _write_u16(fs["data"], ino_off + 0, S_IFDIR + 493)
    _write_u32(fs["data"], ino_off + 4, bs)
    _write_u32(fs["data"], ino_off + 28, bs / 512)
    _write_u32(fs["data"], ino_off + 40, blk)
    _write_u16(fs["data"], ino_off + 26, 2)
    # Initialize directory block with . and ..
    let blk_off = blk * bs
    let w = 0
    while w < bs:
        fs["data"][blk_off + w] = 0
        w = w + 1
    end
    # . entry
    _write_u32(fs["data"], blk_off, new_ino)
    _write_u16(fs["data"], blk_off + 4, 12)
    fs["data"][blk_off + 6] = 1
    fs["data"][blk_off + 7] = FT_DIR
    fs["data"][blk_off + 8] = ord(".")
    # .. entry
    _write_u32(fs["data"], blk_off + 12, parent_inode["inode_num"])
    _write_u16(fs["data"], blk_off + 16, bs - 12)
    fs["data"][blk_off + 18] = 2
    fs["data"][blk_off + 19] = FT_DIR
    fs["data"][blk_off + 20] = ord(".")
    fs["data"][blk_off + 21] = ord(".")
    # Add entry to parent
    _add_dir_entry(fs, parent_inode, name, new_ino, FT_DIR)
    return new_ino
end

proc create_ext2():
    let fs = {}
    fs["superblock"] = {}
    fs["superblock"]["magic"] = EXT_MAGIC
    fs["superblock"]["block_size"] = BLOCK_SIZE
    fs["superblock"]["inode_size"] = INODE_SIZE_EXT2
    fs["superblock"]["log_block_size"] = 2
    fs["superblock"]["version"] = "ext2"
    fs["superblock"]["feature_compat"] = 0
    fs["superblock"]["feature_incompat"] = 0
    fs["data"] = []
    return fs
end

proc create_ext4():
    let fs = {}
    fs["superblock"] = {}
    fs["superblock"]["magic"] = EXT_MAGIC
    fs["superblock"]["block_size"] = BLOCK_SIZE
    fs["superblock"]["inode_size"] = INODE_SIZE_EXT4
    fs["superblock"]["log_block_size"] = 2
    fs["superblock"]["version"] = "ext4"
    fs["superblock"]["feature_compat"] = 4
    fs["superblock"]["feature_incompat"] = 64 + 2 + 128
    fs["data"] = []
    return fs
end

proc format_ext2(size_bytes):
    let bs = BLOCK_SIZE
    let total_blocks = size_bytes / bs
    let inodes_per_group = 8192
    let blocks_per_group = 32768
    let num_groups = (total_blocks + blocks_per_group - 1) / blocks_per_group
    let total_inodes = num_groups * inodes_per_group
    let data = _zero_bytes(size_bytes)
    # Write superblock at offset 1024
    let off = SUPERBLOCK_OFFSET
    _write_u32(data, off + 0, total_inodes)
    _write_u32(data, off + 4, total_blocks)
    _write_u32(data, off + 12, total_blocks - 100)
    _write_u32(data, off + 16, total_inodes - 11)
    _write_u32(data, off + 20, 1)
    _write_u32(data, off + 24, 2)
    _write_u32(data, off + 32, blocks_per_group)
    _write_u32(data, off + 40, inodes_per_group)
    _write_u16(data, off + 56, EXT_MAGIC)
    _write_u16(data, off + 58, 1)
    _write_u32(data, off + 76, 1)
    _write_u32(data, off + 84, 11)
    _write_u16(data, off + 88, INODE_SIZE_EXT2)
    let fs = {}
    fs["data"] = data
    fs["superblock"] = parse_superblock(data, SUPERBLOCK_OFFSET)
    return fs
end

proc format_ext4(size_bytes):
    let fs = format_ext2(size_bytes)
    let off = SUPERBLOCK_OFFSET
    # Enable journal + extents features
    _write_u32(fs["data"], off + 92, 4)
    _write_u32(fs["data"], off + 96, 64 + 2 + 128)
    _write_u16(fs["data"], off + 88, INODE_SIZE_EXT4)
    fs["superblock"] = parse_superblock(fs["data"], SUPERBLOCK_OFFSET)
    return fs
end

# ========== Delete / Rename / Symlink / Journal ==========

# Delete a file (unlink from parent directory, free inode+blocks)
proc delete_file(fs, parent_inode_num, name):
    let parent = read_inode(fs, parent_inode_num)
    let blocks = _get_file_blocks(fs, parent)
    let bs = BLOCK_SIZE
    for bi in range(len(blocks)):
        let bdata = read_block(fs, blocks[bi])
        let off = 0
        let prev_off = -1
        while off < bs:
            let rec_len = _read_u16(bdata, off + 4)
            if rec_len == 0:
                break
            end
            let name_len = bdata[off + 6]
            let entry_name = ""
            for ni in range(name_len):
                entry_name = entry_name + chr(bdata[off + 8 + ni])
            end
            if entry_name == name:
                let target_ino = _read_u32(bdata, off)
                # Zero out inode reference
                _write_u32(bdata, off, 0)
                # If previous entry, extend its rec_len to absorb this one
                if prev_off >= 0:
                    let prev_rec = _read_u16(bdata, prev_off + 4)
                    _write_u16(bdata, prev_off + 4, prev_rec + rec_len)
                end
                # Write block back
                let blk_off = blocks[bi] * bs
                for wi in range(bs):
                    fs["data"][blk_off + wi] = bdata[wi]
                end
                # Free the target inode blocks
                let target = read_inode(fs, target_ino)
                let tblocks = _get_file_blocks(fs, target)
                for ti in range(len(tblocks)):
                    _free_block(fs, tblocks[ti])
                end
                _free_inode(fs, target_ino)
                return true
            end
            prev_off = off
            off = off + rec_len
        end
    end
    return false
end

# Free a block (clear bitmap bit)
proc _free_block(fs, block_num):
    let sb = fs["superblock"]
    let bsize = sb["block_size"]
    let bpg = sb["blocks_per_group"]
    let group = block_num / bpg
    let idx = block_num % bpg
    let gd = _parse_group_desc(fs["data"], SUPERBLOCK_OFFSET + SUPERBLOCK_SIZE + group * 32)
    let bmp_off = gd["block_bitmap"] * bsize + (idx / 8)
    let bit = idx % 8
    fs["data"][bmp_off] = fs["data"][bmp_off] & (255 - (1 << bit))
end

# Free an inode (clear bitmap bit)
proc _free_inode(fs, inode_num):
    let sb = fs["superblock"]
    let bsize = sb["block_size"]
    let ipg = sb["inodes_per_group"]
    let group = (inode_num - 1) / ipg
    let idx = (inode_num - 1) % ipg
    let gd = _parse_group_desc(fs["data"], SUPERBLOCK_OFFSET + SUPERBLOCK_SIZE + group * 32)
    let bmp_off = gd["inode_bitmap"] * bsize + (idx / 8)
    let bit = idx % 8
    fs["data"][bmp_off] = fs["data"][bmp_off] & (255 - (1 << bit))
end

# Rename a file (remove old dir entry, add new one)
proc rename_file(fs, parent_ino, old_name, new_name):
    # Find the inode of the old entry
    let parent = read_inode(fs, parent_ino)
    let entries = list_dir(fs, parent)
    let target_ino = 0
    let target_type = 1
    for i in range(len(entries)):
        if entries[i]["name"] == old_name:
            target_ino = entries[i]["inode"]
            target_type = entries[i]["file_type"]
            break
        end
    end
    if target_ino == 0:
        return false
    end
    delete_file(fs, parent_ino, old_name)
    _add_dir_entry(fs, parent_ino, new_name, target_ino, target_type)
    return true
end

# Create a symbolic link
proc create_symlink(fs, parent_ino, name, target_path):
    let ino = _allocate_inode(fs)
    if ino == 0:
        return 0
    end
    let sb = fs["superblock"]
    let bsize = sb["block_size"]
    let ipg = sb["inodes_per_group"]
    let group = (ino - 1) / ipg
    let idx = (ino - 1) % ipg
    let gd = _parse_group_desc(fs["data"], SUPERBLOCK_OFFSET + SUPERBLOCK_SIZE + group * 32)
    let ino_off = gd["inode_table"] * bsize + idx * sb["inode_size"]
    # Set mode: symlink + rwxrwxrwx (40960 + 511 = 41471)
    _write_u16(fs["data"], ino_off + 0, S_IFLNK + 511)
    _write_u32(fs["data"], ino_off + 4, len(target_path))
    # Short symlinks: store target in block pointers (up to 60 bytes)
    if len(target_path) <= 60:
        for si in range(len(target_path)):
            fs["data"][ino_off + 40 + si] = ord(target_path[si])
        end
    else:
        let blk = _allocate_block(fs)
        if blk > 0:
            _write_u32(fs["data"], ino_off + 40, blk)
            let blk_off = blk * bsize
            for si in range(len(target_path)):
                fs["data"][blk_off + si] = ord(target_path[si])
            end
        end
    end
    _add_dir_entry(fs, parent_ino, name, ino, FT_SYMLINK)
    return ino
end

# Read a symbolic link target
proc read_symlink(fs, inode):
    let size = inode["size"]
    if size <= 60:
        # Fast symlink: target stored in block pointers
        let target = ""
        let sb = fs["superblock"]
        let bsize = sb["block_size"]
        let ipg = sb["inodes_per_group"]
        # Re-read raw inode data for block pointer area
        let blocks = inode["blocks_array"]
        if blocks != nil:
            for si in range(size):
                if si < len(blocks):
                    target = target + chr(blocks[si])
                end
            end
        end
        return target
    end
    # Regular symlink: read from data block
    return read_file(fs, inode)
end

# Extended attributes (xattr) support
proc read_xattrs(fs, inode_num):
    let attrs = {}
    let sb = fs["superblock"]
    let bsize = sb["block_size"]
    let ipg = sb["inodes_per_group"]
    let group = (inode_num - 1) / ipg
    let idx = (inode_num - 1) % ipg
    let gd = _parse_group_desc(fs["data"], SUPERBLOCK_OFFSET + SUPERBLOCK_SIZE + group * 32)
    let ino_off = gd["inode_table"] * bsize + idx * sb["inode_size"]
    # Inline xattrs: after inode base (128 bytes) up to inode_size
    let extra_start = ino_off + 128
    let extra_end = ino_off + sb["inode_size"]
    if extra_end > extra_start + 4:
        let magic = _read_u32(fs["data"], extra_start)
        if magic == 3925999414:
            let off = extra_start + 4
            while off + 4 < extra_end:
                let name_len = fs["data"][off]
                let name_idx = fs["data"][off + 1]
                let val_off = _read_u16(fs["data"], off + 2)
                let val_sz = _read_u32(fs["data"], off + 4)
                if name_len == 0:
                    break
                end
                let aname = ""
                for ni in range(name_len):
                    aname = aname + chr(fs["data"][off + 8 + ni])
                end
                let aval = ""
                for vi in range(val_sz):
                    if extra_start + val_off + vi < extra_end:
                        aval = aval + chr(fs["data"][extra_start + val_off + vi])
                    end
                end
                attrs[aname] = aval
                off = off + 8 + name_len
                # Align to 4
                while off % 4 != 0:
                    off = off + 1
                end
            end
        end
    end
    return attrs
end

# Simple journal info (ext3/4 journal superblock)
proc read_journal_info(fs):
    let info = {}
    let sb = fs["superblock"]
    if not dict_has(sb, "journal_inum"):
        info["has_journal"] = false
        return info
    end
    info["has_journal"] = true
    info["journal_inum"] = sb["journal_inum"]
    # Read journal inode
    let jinode = read_inode(fs, sb["journal_inum"])
    info["journal_size"] = jinode["size"]
    info["journal_blocks"] = len(_get_file_blocks(fs, jinode))
    return info
end

# Basic fsck: check superblock, bitmaps, inode counts
proc fsck(fs):
    let result = {}
    result["errors"] = []
    let sb = fs["superblock"]
    # Check magic
    if sb["magic"] != EXT_MAGIC:
        push(result["errors"], "bad superblock magic")
    end
    # Check block size
    if sb["block_size"] != 1024 and sb["block_size"] != 2048 and sb["block_size"] != 4096:
        push(result["errors"], "invalid block size: " + str(sb["block_size"]))
    end
    # Check root inode
    let root = read_inode(fs, ROOT_INODE)
    if root == nil:
        push(result["errors"], "cannot read root inode")
    else:
        if (root["mode"] & 61440) != S_IFDIR:
            push(result["errors"], "root inode is not a directory")
        end
    end
    # Check free counts
    let groups = _get_group_descs(fs)
    let total_free_blocks = 0
    let total_free_inodes = 0
    for gi in range(len(groups)):
        total_free_blocks = total_free_blocks + groups[gi]["free_blocks"]
        total_free_inodes = total_free_inodes + groups[gi]["free_inodes"]
    end
    result["free_blocks"] = total_free_blocks
    result["free_inodes"] = total_free_inodes
    result["total_blocks"] = sb["total_blocks"]
    result["total_inodes"] = sb["total_inodes"]
    result["clean"] = len(result["errors"]) == 0
    return result
end

# Stat a file (return metadata dict)
proc stat_file(fs, inode):
    let info = {}
    let mode = inode["mode"]
    info["mode"] = mode
    info["size"] = inode["size"]
    info["uid"] = inode["uid"]
    info["gid"] = inode["gid"]
    info["atime"] = inode["atime"]
    info["mtime"] = inode["mtime"]
    info["ctime"] = inode["ctime"]
    info["links"] = inode["links_count"]
    info["blocks"] = len(_get_file_blocks(fs, inode))
    let ft = mode & 61440
    if ft == S_IFREG:
        info["type"] = "file"
    end
    if ft == S_IFDIR:
        info["type"] = "directory"
    end
    if ft == S_IFLNK:
        info["type"] = "symlink"
    end
    if ft == S_IFIFO:
        info["type"] = "fifo"
    end
    if ft == S_IFSOCK:
        info["type"] = "socket"
    end
    if ft == S_IFBLK:
        info["type"] = "block_device"
    end
    if ft == S_IFCHR:
        info["type"] = "char_device"
    end
    # Permissions
    info["owner_read"] = (mode & 256) != 0
    info["owner_write"] = (mode & 128) != 0
    info["owner_exec"] = (mode & 64) != 0
    info["group_read"] = (mode & 32) != 0
    info["group_write"] = (mode & 16) != 0
    info["group_exec"] = (mode & 8) != 0
    info["other_read"] = (mode & 4) != 0
    info["other_write"] = (mode & 2) != 0
    info["other_exec"] = (mode & 1) != 0
    return info
end
