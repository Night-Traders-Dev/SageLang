## os.boot.e820 — BIOS Memory Map (E820)
## Handles collection, sorting, and normalization of the memory map from BIOS INT 0x15.

let TYPE_USABLE      = 1
let TYPE_RESERVED    = 2
let TYPE_ACPI_TABLES = 3
let TYPE_ACPI_NVS    = 4
let TYPE_BAD         = 5

## Collect the memory map into an array of entries.
proc collect():
    # In a real environment this would be populated by BIOS call
    return []
end

## Collect the memory map into an array of entries.
## This generates the assembly to be called from a bootloader.
proc collect_asm(dest_label):
    import os.boot.bios as bios
    let NL = chr(10)
    let TAB = chr(9)
    let asm = ""
    asm = asm + emit_label(".Le820_collect")
    asm = asm + TAB + "xorl %ebx, %ebx" + NL
    asm = asm + TAB + "movw $" + dest_label + ", %di" + NL
    asm = asm + emit_label(".Le820_loop")
    asm = asm + bios.e820_next(".Le820_loop")
    asm = asm + TAB + "jc .Le820_done" + NL
    asm = asm + TAB + "cmpl $0x534D4150, %eax" + NL # Check SMAP
    asm = asm + TAB + "jne .Le820_error" + NL
    asm = asm + TAB + "addw $24, %di" + NL
    asm = asm + TAB + "testl %ebx, %ebx" + NL
    asm = asm + TAB + "jnz .Le820_loop" + NL
    asm = asm + emit_label(".Le820_done")
    # ...
    return asm
end

## Filter usable regions from a collected memory map
proc filter_usable(mmap):
    let usable = []
    for entry in mmap:
        if entry["type"] == TYPE_USABLE:
            push(usable, entry)
        end
    end
    return usable
end

## Find the highest usable physical address
proc highest_usable(mmap):
    let max_addr = 0
    for entry in mmap:
        if entry["type"] == TYPE_USABLE:
            let end_addr = entry["base"] + entry["len"]
            if end_addr > max_addr:
                max_addr = end_addr
            end
        end
    end
    return max_addr
end

## Normalize the map: sort, merge overlapping regions, fill gaps with RESERVED
proc to_regions(mmap):
    # Sort by base address
    # (Simplified: assume bubble sort or similar if no std sort)
    let sorted = sort_mmap(mmap)
    
    let regions = []
    # Logic to merge and fill gaps
    # ...
    return regions
end

proc sort_mmap(mmap):
    # Placeholder for sorting logic
    return mmap
end

proc emit_label(name):
    return name + ":" + chr(10)
end
