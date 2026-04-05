# PCI Configuration Space parser
# Parses PCI device config headers (Type 0 and Type 1)
# Useful for OS development and hardware enumeration

proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256
end

proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216
end

# PCI class code constants
let PCI_CLASS_UNCLASSIFIED = 0
let PCI_CLASS_MASS_STORAGE = 1
let PCI_CLASS_NETWORK = 2
let PCI_CLASS_DISPLAY = 3
let PCI_CLASS_MULTIMEDIA = 4
let PCI_CLASS_MEMORY = 5
let PCI_CLASS_BRIDGE = 6
let PCI_CLASS_SIMPLE_COMM = 7
let PCI_CLASS_BASE_PERIPH = 8
let PCI_CLASS_INPUT = 9
let PCI_CLASS_SERIAL_BUS = 12
let PCI_CLASS_WIRELESS = 13

# Subclass constants for common classes
let PCI_SUBCLASS_IDE = 1
let PCI_SUBCLASS_SATA = 6
let PCI_SUBCLASS_NVME = 8
let PCI_SUBCLASS_ETHERNET = 0
let PCI_SUBCLASS_VGA = 0
let PCI_SUBCLASS_3D = 2
let PCI_SUBCLASS_HOST_BRIDGE = 0
let PCI_SUBCLASS_ISA_BRIDGE = 1
let PCI_SUBCLASS_PCI_BRIDGE = 4
let PCI_SUBCLASS_USB = 3
let PCI_SUBCLASS_SMBUS = 5

# Well-known vendor IDs
let PCI_VENDOR_INTEL = 32902
let PCI_VENDOR_AMD = 4098
let PCI_VENDOR_NVIDIA = 4318
let PCI_VENDOR_QEMU = 6900
let PCI_VENDOR_VIRTIO = 6900
let PCI_VENDOR_BROADCOM = 5348
let PCI_VENDOR_REALTEK = 4332

proc class_name(cls):
    if cls == 0:
        return "Unclassified"
    end
    if cls == 1:
        return "Mass Storage"
    end
    if cls == 2:
        return "Network"
    end
    if cls == 3:
        return "Display"
    end
    if cls == 4:
        return "Multimedia"
    end
    if cls == 5:
        return "Memory"
    end
    if cls == 6:
        return "Bridge"
    end
    if cls == 7:
        return "Simple Communication"
    end
    if cls == 8:
        return "Base System Peripheral"
    end
    if cls == 9:
        return "Input Device"
    end
    if cls == 12:
        return "Serial Bus"
    end
    if cls == 13:
        return "Wireless"
    end
    return "Unknown"
end

proc vendor_name(vid):
    if vid == 32902:
        return "Intel"
    end
    if vid == 4098:
        return "AMD"
    end
    if vid == 4318:
        return "NVIDIA"
    end
    if vid == 6900:
        return "QEMU/VirtIO"
    end
    if vid == 5348:
        return "Broadcom"
    end
    if vid == 4332:
        return "Realtek"
    end
    if vid == 65535:
        return "Invalid"
    end
    return "Unknown"
end

# Build a BDF (Bus/Device/Function) address
proc bdf(bus, device, function):
    let addr = {}
    addr["bus"] = bus
    addr["device"] = device
    addr["function"] = function
    addr["value"] = (bus << 8) + (device << 3) + function
    return addr
end

# Calculate config space address for ECAM (PCIe extended config)
proc ecam_offset(bdf_addr, register):
    return (bdf_addr["bus"] << 20) + (bdf_addr["device"] << 15) + (bdf_addr["function"] << 12) + register
end

