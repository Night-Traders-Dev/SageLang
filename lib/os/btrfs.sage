gc_disable()

# btrfs.sage - Btrfs filesystem support
# Provides parsing and reading for Btrfs B-tree filesystem structures

# Constants
let BTRFS_MAGIC_STR = "_BHRfS_M"
let BTRFS_SUPERBLOCK_OFFSET = 0x10000
let BTRFS_SUPER_INFO_SIZE = 4096
let BTRFS_NODE_SIZE = 16384
let BTRFS_LEAF_SIZE = 16384

# Item types
let INODE_ITEM = 1
let INODE_REF = 12
let XATTR_ITEM = 24
let ORPHAN_ITEM = 48
let DIR_LOG_ITEM = 60
let DIR_LOG_INDEX = 72
let DIR_ITEM = 84
let DIR_INDEX = 96
let EXTENT_DATA = 108
let EXTENT_CSUM = 128
let ROOT_ITEM = 132
let ROOT_BACKREF = 144
let ROOT_REF = 156
let EXTENT_ITEM = 168
let CHUNK_ITEM = 228
let DEV_ITEM = 216
let BLOCK_GROUP_ITEM = 192

# Well-known tree objectids
let ROOT_TREE_OBJECTID = 1
let EXTENT_TREE_OBJECTID = 2
let CHUNK_TREE_OBJECTID = 3
let DEV_TREE_OBJECTID = 4
let FS_TREE_OBJECTID = 5
let CSUM_TREE_OBJECTID = 7
let FIRST_FREE_OBJECTID = 256

# CRC32C table for btrfs checksums
let _crc_table = []
let _crc_initialized = false

def _init_crc32c():
    if _crc_initialized:
        return
    let i = 0
    while i < 256:
        let crc = i
        let j = 0
        while j < 8:
            if crc % 2 == 1:
                crc = (crc / 2) ^ 0x82F63B78
            else:
                crc = crc / 2
            j = j + 1
        _crc_table = _crc_table + [crc]
        i = i + 1
    _crc_initialized = true

def crc32c(data, start, length):
    _init_crc32c()
    let crc = 0xFFFFFFFF
    let i = 0
    while i < length:
        let byte = data[start + i]
        let idx = (crc ^ byte) % 256
        crc = (crc / 256) ^ _crc_table[idx]
        i = i + 1
    return crc ^ 0xFFFFFFFF

def _read_u8(bytes, off):
    return bytes[off]

def _read_u16(bytes, off):
    return bytes[off] + bytes[off + 1] * 256

def _read_u32(bytes, off):
    return bytes[off] + bytes[off + 1] * 256 + bytes[off + 2] * 65536 + bytes[off + 3] * 16777216

def _read_u64(bytes, off):
    let lo = _read_u32(bytes, off)
    let hi = _read_u32(bytes, off + 4)
    return lo + hi * 4294967296

def _read_bytes_as_str(bytes, off, length):
    let s = ""
    let i = 0
    while i < length:
        let b = bytes[off + i]
        if b == 0:
            return s
        s = s + chr(b)
        i = i + 1
    return s

def _write_u32(bytes, off, val):
    bytes[off] = val % 256
    bytes[off + 1] = (val / 256) % 256
    bytes[off + 2] = (val / 65536) % 256
    bytes[off + 3] = (val / 16777216) % 256

def _write_u64(bytes, off, val):
    _write_u32(bytes, off, val % 4294967296)
    _write_u32(bytes, off + 4, val / 4294967296)

def _zero_bytes(count):
    let result = []
    let i = 0
    while i < count:
        result = result + [0]
        i = i + 1
    return result

def parse_superblock(bytes):
    # Btrfs superblock at offset 0x10000 (65536)
    let off = BTRFS_SUPERBLOCK_OFFSET
    let sb = {}
    sb["csum"] = _read_u32(bytes, off + 0)
    sb["fsid"] = _read_bytes_as_str(bytes, off + 32, 16)
    sb["bytenr"] = _read_u64(bytes, off + 48)
    sb["flags"] = _read_u64(bytes, off + 56)
    # Magic at offset 64 from superblock start
    sb["magic"] = _read_bytes_as_str(bytes, off + 64, 8)
    sb["generation"] = _read_u64(bytes, off + 72)
    sb["root"] = _read_u64(bytes, off + 80)
    sb["chunk_root"] = _read_u64(bytes, off + 88)
    sb["log_root"] = _read_u64(bytes, off + 96)
    sb["total_bytes"] = _read_u64(bytes, off + 104)
    sb["bytes_used"] = _read_u64(bytes, off + 112)
    sb["root_dir_objectid"] = _read_u64(bytes, off + 120)
    sb["num_devices"] = _read_u64(bytes, off + 128)
    sb["sectorsize"] = _read_u32(bytes, off + 136)
    sb["nodesize"] = _read_u32(bytes, off + 140)
    sb["leafsize"] = _read_u32(bytes, off + 144)
    sb["stripesize"] = _read_u32(bytes, off + 148)
    sb["sys_chunk_array_size"] = _read_u32(bytes, off + 152)
    sb["compat_flags"] = _read_u64(bytes, off + 160)
    sb["incompat_flags"] = _read_u64(bytes, off + 168)
    if sb["magic"] != BTRFS_MAGIC_STR:
        print("Warning: invalid btrfs magic: " + sb["magic"])
    # Verify checksum
    let expected_csum = crc32c(bytes, off + 32, BTRFS_SUPER_INFO_SIZE - 32)
    sb["csum_valid"] = (expected_csum == sb["csum"])
    return sb

