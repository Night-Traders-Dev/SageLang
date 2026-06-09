gc_disable()

# Flattened Device Tree (DTB) parser
# Parses binary DTB blobs as used by ARM/RISC-V firmware and QEMU

# --- FDT structure token constants ---
comptime:
    let FDT_MAGIC = 3490578157
    let FDT_BEGIN_NODE = 1
    let FDT_END_NODE = 2
    let FDT_PROP = 3
    let FDT_NOP = 4
    let FDT_END = 9
end

# Default QEMU DTB load addresses
comptime:
    let QEMU_DTB_ADDR_ARM = 1073741824
    let QEMU_DTB_ADDR_RISCV = 2214592512
end

let NL = chr(10)
let TAB = chr(9)

# --- Read a big-endian u32 from a byte array at the given offset ---
@inline
proc read_u32_be(bytes, offset):
    let b0 = bytes[offset]
    let b1 = bytes[offset + 1]
    let b2 = bytes[offset + 2]
    let b3 = bytes[offset + 3]
    return ((b0 * 16777216) + (b1 * 65536) + (b2 * 256) + b3)
end

# --- Parse a DTB header from raw bytes ---
# Returns a dict with: magic, totalsize, off_dt_struct, off_dt_strings,
# off_mem_rsvmap, version, last_comp_version, boot_cpuid_phys, size_dt_strings, size_dt_struct
proc parse_dtb_header(bytes):
    let header = {}
    let magic = read_u32_be(bytes, 0)
    if magic != FDT_MAGIC:
        print("dtb: invalid magic: expected 0xD00DFEED")
        return nil
    end
    header["magic"] = magic
    header["totalsize"] = read_u32_be(bytes, 4)
    header["off_dt_struct"] = read_u32_be(bytes, 8)
    header["off_dt_strings"] = read_u32_be(bytes, 12)
    header["off_mem_rsvmap"] = read_u32_be(bytes, 16)
    header["version"] = read_u32_be(bytes, 20)
    header["last_comp_version"] = read_u32_be(bytes, 24)
    header["boot_cpuid_phys"] = read_u32_be(bytes, 28)
    header["size_dt_strings"] = read_u32_be(bytes, 32)
    header["size_dt_struct"] = read_u32_be(bytes, 36)
    return header
end

# --- Read a null-terminated string from a byte array ---
@inline
proc read_cstring(bytes, offset):
    let s = ""
    let i = offset
    while i < len(bytes):
        let ch = bytes[i]
        if ch == 0:
            return s
        end
        s = s + chr(ch)
        i = i + 1
    end
    return s
end

# --- Align offset up to 4-byte boundary ---
@inline
proc align4(offset):
    let rem = offset % 4
    if rem != 0:
        return offset + (4 - rem)
    end
    return offset
end

# --- Read a property name from the strings block ---
@inline
proc read_string_at(bytes, strings_offset, nameoff):
    return read_cstring(bytes, strings_offset + nameoff)
end

# --- Walk structure block to find a node by path ---
# path: e.g. "/memory" or "/cpus/cpu@0"
# Returns a dict with "name" and "properties" (dict of name -> byte arrays),
# or nil if not found.
proc find_node(bytes, header, path):
    let struct_off = header["off_dt_struct"]
    let strings_off = header["off_dt_strings"]
    let total = header["totalsize"]
    let offset = struct_off

    # Split path into components
    let parts = []
    let current = ""
    let pi = 1
    while pi < len(path):
        let c = path[pi]
        if c == "/":
            if current != "":
                push(parts, current)
            end
            current = ""
        else:
            current = current + c
        end
        pi = pi + 1
    end
    if current != "":
        push(parts, current)
    end

    let depth = 0
    let match_depth = 0
    let target_depth = len(parts)
    let found = false
    let node = {}
    node["name"] = path
    node["properties"] = {}

    while offset < total:
        let token = read_u32_be(bytes, offset)
        offset = offset + 4

        if token == FDT_BEGIN_NODE:
            let name = read_cstring(bytes, offset)
            let name_len = len(name) + 1
            offset = align4(offset + name_len)

            if found == false:
                if depth == match_depth:
                    if match_depth < target_depth:
                        if name == parts[match_depth]:
                            match_depth = match_depth + 1
                            if match_depth == target_depth:
                                found = true
                            end
                        end
                    end
                end
            end
            depth = depth + 1

        else if token == FDT_END_NODE:
            depth = depth - 1
            if found:
                if depth < (len(parts)):
                    return node
                end
            end
            if found == false:
                if match_depth > depth:
                    match_depth = depth
                end
            end

        else if token == FDT_PROP:
            let prop_len = read_u32_be(bytes, offset)
            let nameoff = read_u32_be(bytes, offset + 4)
            offset = offset + 8
            if found:
                let pname = read_string_at(bytes, strings_off, nameoff)
                let pval = []
                let vi = 0
                while vi < prop_len:
                    push(pval, bytes[offset + vi])
                    vi = vi + 1
                end
                node["properties"][pname] = pval
            end
            offset = align4(offset + prop_len)

        else if token == FDT_NOP:
            # skip

        else if token == FDT_END:
            break
        else:
            break
        end end end end end
    end

    if found:
        return node
    end
    return nil
