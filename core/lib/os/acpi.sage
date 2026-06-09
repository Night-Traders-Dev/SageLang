# ACPI table parser
# Parses MADT (APIC), FADT, HPET, MCFG, and other common ACPI tables

proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256
end

proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216
end

proc read_u64_le(bs, off):
    let lo = read_u32_le(bs, off)
    let hi = read_u32_le(bs, off + 4)
    return lo + hi * 4294967296
end

# MADT (Multiple APIC Description Table) entry types
let MADT_LOCAL_APIC = 0
let MADT_IO_APIC = 1
let MADT_INT_OVERRIDE = 2
let MADT_NMI_SOURCE = 3
let MADT_LOCAL_APIC_NMI = 4
let MADT_LOCAL_APIC_OVERRIDE = 5
let MADT_LOCAL_X2APIC = 9

proc madt_entry_type_name(t):
    if t == 0:
        return "Local APIC"
    end
    if t == 1:
        return "I/O APIC"
    end
    if t == 2:
        return "Interrupt Override"
    end
    if t == 3:
        return "NMI Source"
    end
    if t == 4:
        return "Local APIC NMI"
    end
    if t == 5:
        return "Local APIC Address Override"
    end
    if t == 9:
        return "Local x2APIC"
    end
    return "Unknown"
end

# Parse SDT header (shared with uefi module but standalone here)
proc parse_sdt_header(bs, off):
    let hdr = {}
    let sig = ""
    for i in range(4):
        sig = sig + chr(bs[off + i])
    end
    hdr["signature"] = sig
    hdr["length"] = read_u32_le(bs, off + 4)
    hdr["revision"] = bs[off + 8]
    hdr["checksum"] = bs[off + 9]
    return hdr
end

# Parse MADT (APIC table, signature "APIC")
proc parse_madt(bs, off):
    let hdr = parse_sdt_header(bs, off)
    if hdr["signature"] != "APIC":
        return nil
    end
    let madt = {}
    madt["header"] = hdr
    madt["local_apic_address"] = read_u32_le(bs, off + 36)
    madt["flags"] = read_u32_le(bs, off + 40)
    madt["has_8259"] = (read_u32_le(bs, off + 40) & 1) != 0

    # Parse variable-length entries
    let entries = []
    let pos = off + 44
    let end_pos = off + hdr["length"]
    while pos + 2 <= end_pos:
        let entry_type = bs[pos]
        let entry_len = bs[pos + 1]
        if entry_len < 2:
            pos = end_pos
        else:
            let entry = {}
            entry["type"] = entry_type
            entry["type_name"] = madt_entry_type_name(entry_type)
            entry["length"] = entry_len

            if entry_type == 0:
                entry["acpi_processor_id"] = bs[pos + 2]
                entry["apic_id"] = bs[pos + 3]
                entry["flags"] = read_u32_le(bs, pos + 4)
                entry["enabled"] = (read_u32_le(bs, pos + 4) & 1) != 0
            end

            if entry_type == 1:
                entry["io_apic_id"] = bs[pos + 2]
                entry["io_apic_address"] = read_u32_le(bs, pos + 4)
                entry["gsi_base"] = read_u32_le(bs, pos + 8)
            end

            if entry_type == 2:
                entry["bus"] = bs[pos + 2]
                entry["source"] = bs[pos + 3]
                entry["gsi"] = read_u32_le(bs, pos + 4)
                entry["flags"] = read_u16_le(bs, pos + 8)
            end

            if entry_type == 4:
                entry["acpi_processor_id"] = bs[pos + 2]
                entry["flags"] = read_u16_le(bs, pos + 3)
                entry["lint"] = bs[pos + 5]
            end

            if entry_type == 5:
                entry["address"] = read_u64_le(bs, pos + 4)
            end

            if entry_type == 9:
                entry["x2apic_id"] = read_u32_le(bs, pos + 4)
                entry["flags"] = read_u32_le(bs, pos + 8)
                entry["acpi_uid"] = read_u32_le(bs, pos + 12)
            end

            push(entries, entry)
            pos = pos + entry_len
        end
    end
    madt["entries"] = entries
    return madt
end

# Count enabled processors in MADT
proc count_processors(madt):
    let count = 0
    let entries = madt["entries"]
    for i in range(len(entries)):
        let e = entries[i]
        if e["type"] == 0 and e["enabled"]:
            count = count + 1
        end
        if e["type"] == 9:
            if (e["flags"] & 1) != 0:
                count = count + 1
            end
        end
    end
    return count