def _parse_key(bytes, off):
    let key = {}
    key["objectid"] = _read_u64(bytes, off)
    key["type"] = _read_u8(bytes, off + 8)
    key["offset"] = _read_u64(bytes, off + 9)
    return key

def _parse_header(bytes, addr):
    let hdr = {}
    hdr["csum"] = _read_u32(bytes, addr + 0)
    hdr["fsid"] = _read_bytes_as_str(bytes, addr + 32, 16)
    hdr["bytenr"] = _read_u64(bytes, addr + 48)
    hdr["flags"] = _read_u64(bytes, addr + 56)
    hdr["generation"] = _read_u64(bytes, addr + 72)
    hdr["owner"] = _read_u64(bytes, addr + 80)
    hdr["nritems"] = _read_u32(bytes, addr + 88)
    hdr["level"] = _read_u8(bytes, addr + 92)
    return hdr

def read_tree(fs, root_addr):
    let data = fs["data"]
    let hdr = _parse_header(data, root_addr)
    let node = {}
    node["header"] = hdr
    node["addr"] = root_addr
    if hdr["level"] == 0:
        node["type"] = "leaf"
        node["items"] = parse_leaf(fs, root_addr)
    else:
        node["type"] = "internal"
        node["children"] = parse_internal(fs, root_addr)
    return node

def parse_leaf(fs, addr):
    let data = fs["data"]
    let hdr = _parse_header(data, addr)
    let items = []
    let i = 0
    while i < hdr["nritems"]:
        let item_off = addr + 101 + i * 25
        let item = {}
        item["key"] = _parse_key(data, item_off)
        item["offset"] = _read_u32(data, item_off + 17)
        item["size"] = _read_u32(data, item_off + 21)
        # Read item data
        let data_off = addr + 101 + item["offset"]
        item["data_offset"] = data_off
        items = items + [item]
        i = i + 1
    return items

def parse_internal(fs, addr):
    let data = fs["data"]
    let hdr = _parse_header(data, addr)
    let children = []
    let i = 0
    while i < hdr["nritems"]:
        let kp_off = addr + 101 + i * 33
        let child = {}
        child["key"] = _parse_key(data, kp_off)
        child["blockptr"] = _read_u64(data, kp_off + 17)
        child["generation"] = _read_u64(data, kp_off + 25)
        children = children + [child]
        i = i + 1
    return children

def _search_tree(fs, root_addr, objectid, item_type):
    let data = fs["data"]
    let hdr = _parse_header(data, root_addr)
    if hdr["level"] == 0:
        # Leaf: scan items
        let items = parse_leaf(fs, root_addr)
        let results = []
        let i = 0
        while i < len(items):
            let k = items[i]["key"]
            if k["objectid"] == objectid:
                if k["type"] == item_type:
                    results = results + [items[i]]
            i = i + 1
        return results
    # Internal: find child
    let children = parse_internal(fs, root_addr)
    let target_child = children[0]["blockptr"]
    let i = 0
    while i < len(children):
        let k = children[i]["key"]
        if k["objectid"] <= objectid:
            target_child = children[i]["blockptr"]
        i = i + 1
    return _search_tree(fs, target_child, objectid, item_type)

def list_dir(fs, tree_root, dir_objectid):
    let items = _search_tree(fs, tree_root, dir_objectid, DIR_ITEM)
    let entries = []
    let i = 0
    while i < len(items):
        let item = items[i]
        let data = fs["data"]
        let doff = item["data_offset"]
        let child_key = _parse_key(data, doff)
        let transid = _read_u64(data, doff + 17)
        let data_len = _read_u16(data, doff + 25)
        let name_len = _read_u16(data, doff + 27)
        let entry_type = _read_u8(data, doff + 29)
        let name = _read_bytes_as_str(data, doff + 30, name_len)
        let entry = {}
        entry["objectid"] = child_key["objectid"]
        entry["name"] = name
        entry["type"] = entry_type
        entries = entries + [entry]
        i = i + 1
    return entries

