gc_disable()

# f2fs.sage - F2FS (Flash-Friendly File System) support
# Provides parsing and reading for F2FS filesystem structures

# Constants
let F2FS_MAGIC = 0xF2F52010
let BLOCK_SIZE = 4096
let F2FS_SUPER_OFFSET = 1024
let LOG_BLOCKS_PER_SEG = 9
let BLOCKS_PER_SEG = 512
let NAT_ENTRY_SIZE = 9
let SIT_ENTRY_SIZE = 74
let F2FS_INODE_SIZE = 4096
let MAX_NIDS_PER_BLOCK = 455

# Segment types
let HOT_DATA = 0
let WARM_DATA = 1
let COLD_DATA = 2
let HOT_NODE = 3
let WARM_NODE = 4
let COLD_NODE = 5

# Inode flags
let F2FS_FT_REG_FILE = 1
let F2FS_FT_DIR = 2
let F2FS_FT_SYMLINK = 7

# Inline flags
let F2FS_INLINE_DATA = 0x02
let F2FS_INLINE_DENTRY = 0x04

proc _read_u8(bytes, off):
    return bytes[off]

proc _read_u16(bytes, off):
    return bytes[off] + bytes[off + 1] * 256

proc _read_u32(bytes, off):
    return bytes[off] + bytes[off + 1] * 256 + bytes[off + 2] * 65536 + bytes[off + 3] * 16777216

proc _read_u64(bytes, off):
    let lo = _read_u32(bytes, off)
    let hi = _read_u32(bytes, off + 4)
    return lo + hi * 4294967296

proc _write_u16(bytes, off, val):
    bytes[off] = val % 256
    bytes[off + 1] = (val / 256) % 256

proc _write_u32(bytes, off, val):
    bytes[off] = val % 256
    bytes[off + 1] = (val / 256) % 256
    bytes[off + 2] = (val / 65536) % 256
    bytes[off + 3] = (val / 16777216) % 256

proc _write_u64(bytes, off, val):
    _write_u32(bytes, off, val % 4294967296)
    _write_u32(bytes, off + 4, val / 4294967296)

proc _read_bytes_as_str(bytes, off, length):
    let s = ""
    let i = 0
    while i < length:
        let b = bytes[off + i]
        if b == 0:
            return s
        s = s + chr(b)
        i = i + 1
    return s

proc _zero_bytes(count):
    let result = []
    let i = 0
    while i < count:
        result = result + [0]
        i = i + 1
    return result

proc _read_block(fs, blkaddr):
    let offset = blkaddr * BLOCK_SIZE
    let result = []
    let i = 0
    while i < BLOCK_SIZE:
        result = result + [fs["data"][offset + i]]
        i = i + 1
    return result

proc parse_superblock(bytes):
    let off = F2FS_SUPER_OFFSET
    let sb = {}
    sb["magic"] = _read_u32(bytes, off + 0)
    sb["major_ver"] = _read_u16(bytes, off + 4)
    sb["minor_ver"] = _read_u16(bytes, off + 6)
    sb["log_sectorsize"] = _read_u32(bytes, off + 8)
    sb["log_sectors_per_block"] = _read_u32(bytes, off + 12)
    sb["log_blocksize"] = _read_u32(bytes, off + 16)
    sb["log_blocks_per_seg"] = _read_u32(bytes, off + 20)
    sb["segs_per_sec"] = _read_u32(bytes, off + 24)
    sb["secs_per_zone"] = _read_u32(bytes, off + 28)
    sb["checksum_offset"] = _read_u32(bytes, off + 32)
    sb["block_count"] = _read_u64(bytes, off + 36)
    sb["section_count"] = _read_u32(bytes, off + 44)
    sb["segment_count"] = _read_u32(bytes, off + 48)
    sb["segment_count_ckpt"] = _read_u32(bytes, off + 52)
    sb["segment_count_sit"] = _read_u32(bytes, off + 56)
    sb["segment_count_nat"] = _read_u32(bytes, off + 60)
    sb["segment_count_ssa"] = _read_u32(bytes, off + 64)
    sb["segment_count_main"] = _read_u32(bytes, off + 68)
    sb["segment0_blkaddr"] = _read_u32(bytes, off + 72)
    sb["cp_blkaddr"] = _read_u32(bytes, off + 76)
    sb["sit_blkaddr"] = _read_u32(bytes, off + 80)
    sb["nat_blkaddr"] = _read_u32(bytes, off + 84)
    sb["ssa_blkaddr"] = _read_u32(bytes, off + 88)
    sb["main_blkaddr"] = _read_u32(bytes, off + 92)
    sb["root_ino"] = _read_u32(bytes, off + 96)
    sb["node_ino"] = _read_u32(bytes, off + 100)
    sb["meta_ino"] = _read_u32(bytes, off + 104)
    if sb["magic"] != F2FS_MAGIC:
        print("Warning: invalid F2FS magic " + str(sb["magic"]))
    return sb

