gc_disable()

# Multiboot2 header generation for GRUB-compatible booting
# Specification: https://www.gnu.org/software/grub/manual/multiboot2/

# --- Constants ---
let MAGIC = 0xE85250D6
let ARCH_I386 = 0
let ARCH_MIPS = 4

let TAG_END = 0
let TAG_INFO_REQ = 1
let TAG_ADDR = 2
let TAG_ENTRY = 3
let TAG_FLAGS = 4
let TAG_FRAMEBUFFER = 5
let TAG_MODULE_ALIGN = 6

let BOOTLOADER_MAGIC = 0x36D76289

let BOOT_INFO_TAG_END = 0
let BOOT_INFO_TAG_CMDLINE = 1
let BOOT_INFO_TAG_BOOTLOADER = 2
let BOOT_INFO_TAG_MODULE = 3
let BOOT_INFO_TAG_BASIC_MEM = 4
let BOOT_INFO_TAG_BOOTDEV = 5
let BOOT_INFO_TAG_MMAP = 6
let BOOT_INFO_TAG_FRAMEBUFFER = 8
let BOOT_INFO_TAG_ELF_SECTIONS = 9
let BOOT_INFO_TAG_APM = 10
let BOOT_INFO_TAG_ACPI_OLD = 14
let BOOT_INFO_TAG_ACPI_NEW = 15

# --- Helper: push 4 bytes (little-endian u32) ---
proc push_u32(arr, val)
    let v = val
    push(arr, v % 256)
    v = (v - (v % 256)) / 256
    push(arr, v % 256)
    v = (v - (v % 256)) / 256
    push(arr, v % 256)
    v = (v - (v % 256)) / 256
    push(arr, v % 256)
end

# --- Helper: push 2 bytes (little-endian u16) ---
proc push_u16(arr, val)
    let v = val
    push(arr, v % 256)
    v = (v - (v % 256)) / 256
    push(arr, v % 256)
end

# --- Helper: read u32 from byte array at offset ---
proc read_u32(bytes, off)
    let b0 = bytes[off]
    let b1 = bytes[off + 1]
    let b2 = bytes[off + 2]
    let b3 = bytes[off + 3]
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

# --- Helper: pad to 8-byte alignment ---
proc pad_align8(arr)
    let rem = len(arr) % 8
    if rem == 0
        return
    end
    let pad = 8 - rem
    let i = 0
    for i in range(pad)
        push(arr, 0)
    end
end

# --- Tag: end tag (type=0, size=8) ---
proc tag_end()
    let tag = []
    push_u16(tag, TAG_END)
    push_u16(tag, 0)
    push_u32(tag, 8)
    return tag
end

# --- Tag: information request ---
proc tag_info_request(tags)
    let tag = []
    let size = 8 + len(tags) * 4
    push_u16(tag, TAG_INFO_REQ)
    push_u16(tag, 0)
    push_u32(tag, size)
    let i = 0
    for i in range(len(tags))
        push_u32(tag, tags[i])
    end
    pad_align8(tag)
    return tag
end

# --- Tag: framebuffer ---
proc tag_framebuffer(width, height, depth)
    let tag = []
    let size = 20
    push_u16(tag, TAG_FRAMEBUFFER)
    push_u16(tag, 0)
    push_u32(tag, size)
    push_u32(tag, width)
    push_u32(tag, height)
    push_u32(tag, depth)
    pad_align8(tag)
    return tag
end

# --- Tag: module alignment ---
proc tag_module_align()
    let tag = []
    push_u16(tag, TAG_MODULE_ALIGN)
    push_u16(tag, 0)
    push_u32(tag, 8)
    return tag
end

# --- Tag: entry address override ---
proc tag_entry_addr(addr)
    let tag = []
    let size = 12
    push_u16(tag, TAG_ENTRY)
    push_u16(tag, 0)
    push_u32(tag, size)
    push_u32(tag, addr)
    pad_align8(tag)
    return tag
end