def read_file(fs, tree_root, objectid):
    let items = _search_tree(fs, tree_root, objectid, EXTENT_DATA)
    let result = []
    let i = 0
    while i < len(items):
        let item = items[i]
        let data = fs["data"]
        let doff = item["data_offset"]
        let generation = _read_u64(data, doff)
        let ram_bytes = _read_u64(data, doff + 8)
        let compression = _read_u8(data, doff + 16)
        let extent_type = _read_u8(data, doff + 20)
        if extent_type == 0:
            # Inline extent
            let j = 0
            while j < item["size"] - 21:
                result = result + [data[doff + 21 + j]]
                j = j + 1
        if extent_type == 1:
            # Regular extent
            let disk_bytenr = _read_u64(data, doff + 21)
            let disk_num_bytes = _read_u64(data, doff + 29)
            let ext_offset = _read_u64(data, doff + 37)
            let num_bytes = _read_u64(data, doff + 45)
            let start = disk_bytenr + ext_offset
            let j = 0
            while j < num_bytes:
                result = result + [data[start + j]]
                j = j + 1
        i = i + 1
    return result

def subvolume_list(fs):
    let sb = parse_superblock(fs["data"])
    let root_tree = sb["root"]
    let items = parse_leaf(fs, root_tree)
    let subvols = []
    let i = 0
    while i < len(items):
        let k = items[i]["key"]
        if k["type"] == ROOT_ITEM:
            if k["objectid"] >= FIRST_FREE_OBJECTID:
                let sv = {}
                sv["id"] = k["objectid"]
                sv["generation"] = _read_u64(fs["data"], items[i]["data_offset"] + 0)
                sv["root_dirid"] = _read_u64(fs["data"], items[i]["data_offset"] + 8)
                subvols = subvols + [sv]
        i = i + 1
    return subvols

def snapshot_info(fs, subvol_id):
    let sb = parse_superblock(fs["data"])
    let root_tree = sb["root"]
    let items = _search_tree(fs, root_tree, subvol_id, ROOT_ITEM)
    if len(items) == 0:
        return nil
    let item = items[0]
    let data = fs["data"]
    let doff = item["data_offset"]
    let info = {}
    info["id"] = subvol_id
    info["generation"] = _read_u64(data, doff)
    info["root_dirid"] = _read_u64(data, doff + 8)
    info["bytenr"] = _read_u64(data, doff + 16)
    info["flags"] = _read_u64(data, doff + 40)
    return info

def _chunk_logical_to_physical(fs, logical):
    # Simple chunk mapping: parse sys_chunk_array from superblock
    let sb_off = BTRFS_SUPERBLOCK_OFFSET
    let data = fs["data"]
    let array_size = _read_u32(data, sb_off + 152)
    let arr_off = sb_off + 299
    let pos = 0
    while pos < array_size:
        let key = _parse_key(data, arr_off + pos)
        pos = pos + 17
        if key["type"] == CHUNK_ITEM:
            let chunk_size = _read_u64(data, arr_off + pos)
            let chunk_root = _read_u64(data, arr_off + pos + 8)
            let stripe_len = _read_u64(data, arr_off + pos + 16)
            let chunk_type = _read_u64(data, arr_off + pos + 24)
            let num_stripes = _read_u16(data, arr_off + pos + 44)
            let stripe_offset = _read_u64(data, arr_off + pos + 48)
            if logical >= key["offset"]:
                if logical < key["offset"] + chunk_size:
                    let phys = stripe_offset + (logical - key["offset"])
                    return phys
            pos = pos + 48 + 8 + num_stripes * 32
        else:
            break
    # Fallback: identity mapping
    return logical

def create_btrfs(size_bytes):
    let data = _zero_bytes(size_bytes)
    let off = BTRFS_SUPERBLOCK_OFFSET
    # Write magic
    let magic = BTRFS_MAGIC_STR
    let i = 0
    while i < len(magic):
        data[off + 64 + i] = ord(magic[i])
        i = i + 1
    # Basic fields
    _write_u64(data, off + 48, off)
    _write_u64(data, off + 72, 1)
    _write_u64(data, off + 104, size_bytes)
    _write_u32(data, off + 136, 4096)
    _write_u32(data, off + 140, BTRFS_NODE_SIZE)
    _write_u32(data, off + 144, BTRFS_LEAF_SIZE)
    _write_u32(data, off + 148, 4096)
    # Compute and write checksum
    let csum = crc32c(data, off + 32, BTRFS_SUPER_INFO_SIZE - 32)
    _write_u32(data, off, csum)
    let fs = {}
    fs["data"] = data
    return fs
