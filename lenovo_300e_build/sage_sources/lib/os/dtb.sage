# Device Tree Blob (DTB/FDT) parser
# Parses flattened device trees used by ARM64 and RISC-V platforms
# Conforms to the Devicetree Specification v0.4

proc read_u32_be(bs, off):
    return bs[off] * 16777216 + bs[off + 1] * 65536 + bs[off + 2] * 256 + bs[off + 3]
end

proc read_u64_be(bs, off):
    let hi = read_u32_be(bs, off)
    let lo = read_u32_be(bs, off + 4)
    return hi * 4294967296 + lo
end

# FDT magic number: 0xD00DFEED
let FDT_MAGIC = 3490578157

# FDT token types
let FDT_BEGIN_NODE = 1
let FDT_END_NODE = 2
let FDT_PROP = 3
let FDT_NOP = 4
let FDT_END = 9

# Read a null-terminated string from the string block
proc read_string(bs, off):
    let result = ""
    let i = off
    while i < len(bs) and bs[i] != 0:
        result = result + chr(bs[i])
        i = i + 1
    end
    return result
end

# Align offset to 4-byte boundary
proc align4(off):
    return (off + 3) & (0 - 4)
end

# Check if the DTB has valid magic
proc is_valid_dtb(bs):
    if len(bs) < 40:
        return false
    end
    let magic = read_u32_be(bs, 0)
    return magic == 3490578157
end

# Parse the DTB header (40 bytes)
proc parse_header(bs):
    if not is_valid_dtb(bs):
        return nil
    end
    let hdr = {}
    hdr["magic"] = read_u32_be(bs, 0)
    hdr["totalsize"] = read_u32_be(bs, 4)
    hdr["off_dt_struct"] = read_u32_be(bs, 8)
    hdr["off_dt_strings"] = read_u32_be(bs, 12)
    hdr["off_mem_rsvmap"] = read_u32_be(bs, 16)
    hdr["version"] = read_u32_be(bs, 20)
    hdr["last_comp_version"] = read_u32_be(bs, 24)
    hdr["boot_cpuid_phys"] = read_u32_be(bs, 28)
    hdr["size_dt_strings"] = read_u32_be(bs, 32)
    hdr["size_dt_struct"] = read_u32_be(bs, 36)
    return hdr
end

# Parse the memory reservation block
proc parse_mem_reservations(bs, hdr):
    let entries = []
    let off = hdr["off_mem_rsvmap"]
    while off + 16 <= len(bs):
        let addr = read_u64_be(bs, off)
        let size = read_u64_be(bs, off + 8)
        if addr == 0 and size == 0:
            return entries
        end
        let entry = {}
        entry["address"] = addr
        entry["size"] = size
        push(entries, entry)
        off = off + 16
    end
    return entries
end

# Parse a property value as a u32 array
proc prop_as_u32_array(data):
    let result = []
    let i = 0
    while i + 4 <= len(data):
        push(result, read_u32_be(data, i))
        i = i + 4
    end
    return result
end

# Parse a property value as a single u32
proc prop_as_u32(data):
    if len(data) < 4:
        return 0
    end
    return read_u32_be(data, 0)
end

# Parse a property value as a u64
proc prop_as_u64(data):
    if len(data) < 8:
        return 0
    end
    return read_u64_be(data, 0)
end

# Parse a property value as a string
proc prop_as_string(data):
    let result = ""
    for i in range(len(data)):
        if data[i] == 0:
            return result
        end
        result = result + chr(data[i])
    end
    return result
end

# Parse a property value as a string list (null-separated)
proc prop_as_string_list(data):
    let result = []
    let current = ""
    for i in range(len(data)):
        if data[i] == 0:
            if len(current) > 0:
                push(result, current)
            end
            current = ""
        else:
            current = current + chr(data[i])
        end
    end
    if len(current) > 0:
        push(result, current)
    end
    return result
end