end

# --- Get a named property value from a parsed node ---
# node: dict returned by find_node (has "properties" key)
# name: property name string
# Returns the property byte array, or nil if not found.
@inline
proc get_property(node, name):
    if node == nil:
        return nil
    end
    let props = node["properties"]
    if dict_has(props, name):
        return props[name]
    end
    return nil
end

# --- Parse /memory nodes to extract base + size pairs ---
# Returns an array of dicts, each with "base" and "size" keys (as integers).
# Assumes #address-cells = 2 and #size-cells = 2 (64-bit values).
proc find_memory_regions(bytes):
    let header = parse_dtb_header(bytes)
    if header == nil:
        return []
    end

    let mem_node = find_node(bytes, header, "/memory")
    if mem_node == nil:
        # Try /memory@0 as used by some firmware
        mem_node = find_node(bytes, header, "/memory@0")
    end
    if mem_node == nil:
        return []
    end

    let reg = get_property(mem_node, "reg")
    if reg == nil:
        return []
    end

    let regions = []
    let offset = 0
    # Each entry: 8 bytes base (u64 BE) + 8 bytes size (u64 BE)
    while (offset + 16) <= len(reg):
        let base_hi = read_u32_be(reg, offset)
        let base_lo = read_u32_be(reg, offset + 4)
        let size_hi = read_u32_be(reg, offset + 8)
        let size_lo = read_u32_be(reg, offset + 12)

        let region = {}
        region["base"] = (base_hi * 4294967296) + base_lo
        region["size"] = (size_hi * 4294967296) + size_lo
        push(regions, region)
        offset = offset + 16
    end

    return regions
end

# --- Count CPU nodes under /cpus ---
# Walks the /cpus node and counts child nodes named cpu@N.
proc find_cpu_count(bytes):
    let header = parse_dtb_header(bytes)
    if header == nil:
        return 0
    end

    let struct_off = header["off_dt_struct"]
    let total = header["totalsize"]
    let offset = struct_off

    # First find the /cpus node
    let depth = 0
    let in_cpus = false
    let cpus_depth = 0
    let count = 0

    while offset < total:
        let token = read_u32_be(bytes, offset)
        offset = offset + 4

        if token == FDT_BEGIN_NODE:
            let name = read_cstring(bytes, offset)
            let name_len = len(name) + 1
            offset = align4(offset + name_len)

            if in_cpus:
                if depth == (cpus_depth + 1):
                    if startswith(name, "cpu@"):
                        count = count + 1
                    end
                end
            else:
                if depth == 1:
                    if name == "cpus":
                        in_cpus = true
                        cpus_depth = depth
                    end
                end
            end
            depth = depth + 1

        else if token == FDT_END_NODE:
            depth = depth - 1
            if in_cpus:
                if depth < cpus_depth:
                    return count
                end
            end

        else if token == FDT_PROP:
            let prop_len = read_u32_be(bytes, offset)
            offset = align4(offset + 8 + prop_len)

        else if token == FDT_NOP:
            # skip

        else if token == FDT_END:
            break
        else:
            break
        end end end end end
    end

    return count
end