proc _get_nat_block_addr(fs, nid):
    let sb = fs["superblock"]
    let nat_blkaddr = sb["nat_blkaddr"]
    let entries_per_block = BLOCK_SIZE / NAT_ENTRY_SIZE
    let block_off = nid / entries_per_block
    return nat_blkaddr + block_off

proc read_nat(fs, nid):
    let sb = fs["superblock"]
    let nat_blkaddr = sb["nat_blkaddr"]
    let entries_per_block = BLOCK_SIZE / NAT_ENTRY_SIZE
    let block_off = nid / entries_per_block
    let entry_off = nid % entries_per_block
    let blk = _read_block(fs, nat_blkaddr + block_off)
    let eoff = entry_off * NAT_ENTRY_SIZE
    let entry = {}
    entry["ino"] = _read_u32(blk, eoff + 0)
    entry["block_addr"] = _read_u32(blk, eoff + 4)
    entry["version"] = _read_u8(blk, eoff + 8)
    return entry

proc _get_sit_block_addr(fs, segno):
    let sb = fs["superblock"]
    let sit_blkaddr = sb["sit_blkaddr"]
    let entries_per_block = BLOCK_SIZE / SIT_ENTRY_SIZE
    let block_off = segno / entries_per_block
    return sit_blkaddr + block_off

proc read_sit(fs, segno):
    let sb = fs["superblock"]
    let sit_blkaddr = sb["sit_blkaddr"]
    let entries_per_block = BLOCK_SIZE / SIT_ENTRY_SIZE
    let block_off = segno / entries_per_block
    let entry_off = segno % entries_per_block
    let blk = _read_block(fs, sit_blkaddr + block_off)
    let eoff = entry_off * SIT_ENTRY_SIZE
    let entry = {}
    entry["vblocks"] = _read_u16(blk, eoff + 0)
    entry["mtime"] = _read_u64(blk, eoff + 2)
    # Valid bitmap: 64 bytes (512 bits, one per block in segment)
    let bitmap = []
    let i = 0
    while i < 64:
        bitmap = bitmap + [blk[eoff + 10 + i]]
        i = i + 1
    entry["valid_map"] = bitmap
    entry["seg_type"] = _get_seg_type(entry["vblocks"])
    return entry

proc _get_seg_type(vblocks):
    # Upper bits may encode type
    let t = (vblocks / 1024) % 8
    if t == HOT_DATA:
        return "hot_data"
    if t == WARM_DATA:
        return "warm_data"
    if t == COLD_DATA:
        return "cold_data"
    if t == HOT_NODE:
        return "hot_node"
    if t == WARM_NODE:
        return "warm_node"
    if t == COLD_NODE:
        return "cold_node"
    return "unknown"