# Parse the structure block into a tree of nodes
# Returns the root node as a dict with "name", "properties", "children"
proc parse_tree(bs, hdr):
    let struct_off = hdr["off_dt_struct"]
    let strings_off = hdr["off_dt_strings"]
    let pos = struct_off

    # Stack-based tree builder
    let root = nil
    let stack = []

    while pos + 4 <= len(bs):
        let token = read_u32_be(bs, pos)
        pos = pos + 4

        if token == 1:
            # FDT_BEGIN_NODE: read node name
            let name = read_string(bs, pos)
            let name_len = len(name) + 1
            pos = align4(pos + name_len)
            let node = {}
            node["name"] = name
            node["properties"] = {}
            node["children"] = []
            if root == nil:
                root = node
            else:
                let parent = stack[len(stack) - 1]
                push(parent["children"], node)
            end
            push(stack, node)
        end

        if token == 2:
            # FDT_END_NODE
            if len(stack) > 0:
                pop(stack)
            end
        end

        if token == 3:
            # FDT_PROP: read property
            let prop_len = read_u32_be(bs, pos)
            let name_off = read_u32_be(bs, pos + 4)
            pos = pos + 8
            let prop_name = read_string(bs, strings_off + name_off)
            let prop_data = []
            for i in range(prop_len):
                if pos + i < len(bs):
                    push(prop_data, bs[pos + i])
                end
            end
            pos = align4(pos + prop_len)
            if len(stack) > 0:
                let current = stack[len(stack) - 1]
                current["properties"][prop_name] = prop_data
            end
        end

        if token == 4:
            # FDT_NOP
            let skip = true
        end

        if token == 9:
            # FDT_END
            return root
        end
    end

    return root
end

# Find a node by path (e.g., "/cpus/cpu@0")
proc find_node(root, path):
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
    let node = root
    for i in range(len(parts)):
        let found = false
        let children = node["children"]
        for j in range(len(children)):
            if children[j]["name"] == parts[i]:
                node = children[j]
                found = true
                j = len(children)
            end
        end
        if not found:
            return nil
        end
    end
    return node
end

# Get a property value from a node
proc get_prop(node, name):
    if node == nil:
        return nil
    end
    if dict_has(node["properties"], name):
        return node["properties"][name]
    end
    return nil
end

# Get a property as string
proc get_prop_string(node, name):
    let data = get_prop(node, name)
    if data == nil:
        return nil
    end
    return prop_as_string(data)
end

# Get a property as u32
proc get_prop_u32(node, name):
    let data = get_prop(node, name)
    if data == nil:
        return nil
    end
    return prop_as_u32(data)
end

# Get the "compatible" property as a string list
proc get_compatible(node):
    let data = get_prop(node, "compatible")
    if data == nil:
        return []
    end
    return prop_as_string_list(data)
end

# Check if a node is compatible with a given string
proc is_compatible(node, compat):
    let list = get_compatible(node)
    for i in range(len(list)):
        if list[i] == compat:
            return true
        end
    end
    return false
end

# Find all nodes with a given compatible string
proc find_compatible(root, compat):
    let result = []
    let stack = [root]
    while len(stack) > 0:
        let node = pop(stack)
        if is_compatible(node, compat):
            push(result, node)
        end
        let children = node["children"]
        for i in range(len(children)):
            push(stack, children[i])
        end
    end
    return result
end

# Get the #address-cells and #size-cells for a node
proc get_cell_sizes(node):
    let result = {}
    let ac = get_prop_u32(node, "#address-cells")
    let sc = get_prop_u32(node, "#size-cells")
    if ac == nil:
        result["address_cells"] = 2
    else:
        result["address_cells"] = ac
    end
    if sc == nil:
        result["size_cells"] = 1
    else:
        result["size_cells"] = sc
    end
    return result
end

# Parse a "reg" property given address and size cell counts
proc parse_reg(data, address_cells, size_cells):
    let entry_size = (address_cells + size_cells) * 4
    let entries = []
    let off = 0
    while off + entry_size <= len(data):
        let entry = {}
        if address_cells == 1:
            entry["address"] = read_u32_be(data, off)
        end
        if address_cells == 2:
            entry["address"] = read_u64_be(data, off)
        end
        let size_off = off + address_cells * 4
        if size_cells == 1:
            entry["size"] = read_u32_be(data, size_off)
        end
        if size_cells == 2:
            entry["size"] = read_u64_be(data, size_off)
        end
        push(entries, entry)
        off = off + entry_size
    end
    return entries
end

# Count the number of CPU nodes
proc count_cpus(root):
    let cpus_node = find_node(root, "cpus")
    if cpus_node == nil:
        return 0
    end
    let count = 0
    let children = cpus_node["children"]
    for i in range(len(children)):
        let name = children[i]["name"]
        if len(name) >= 3:
            if name[0] == "c" and name[1] == "p" and name[2] == "u":
                count = count + 1
            end
        end
    end
    return count
end

# Get the model string from the root node
proc get_model(root):
    return get_prop_string(root, "model")
end
