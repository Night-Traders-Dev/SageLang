gc_disable()

# cpio.sage — CPIO archive format (newc/initramfs)
#
# Create and parse CPIO archives for Linux initramfs images.
# Supports newc (SVR4 with CRC) format used by the Linux kernel.

# ----- CPIO newc format -----
# Each entry: 110-byte header + filename + padding + file data + padding
# Magic: "070701" (newc) or "070702" (newc with CRC)

let CPIO_MAGIC = "070701"
let CPIO_TRAILER = "TRAILER!!!"

# File type bits (mode >> 12)
let CPIO_REG = 32768
let CPIO_DIR = 16384
let CPIO_LNK = 40960
let CPIO_CHR = 8192
let CPIO_BLK = 24576
let CPIO_FIFO = 4096
let CPIO_SOCK = 49152

# ========== Hex encoding helpers ==========

proc _hex_digit(n):
    if n < 10:
        return chr(48 + n)
    end
    return chr(55 + n)
end

proc _to_hex8(val):
    let s = ""
    for i in range(8):
        let shift = (7 - i) * 4
        let nibble = (val >> shift) & 15
        s = s + _hex_digit(nibble)
    end
    return s
end

proc _from_hex8(data, off):
    let val = 0
    for i in range(8):
        let c = data[off + i]
        let d = 0
        if ord(c) >= 48 and ord(c) <= 57:
            d = ord(c) - 48
        end
        if ord(c) >= 65 and ord(c) <= 70:
            d = ord(c) - 55
        end
        if ord(c) >= 97 and ord(c) <= 102:
            d = ord(c) - 87
        end
        val = val * 16 + d
    end
    return val
end

# ========== CPIO Entry ==========

proc create_entry(name, data, mode, uid, gid):
    let entry = {}
    entry["name"] = name
    entry["data"] = data
    entry["mode"] = mode
    entry["uid"] = uid
    entry["gid"] = gid
    entry["nlink"] = 1
    entry["mtime"] = 0
    entry["devmajor"] = 0
    entry["devminor"] = 0
    entry["rdevmajor"] = 0
    entry["rdevminor"] = 0
    return entry
end

proc create_file(name, data):
    return create_entry(name, data, CPIO_REG + 420, 0, 0)
end

proc create_dir(name):
    return create_entry(name, "", CPIO_DIR + 493, 0, 0)
end

proc create_symlink(name, target):
    return create_entry(name, target, CPIO_LNK + 511, 0, 0)
end

proc create_device(name, dev_type, major, minor):
    let entry = create_entry(name, "", dev_type + 438, 0, 0)
    entry["rdevmajor"] = major
    entry["rdevminor"] = minor
    return entry
end

proc create_char_device(name, major, minor):
    return create_device(name, CPIO_CHR, major, minor)
end

proc create_block_device(name, major, minor):
    return create_device(name, CPIO_BLK, major, minor)
end

# ========== Archive Builder ==========

proc create_archive():
    let archive = {}
    archive["entries"] = []
    return archive
end

proc add_entry(archive, entry):
    push(archive["entries"], entry)
    return archive
end

proc add_file(archive, name, data):
    return add_entry(archive, create_file(name, data))
end

proc add_dir(archive, name):
    return add_entry(archive, create_dir(name))
end

proc add_symlink(archive, name, target):
    return add_entry(archive, create_symlink(name, target))
end

# Add standard Linux directory structure
proc add_initramfs_dirs(archive):
    archive = add_dir(archive, "bin")
    archive = add_dir(archive, "sbin")
    archive = add_dir(archive, "etc")
    archive = add_dir(archive, "proc")
    archive = add_dir(archive, "sys")
    archive = add_dir(archive, "dev")
    archive = add_dir(archive, "tmp")
    archive = add_dir(archive, "lib")
    archive = add_dir(archive, "lib/modules")
    archive = add_dir(archive, "var")
    archive = add_dir(archive, "var/run")
    archive = add_dir(archive, "root")
    return archive
end

# Add standard device nodes
proc add_initramfs_devices(archive):
    archive = add_entry(archive, create_char_device("dev/console", 5, 1))
    archive = add_entry(archive, create_char_device("dev/tty", 5, 0))
    archive = add_entry(archive, create_char_device("dev/null", 1, 3))
    archive = add_entry(archive, create_char_device("dev/zero", 1, 5))
    archive = add_entry(archive, create_char_device("dev/random", 1, 8))
    archive = add_entry(archive, create_char_device("dev/urandom", 1, 9))
    return archive
end

# ========== Serialization (newc format) ==========

proc _align4(n):
    if n % 4 == 0:
        return n
    end
    return n + (4 - (n % 4))
end