proc read_inode(fs, nid):
    let nat_entry = read_nat(fs, nid)
    let blkaddr = nat_entry["block_addr"]
    if blkaddr == 0:
        return nil
    let blk = _read_block(fs, blkaddr)
    let inode = {}
    inode["nid"] = nid
    inode["mode"] = _read_u16(blk, 0)
    inode["uid"] = _read_u32(blk, 4)
    inode["gid"] = _read_u32(blk, 8)
    inode["links"] = _read_u32(blk, 12)
    inode["size"] = _read_u64(blk, 16)
    inode["blocks"] = _read_u64(blk, 24)
    inode["atime"] = _read_u64(blk, 32)
    inode["ctime"] = _read_u64(blk, 40)
    inode["mtime"] = _read_u64(blk, 48)
    inode["flags"] = _read_u32(blk, 56)
    inode["namelen"] = _read_u32(blk, 60)
    inode["name"] = _read_bytes_as_str(blk, 64, inode["namelen"])
    inode["inline_flags"] = _read_u32(blk, 320)
    # Data block addresses (up to 923 direct + indirect)
    let addrs = []
    let i = 0
    while i < 923:
        let addr = _read_u32(blk, 328 + i * 4)
        addrs = addrs + [addr]
        i = i + 1
    inode["addrs"] = addrs
    inode["has_inline_data"] = (inode["inline_flags"] / 2) % 2 == 1
    inode["has_inline_dentry"] = (inode["inline_flags"] / 4) % 2 == 1
    return inode

proc list_dir(fs, inode):
    let entries = []
    if inode["has_inline_dentry"]:
        # Inline dentry stored in inode block
        let nat_entry = read_nat(fs, inode["nid"])
        let blk = _read_block(fs, nat_entry["block_addr"])
        let dentry_off = 328
        let max_entries = 30
        let i = 0
        while i < max_entries:
            let eoff = dentry_off + i * 11
            if eoff + 11 > BLOCK_SIZE:
                break
            let hash = _read_u32(blk, eoff)
            let ino = _read_u32(blk, eoff + 4)
            let name_len = _read_u8(blk, eoff + 8)
            let file_type = _read_u8(blk, eoff + 9)
            if ino == 0:
                i = i + 1
                continue
            let name_off = dentry_off + max_entries * 11 + i * 8
            let name = _read_bytes_as_str(blk, name_off, name_len)
            let entry = {}
            entry["ino"] = ino
            entry["name"] = name
            entry["type"] = file_type
            entries = entries + [entry]
            i = i + 1
        return entries
    # Read dentry blocks from inode addresses
    let bi = 0
    while bi < len(inode["addrs"]):
        let blkaddr = inode["addrs"][bi]
        if blkaddr == 0:
            bi = bi + 1
            continue
        let blk = _read_block(fs, blkaddr)
        # Dentry block: bitmap + dentries + filenames
        let max_entries = 214
        let bitmap_size = 27
        let i = 0
        while i < max_entries:
            let byte_idx = i / 8
            let bit_idx = i % 8
            let valid = (blk[byte_idx] / (2 ** bit_idx)) % 2
            if valid == 0:
                i = i + 1
                continue
            let eoff = bitmap_size + i * 11
            let hash = _read_u32(blk, eoff)
            let ino = _read_u32(blk, eoff + 4)
            let name_len = _read_u8(blk, eoff + 8)
            let file_type = _read_u8(blk, eoff + 9)
            let name_off = bitmap_size + max_entries * 11 + i * 8
            let name = _read_bytes_as_str(blk, name_off, name_len)
            let entry = {}
            entry["ino"] = ino
            entry["name"] = name
            entry["type"] = file_type
            entries = entries + [entry]
            i = i + 1
        bi = bi + 1
    return entries

proc read_file(fs, inode):
    let size = inode["size"]
    let result = []
    let remaining = size
    let bi = 0
    while bi < len(inode["addrs"]):
        if remaining <= 0:
            break
        let blkaddr = inode["addrs"][bi]
        if blkaddr == 0:
            bi = bi + 1
            continue
        let blk = _read_block(fs, blkaddr)
        let to_copy = BLOCK_SIZE
        if remaining < BLOCK_SIZE:
            to_copy = remaining
        let j = 0
        while j < to_copy:
            result = result + [blk[j]]
            j = j + 1
        remaining = remaining - to_copy
        bi = bi + 1
    return result