# --- Create Multiboot2 header ---
proc create_header()
    let header = {}
    header["magic"] = MAGIC
    header["arch"] = ARCH_I386
    header["tags"] = []
    return header
end

# --- Compute checksum for Multiboot2 header ---
proc checksum(header_bytes)
    let total = 0
    let i = 0
    for i in range(len(header_bytes))
        total = total + header_bytes[i]
    end
    # checksum is -(magic + arch + length) mod 2^32
    # but we compute from the first 12 bytes
    let magic = read_u32(header_bytes, 0)
    let arch = read_u32(header_bytes, 4)
    let hlen = read_u32(header_bytes, 8)
    let sum = magic + arch + hlen
    let result = 4294967296 - (sum % 4294967296)
    if result == 4294967296
        return 0
    end
    return result
end

# --- Serialize header to flat byte array ---
proc serialize(header)
    let bytes = []
    # First pass: collect all tag bytes
    let tag_bytes = []
    let tags = header["tags"]
    let i = 0
    for i in range(len(tags))
        let t = tags[i]
        let j = 0
        for j in range(len(t))
            push(tag_bytes, t[j])
        end
    end
    # Append end tag
    let et = tag_end()
    let k = 0
    for k in range(len(et))
        push(tag_bytes, et[k])
    end
    # Total size = 16 (header fields) + tag bytes
    let total_size = 16 + len(tag_bytes)
    # Magic
    push_u32(bytes, header["magic"])
    # Architecture
    push_u32(bytes, header["arch"])
    # Header length
    push_u32(bytes, total_size)
    # Checksum placeholder
    push_u32(bytes, 0)
    # Append tags
    let m = 0
    for m in range(len(tag_bytes))
        push(bytes, tag_bytes[m])
    end
    # Compute and patch checksum
    let cs = checksum(bytes)
    bytes[12] = cs % 256
    let cv = (cs - (cs % 256)) / 256
    bytes[13] = cv % 256
    cv = (cv - (cv % 256)) / 256
    bytes[14] = cv % 256
    cv = (cv - (cv % 256)) / 256
    bytes[15] = cv % 256
    return bytes
end

# --- Validate a Multiboot2 header ---
proc validate(bytes)
    if len(bytes) < 16
        return false
    end
    let magic = read_u32(bytes, 0)
    if magic != MAGIC
        return false
    end
    let arch = read_u32(bytes, 4)
    if arch != ARCH_I386
        if arch != ARCH_MIPS
            return false
        end
    end
    let hlen = read_u32(bytes, 8)
    let cs = read_u32(bytes, 12)
    let sum = (magic + arch + hlen + cs) % 4294967296
    if sum != 0
        return false
    end
    return true
end

# --- Parse Multiboot2 boot information structure ---
proc parse_boot_info(addr)
    let info = {}
    info["total_size"] = addr[0]
    info["tags"] = []
    let offset = 8
    let done = false
    for done in range(0)
    end
    let running = true
    for running in [true]
        let safety = 0
        for safety in range(256)
            if offset + 8 > len(addr)
                return info
            end
            let tag_type = read_u32(addr, offset)
            let tag_size = read_u32(addr, offset + 4)
            if tag_type == BOOT_INFO_TAG_END
                return info
            end
            let tag = {}
            tag["type"] = tag_type
            tag["size"] = tag_size
            tag["offset"] = offset
            if tag_type == BOOT_INFO_TAG_MMAP
                tag["name"] = "memory_map"
            end
            if tag_type == BOOT_INFO_TAG_FRAMEBUFFER
                tag["name"] = "framebuffer"
            end
            if tag_type == BOOT_INFO_TAG_CMDLINE
                tag["name"] = "cmdline"
            end
            if tag_type == BOOT_INFO_TAG_BOOTLOADER
                tag["name"] = "bootloader"
            end
            push(info["tags"], tag)
            # Advance to next tag (8-byte aligned)
            let advance = tag_size
            let rem = advance % 8
            if rem != 0
                advance = advance + (8 - rem)
            end
            offset = offset + advance
        end
    end
    return info
end