proc serialize(archive):
    let out = []
    let ino = 1
    for ei in range(len(archive["entries"])):
        let e = archive["entries"][ei]
        let name = e["name"]
        let data = e["data"]
        let namesize = len(name) + 1
        let filesize = len(data)
        # Header (110 bytes ASCII hex)
        let hdr = CPIO_MAGIC
        hdr = hdr + _to_hex8(ino)
        hdr = hdr + _to_hex8(e["mode"])
        hdr = hdr + _to_hex8(e["uid"])
        hdr = hdr + _to_hex8(e["gid"])
        hdr = hdr + _to_hex8(e["nlink"])
        hdr = hdr + _to_hex8(e["mtime"])
        hdr = hdr + _to_hex8(filesize)
        hdr = hdr + _to_hex8(e["devmajor"])
        hdr = hdr + _to_hex8(e["devminor"])
        hdr = hdr + _to_hex8(e["rdevmajor"])
        hdr = hdr + _to_hex8(e["rdevminor"])
        hdr = hdr + _to_hex8(namesize)
        hdr = hdr + _to_hex8(0)
        # Write header bytes
        for hi in range(len(hdr)):
            push(out, ord(hdr[hi]))
        end
        # Write filename + null
        for ni in range(len(name)):
            push(out, ord(name[ni]))
        end
        push(out, 0)
        # Pad to 4-byte boundary
        let total_hdr = 110 + namesize
        while len(out) % 4 != 0:
            push(out, 0)
        end
        # Write file data
        for di in range(len(data)):
            if type(data) == "string":
                push(out, ord(data[di]))
            else:
                push(out, data[di])
            end
        end
        # Pad data to 4-byte boundary
        while len(out) % 4 != 0:
            push(out, 0)
        end
        ino = ino + 1
    end
    # Write trailer entry
    let trailer = CPIO_MAGIC
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(1)
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(0)
    trailer = trailer + _to_hex8(11)
    trailer = trailer + _to_hex8(0)
    for ti in range(len(trailer)):
        push(out, ord(trailer[ti]))
    end
    let tname = CPIO_TRAILER
    for ti in range(len(tname)):
        push(out, ord(tname[ti]))
    end
    push(out, 0)
    while len(out) % 4 != 0:
        push(out, 0)
    end
    # Pad to 512-byte boundary (block alignment)
    while len(out) % 512 != 0:
        push(out, 0)
    end
    return out
end

# ========== Parser ==========

proc parse_archive(data):
    let entries = []
    let off = 0
    while off + 110 <= len(data):
        # Read magic
        let magic = ""
        for i in range(6):
            magic = magic + chr(data[off + i])
        end
        if magic != CPIO_MAGIC and magic != "070702":
            break
        end
        let ino = _from_hex8(data, off + 6)
        let mode = _from_hex8(data, off + 14)
        let uid = _from_hex8(data, off + 22)
        let gid = _from_hex8(data, off + 30)
        let nlink = _from_hex8(data, off + 38)
        let mtime = _from_hex8(data, off + 46)
        let filesize = _from_hex8(data, off + 54)
        let namesize = _from_hex8(data, off + 94)
        # Read name
        let name = ""
        for ni in range(namesize - 1):
            name = name + chr(data[off + 110 + ni])
        end
        if name == CPIO_TRAILER:
            break
        end
        # Skip to data (align header+name to 4)
        let data_off = _align4(off + 110 + namesize)
        # Read data
        let fdata = ""
        for di in range(filesize):
            if data_off + di < len(data):
                fdata = fdata + chr(data[data_off + di])
            end
        end
        let entry = {}
        entry["name"] = name
        entry["data"] = fdata
        entry["mode"] = mode
        entry["uid"] = uid
        entry["gid"] = gid
        entry["nlink"] = nlink
        entry["mtime"] = mtime
        entry["size"] = filesize
        entry["is_dir"] = (mode & 61440) == CPIO_DIR
        entry["is_file"] = (mode & 61440) == CPIO_REG
        entry["is_symlink"] = (mode & 61440) == CPIO_LNK
        push(entries, entry)
        # Next entry
        off = _align4(data_off + filesize)
    end
    return entries
end

# ========== Convenience ==========

proc create_initramfs(init_script):
    let archive = create_archive()
    archive = add_initramfs_dirs(archive)
    archive = add_initramfs_devices(archive)
    archive = add_file(archive, "init", init_script)
    return serialize(archive)
end

proc list_archive(data):
    let entries = parse_archive(data)
    let listing = []
    for i in range(len(entries)):
        let e = entries[i]
        let line = ""
        if e["is_dir"]:
            line = "d "
        end
        if e["is_file"]:
            line = "- "
        end
        if e["is_symlink"]:
            line = "l "
        end
        if not e["is_dir"] and not e["is_file"] and not e["is_symlink"]:
            line = "? "
        end
        line = line + str(e["size"]) + " " + e["name"]
        push(listing, line)
    end
    return listing
end