proc gc_info(fs):
    let sb = fs["superblock"]
    let info = {}
    info["segment_count_main"] = sb["segment_count_main"]
    info["segment_count"] = sb["segment_count"]
    # Scan SIT for valid block counts and segment utilization
    let total_valid = 0
    let total_segments = sb["segment_count_main"]
    let free_segments = 0
    let dirty_segments = 0
    let seg = 0
    while seg < total_segments:
        let sit = read_sit(fs, seg)
        let vblocks = sit["vblocks"] % 1024
        total_valid = total_valid + vblocks
        if vblocks == 0:
            free_segments = free_segments + 1
        if vblocks > 0:
            if vblocks < BLOCKS_PER_SEG:
                dirty_segments = dirty_segments + 1
        seg = seg + 1
    info["total_valid_blocks"] = total_valid
    info["free_segments"] = free_segments
    info["dirty_segments"] = dirty_segments
    info["utilization"] = 0
    if total_segments > 0:
        info["utilization"] = (total_valid * 100) / (total_segments * BLOCKS_PER_SEG)
    return info

proc _parse_checkpoint(fs):
    let sb = fs["superblock"]
    let cp_blkaddr = sb["cp_blkaddr"]
    let blk = _read_block(fs, cp_blkaddr)
    let cp = {}
    cp["checkpoint_ver"] = _read_u64(blk, 0)
    cp["user_block_count"] = _read_u64(blk, 8)
    cp["valid_block_count"] = _read_u64(blk, 16)
    cp["rsvd_segment_count"] = _read_u32(blk, 24)
    cp["free_segment_count"] = _read_u32(blk, 28)
    cp["cur_node_segno0"] = _read_u32(blk, 32)
    cp["cur_node_segno1"] = _read_u32(blk, 36)
    cp["cur_data_segno0"] = _read_u32(blk, 40)
    cp["cur_data_segno1"] = _read_u32(blk, 44)
    cp["elapsed_time"] = _read_u64(blk, 48)
    return cp

proc create_f2fs(size_bytes):
    let total_blocks = size_bytes / BLOCK_SIZE
    let total_segments = total_blocks / BLOCKS_PER_SEG
    let data = _zero_bytes(size_bytes)
    # Write superblock at offset 1024
    let off = F2FS_SUPER_OFFSET
    _write_u32(data, off + 0, F2FS_MAGIC)
    _write_u16(data, off + 4, 1)
    _write_u16(data, off + 6, 0)
    _write_u32(data, off + 8, 9)
    _write_u32(data, off + 12, 3)
    _write_u32(data, off + 16, 12)
    _write_u32(data, off + 20, LOG_BLOCKS_PER_SEG)
    _write_u32(data, off + 24, 1)
    _write_u32(data, off + 28, 1)
    _write_u64(data, off + 36, total_blocks)
    _write_u32(data, off + 44, total_segments - 10)
    _write_u32(data, off + 48, total_segments)
    _write_u32(data, off + 52, 2)
    _write_u32(data, off + 56, 2)
    _write_u32(data, off + 60, 2)
    _write_u32(data, off + 64, 2)
    _write_u32(data, off + 68, total_segments - 10)
    # Metadata area starts at segment 0
    let seg0_blkaddr = 2
    _write_u32(data, off + 72, seg0_blkaddr)
    _write_u32(data, off + 76, seg0_blkaddr)
    let cp_segs = 2
    let sit_blkaddr = seg0_blkaddr + cp_segs * BLOCKS_PER_SEG
    _write_u32(data, off + 80, sit_blkaddr)
    let sit_segs = 2
    let nat_blkaddr = sit_blkaddr + sit_segs * BLOCKS_PER_SEG
    _write_u32(data, off + 84, nat_blkaddr)
    let nat_segs = 2
    let ssa_blkaddr = nat_blkaddr + nat_segs * BLOCKS_PER_SEG
    _write_u32(data, off + 88, ssa_blkaddr)
    let ssa_segs = 2
    let main_blkaddr = ssa_blkaddr + ssa_segs * BLOCKS_PER_SEG
    _write_u32(data, off + 92, main_blkaddr)
    # Root inode = 3, node_ino = 1, meta_ino = 2
    _write_u32(data, off + 96, 3)
    _write_u32(data, off + 100, 1)
    _write_u32(data, off + 104, 2)
    let fs = {}
    fs["data"] = data
    fs["superblock"] = parse_superblock(data)
    return fs