# Parse PCI configuration space header (first 64 bytes)
proc parse_config(bs):
    if len(bs) < 64:
        return nil
    end
    let cfg = {}
    cfg["vendor_id"] = read_u16_le(bs, 0)
    cfg["device_id"] = read_u16_le(bs, 2)
    cfg["vendor_name"] = vendor_name(read_u16_le(bs, 0))

    # Check for invalid/absent device
    if cfg["vendor_id"] == 65535:
        cfg["present"] = false
        return cfg
    end
    cfg["present"] = true

    cfg["command"] = read_u16_le(bs, 4)
    cfg["status"] = read_u16_le(bs, 6)
    cfg["revision_id"] = bs[8]
    cfg["prog_if"] = bs[9]
    cfg["subclass"] = bs[10]
    cfg["class_code"] = bs[11]
    cfg["class_name"] = class_name(bs[11])
    cfg["cache_line_size"] = bs[12]
    cfg["latency_timer"] = bs[13]
    cfg["header_type"] = bs[14] & 127
    cfg["multifunction"] = (bs[14] & 128) != 0
    cfg["bist"] = bs[15]

    # Command register bits
    cfg["io_enabled"] = (read_u16_le(bs, 4) & 1) != 0
    cfg["memory_enabled"] = (read_u16_le(bs, 4) & 2) != 0
    cfg["bus_master"] = (read_u16_le(bs, 4) & 4) != 0
    cfg["interrupt_disable"] = (read_u16_le(bs, 4) & 1024) != 0

    # Status register bits
    cfg["capabilities_list"] = (read_u16_le(bs, 6) & 16) != 0

    if cfg["header_type"] == 0:
        # Type 0: General device
        cfg["bar0"] = read_u32_le(bs, 16)
        cfg["bar1"] = read_u32_le(bs, 20)
        cfg["bar2"] = read_u32_le(bs, 24)
        cfg["bar3"] = read_u32_le(bs, 28)
        cfg["bar4"] = read_u32_le(bs, 32)
        cfg["bar5"] = read_u32_le(bs, 36)
        cfg["cardbus_cis"] = read_u32_le(bs, 40)
        cfg["subsystem_vendor_id"] = read_u16_le(bs, 44)
        cfg["subsystem_id"] = read_u16_le(bs, 46)
        cfg["expansion_rom"] = read_u32_le(bs, 48)
        cfg["capabilities_ptr"] = bs[52]
        cfg["interrupt_line"] = bs[60]
        cfg["interrupt_pin"] = bs[61]
        cfg["min_grant"] = bs[62]
        cfg["max_latency"] = bs[63]
    end

    if cfg["header_type"] == 1:
        # Type 1: PCI-to-PCI bridge
        cfg["bar0"] = read_u32_le(bs, 16)
        cfg["bar1"] = read_u32_le(bs, 20)
        cfg["primary_bus"] = bs[24]
        cfg["secondary_bus"] = bs[25]
        cfg["subordinate_bus"] = bs[26]
        cfg["secondary_latency"] = bs[27]
        cfg["io_base"] = bs[28]
        cfg["io_limit"] = bs[29]
        cfg["secondary_status"] = read_u16_le(bs, 30)
        cfg["memory_base"] = read_u16_le(bs, 32)
        cfg["memory_limit"] = read_u16_le(bs, 34)
        cfg["prefetch_base"] = read_u16_le(bs, 36)
        cfg["prefetch_limit"] = read_u16_le(bs, 38)
        cfg["capabilities_ptr"] = bs[52]
        cfg["interrupt_line"] = bs[60]
        cfg["interrupt_pin"] = bs[61]
        cfg["bridge_control"] = read_u16_le(bs, 62)
    end

    return cfg
end

# Decode a BAR (Base Address Register)
proc decode_bar(bar_value):
    let bar = {}
    bar["raw"] = bar_value
    bar["is_io"] = (bar_value & 1) != 0
    if bar["is_io"]:
        bar["address"] = bar_value & 4294967292
        bar["type"] = "io"
    else:
        bar["type"] = "memory"
        bar["prefetchable"] = (bar_value & 8) != 0
        let mem_type = (bar_value >> 1) & 3
        bar["is_64bit"] = mem_type == 2
        bar["address"] = bar_value & 4294967280
    end
    return bar
end

# Parse capability list from config space
proc parse_capabilities(bs, start_offset):
    let caps = []
    let off = start_offset
    let seen = 0
    while off != 0 and seen < 48:
        if off + 2 > len(bs):
            return caps
        end
        let cap = {}
        cap["id"] = bs[off]
        cap["next"] = bs[off + 1]
        cap["offset"] = off
        if bs[off] == 1:
            cap["name"] = "Power Management"
        end
        if bs[off] == 5:
            cap["name"] = "MSI"
        end
        if bs[off] == 16:
            cap["name"] = "PCIe"
        end
        if bs[off] == 17:
            cap["name"] = "MSI-X"
        end
        if bs[off] == 9:
            cap["name"] = "Vendor Specific"
        end
        if not dict_has(cap, "name"):
            cap["name"] = "Unknown"
        end
        push(caps, cap)
        off = bs[off + 1]
        seen = seen + 1
    end
    return caps
end

# Enumerate all devices on a bus (given an array of 256 config space blocks)
proc enumerate_bus(config_blocks):
    let devices = []
    for dev in range(32):
        for func in range(8):
            let idx = dev * 8 + func
            if idx < len(config_blocks):
                let cfg = parse_config(config_blocks[idx])
                if cfg != nil and cfg["present"]:
                    cfg["device_num"] = dev
                    cfg["function_num"] = func
                    push(devices, cfg)
                    # If not multifunction, skip remaining functions
                    if func == 0 and not cfg["multifunction"]:
                        func = 8
                    end
                end
            end
        end
    end
    return devices
end