end

# Get I/O APIC entries from MADT
proc get_io_apics(madt):
    let result = []
    let entries = madt["entries"]
    for i in range(len(entries)):
        if entries[i]["type"] == 1:
            push(result, entries[i])
        end
    end
    return result
end

# Parse MCFG (PCI Express memory-mapped configuration)
proc parse_mcfg(bs, off):
    let hdr = parse_sdt_header(bs, off)
    if hdr["signature"] != "MCFG":
        return nil
    end
    let mcfg = {}
    mcfg["header"] = hdr
    # Entries start at offset 44 (after 36-byte SDT header + 8 reserved bytes)
    let entries = []
    let pos = off + 44
    let end_pos = off + hdr["length"]
    while pos + 16 <= end_pos:
        let entry = {}
        entry["base_address"] = read_u64_le(bs, pos)
        entry["segment_group"] = read_u16_le(bs, pos + 8)
        entry["start_bus"] = bs[pos + 10]
        entry["end_bus"] = bs[pos + 11]
        push(entries, entry)
        pos = pos + 16
    end
    mcfg["entries"] = entries
    return mcfg
end

# Parse HPET (High Precision Event Timer)
proc parse_hpet(bs, off):
    let hdr = parse_sdt_header(bs, off)
    if hdr["signature"] != "HPET":
        return nil
    end
    let hpet = {}
    hpet["header"] = hdr
    hpet["hardware_rev_id"] = bs[off + 36]
    let info = bs[off + 37]
    hpet["num_comparators"] = ((info >> 3) & 31) + 1
    hpet["counter_64bit"] = (info & 4) != 0
    hpet["legacy_replacement"] = (info & 2) != 0
    hpet["pci_vendor_id"] = read_u16_le(bs, off + 38)
    # Address structure (GAS - Generic Address Structure)
    hpet["address_space_id"] = bs[off + 40]
    hpet["register_bit_width"] = bs[off + 41]
    hpet["register_bit_offset"] = bs[off + 42]
    hpet["base_address"] = read_u64_le(bs, off + 44)
    hpet["hpet_number"] = bs[off + 52]
    hpet["min_tick"] = read_u16_le(bs, off + 53)
    hpet["page_protection"] = bs[off + 55]
    return hpet
end

# Parse FADT (Fixed ACPI Description Table) - key fields
proc parse_fadt(bs, off):
    let hdr = parse_sdt_header(bs, off)
    if hdr["signature"] != "FACP":
        return nil
    end
    let fadt = {}
    fadt["header"] = hdr
    fadt["firmware_ctrl"] = read_u32_le(bs, off + 36)
    fadt["dsdt"] = read_u32_le(bs, off + 40)
    fadt["preferred_pm_profile"] = bs[off + 45]
    fadt["sci_interrupt"] = read_u16_le(bs, off + 46)
    fadt["smi_command_port"] = read_u32_le(bs, off + 48)
    fadt["acpi_enable"] = bs[off + 52]
    fadt["acpi_disable"] = bs[off + 53]
    fadt["pm1a_event_block"] = read_u32_le(bs, off + 56)
    fadt["pm1b_event_block"] = read_u32_le(bs, off + 60)
    fadt["pm1a_control_block"] = read_u32_le(bs, off + 64)
    fadt["pm_timer_block"] = read_u32_le(bs, off + 76)
    fadt["pm_timer_length"] = bs[off + 89]
    fadt["flags"] = read_u32_le(bs, off + 112)
    # Important FADT flags
    fadt["wbinvd"] = (read_u32_le(bs, off + 112) & 1) != 0
    fadt["proc_c1"] = (read_u32_le(bs, off + 112) & 4) != 0
    fadt["pwr_button"] = (read_u32_le(bs, off + 112) & 16) != 0
    fadt["slp_button"] = (read_u32_le(bs, off + 112) & 32) != 0
    fadt["rtc_s4"] = (read_u32_le(bs, off + 112) & 128) != 0
    fadt["reset_supported"] = (read_u32_le(bs, off + 112) & 1024) != 0
    # Extended addresses (ACPI 2.0+)
    if hdr["length"] >= 244:
        fadt["x_firmware_ctrl"] = read_u64_le(bs, off + 132)
        fadt["x_dsdt"] = read_u64_le(bs, off + 140)
    end
    return fadt
end

# Verify ACPI table checksum
proc verify_checksum(bs, off, length):
    let sum = 0
    for i in range(length):
        sum = sum + bs[off + i]
    end
    return (sum & 255) == 0
end
