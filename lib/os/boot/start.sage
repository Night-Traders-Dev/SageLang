gc_disable()

# x86_64 startup assembly generation
# Generates boot assembly for transitioning from 32-bit protected mode to 64-bit long mode

# --- Constants ---
let KERNEL_STACK_SIZE = 16384
let KERNEL_BASE = 1048576
let PAGE_PRESENT = 1
let PAGE_WRITABLE = 2
let PAGE_LARGE = 128
let CR0_PE = 1
let CR0_PG = 2147483648
let CR4_PAE = 32
let EFER_MSR = 3221225600
let EFER_LME = 256
let NL = chr(10)
let TAB = chr(9)

# --- Helper: emit an assembly instruction ---
proc emit_asm(instruction, operands):
    if operands == "":
        return TAB + instruction + NL
    end
    return TAB + instruction + " " + operands + NL
end

# --- Helper: emit a label ---
proc emit_label(name):
    return name + ":" + NL
end

# --- Helper: emit a section directive ---
proc emit_section(name):
    return ".section " + name + NL
end

# --- Generate Multiboot2 header in assembly ---
proc generate_multiboot_header():
    let asm = ""
    asm = asm + emit_section(".multiboot")
    asm = asm + ".align 8" + NL
    asm = asm + emit_label("multiboot_header")
    asm = asm + emit_asm(".long", "0xE85250D6")
    asm = asm + emit_asm(".long", "0")
    asm = asm + emit_asm(".long", "multiboot_header_end - multiboot_header")
    asm = asm + emit_asm(".long", "-(0xE85250D6 + 0 + (multiboot_header_end - multiboot_header))")
    # End tag
    asm = asm + emit_asm(".short", "0")
    asm = asm + emit_asm(".short", "0")
    asm = asm + emit_asm(".long", "8")
    asm = asm + emit_label("multiboot_header_end")
    asm = asm + NL
    return asm
end

# --- Generate page table setup (identity map first 4GB) ---
proc generate_page_tables():
    let asm = ""
    asm = asm + emit_section(".bss")
    asm = asm + ".align 4096" + NL
    # PML4 table
    asm = asm + emit_label("pml4_table")
    asm = asm + emit_asm(".skip", "4096")
    # PDP table (Page Directory Pointer)
    asm = asm + emit_label("pdp_table")
    asm = asm + emit_asm(".skip", "4096")
    # PD table (Page Directory) - 4 entries for 4GB with 1GB pages
    asm = asm + emit_label("pd_table")
    asm = asm + emit_asm(".skip", "4096")
    asm = asm + NL
    return asm
end

# --- Generate page table initialization code ---
proc generate_page_table_init():
    let asm = ""
    asm = asm + TAB + "# Clear page tables" + NL
    asm = asm + emit_asm("movl", "$pml4_table, %edi")
    asm = asm + emit_asm("xorl", "%eax, %eax")
    asm = asm + emit_asm("movl", "$3072, %ecx")
    asm = asm + emit_asm("rep stosl", "")
    asm = asm + NL
    asm = asm + TAB + "# PML4[0] -> PDP table" + NL
    asm = asm + emit_asm("movl", "$pdp_table, %eax")
    asm = asm + emit_asm("orl", "$0x03, %eax")
    asm = asm + emit_asm("movl", "%eax, (pml4_table)")
    asm = asm + NL
    asm = asm + TAB + "# PDP entries: 4 x 1GB pages (identity map 0-4GB)" + NL
    asm = asm + emit_asm("movl", "$0x00000083, (pdp_table)")
    asm = asm + emit_asm("movl", "$0x40000083, (pdp_table + 8)")
    asm = asm + emit_asm("movl", "$0x80000083, (pdp_table + 16)")
    asm = asm + emit_asm("movl", "$0xC0000083, (pdp_table + 24)")
    asm = asm + NL
    return asm
end

# --- Generate GDT loading code ---
proc generate_gdt_load():
    let asm = ""
    # GDT data
    asm = asm + emit_section(".rodata")
    asm = asm + ".align 16" + NL
    asm = asm + emit_label("gdt64")
    # Null descriptor
    asm = asm + emit_asm(".quad", "0")
    # Kernel code: 64-bit, present, executable, readable
    asm = asm + emit_label("gdt64_code")
    asm = asm + emit_asm(".quad", "0x00209A0000000000")
    # Kernel data: present, writable
    asm = asm + emit_label("gdt64_data")
    asm = asm + emit_asm(".quad", "0x0000920000000000")
    asm = asm + emit_label("gdt64_end")
    asm = asm + NL
    # GDTR
    asm = asm + emit_label("gdt64_pointer")
    asm = asm + emit_asm(".short", "gdt64_end - gdt64 - 1")
    asm = asm + emit_asm(".long", "gdt64")
    asm = asm + NL
    return asm
end

# --- Generate A20 line enable ---
proc generate_a20_enable():
    let asm = ""
    asm = asm + TAB + "# Enable A20 line via port 0x92 (fast A20)" + NL
    asm = asm + emit_asm("inb", "$0x92, %al")
    asm = asm + emit_asm("orb", "$0x02, %al")
    asm = asm + emit_asm("andb", "$0xFE, %al")
    asm = asm + emit_asm("outb", "%al, $0x92")
    asm = asm + NL
    return asm
end

# --- Generate long mode enable sequence ---
proc generate_long_mode_enable():
    let asm = ""
    asm = asm + TAB + "# Set CR4.PAE (Physical Address Extension)" + NL
    asm = asm + emit_asm("movl", "%cr4, %eax")
    asm = asm + emit_asm("orl", "$0x20, %eax")
    asm = asm + emit_asm("movl", "%eax, %cr4")
    asm = asm + NL
    asm = asm + TAB + "# Load PML4 into CR3" + NL
    asm = asm + emit_asm("movl", "$pml4_table, %eax")
    asm = asm + emit_asm("movl", "%eax, %cr3")
    asm = asm + NL
    asm = asm + TAB + "# Set EFER.LME (Long Mode Enable)" + NL
    asm = asm + emit_asm("movl", "$0xC0000080, %ecx")
    asm = asm + emit_asm("rdmsr", "")
    asm = asm + emit_asm("orl", "$0x100, %eax")
    asm = asm + emit_asm("wrmsr", "")
    asm = asm + NL
    asm = asm + TAB + "# Enable paging (CR0.PG) and protected mode (CR0.PE)" + NL
    asm = asm + emit_asm("movl", "%cr0, %eax")
    asm = asm + emit_asm("orl", "$0x80000001, %eax")
    asm = asm + emit_asm("movl", "%eax, %cr0")
    asm = asm + NL
    return asm
end

# --- Generate 32-bit entry point ---
proc generate_entry32():
    let asm = ""
    asm = asm + emit_section(".text")
    asm = asm + ".code32" + NL
    asm = asm + ".global _start" + NL
    asm = asm + emit_label("_start")
    asm = asm + TAB + "# Save multiboot info pointer" + NL
    asm = asm + emit_asm("movl", "%ebx, %edi")
    asm = asm + NL
    asm = asm + TAB + "# Set up initial stack" + NL
    asm = asm + emit_asm("movl", "$stack_top, %esp")
    asm = asm + NL
    asm = asm + TAB + "# Clear BSS" + NL
    asm = asm + emit_asm("movl", "$__bss_start, %edi")
    asm = asm + emit_asm("movl", "$__bss_end, %ecx")
    asm = asm + emit_asm("subl", "%edi, %ecx")
    asm = asm + emit_asm("shrl", "$2, %ecx")
    asm = asm + emit_asm("xorl", "%eax, %eax")
    asm = asm + emit_asm("rep stosl", "")
    asm = asm + NL
    # Restore multiboot pointer
    asm = asm + emit_asm("movl", "%ebx, %edi")
    asm = asm + NL
    return asm
end

# --- Generate 64-bit trampoline ---
proc generate_entry64():
    let asm = ""
    asm = asm + TAB + "# Load 64-bit GDT" + NL
    asm = asm + emit_asm("lgdt", "(gdt64_pointer)")
    asm = asm + NL
    asm = asm + TAB + "# Far jump to 64-bit code segment" + NL
    asm = asm + emit_asm("ljmp", "$0x08, $long_mode_start")
    asm = asm + NL
    asm = asm + ".code64" + NL
    asm = asm + emit_label("long_mode_start")
    asm = asm + TAB + "# Reload data segment registers" + NL
    asm = asm + emit_asm("movw", "$0x10, %ax")
    asm = asm + emit_asm("movw", "%ax, %ds")
    asm = asm + emit_asm("movw", "%ax, %es")
    asm = asm + emit_asm("movw", "%ax, %fs")
    asm = asm + emit_asm("movw", "%ax, %gs")
    asm = asm + emit_asm("movw", "%ax, %ss")
    asm = asm + NL
    asm = asm + TAB + "# Set up 64-bit stack" + NL
    asm = asm + emit_asm("movq", "$stack_top, %rsp")
    asm = asm + NL
    asm = asm + TAB + "# Pass multiboot info pointer as first argument" + NL
    asm = asm + emit_asm("movl", "%edi, %edi")
    asm = asm + NL
    asm = asm + TAB + "# Call kernel main" + NL
    asm = asm + emit_asm("call", "kmain")
    asm = asm + NL
    asm = asm + TAB + "# Halt if kmain returns" + NL
    asm = asm + emit_label("halt")
    asm = asm + emit_asm("cli", "")
    asm = asm + emit_asm("hlt", "")
    asm = asm + emit_asm("jmp", "halt")
    asm = asm + NL
    return asm
end

# --- Generate stack reservation ---
proc generate_stack():
    let asm = ""
    asm = asm + emit_section(".bss")
    asm = asm + ".align 16" + NL
    asm = asm + emit_label("stack_bottom")
    asm = asm + emit_asm(".skip", str(KERNEL_STACK_SIZE))
    asm = asm + emit_label("stack_top")
    asm = asm + NL
    return asm
end

# --- Generate complete boot assembly ---
proc generate_boot_asm(config):
    let asm = ""
    asm = asm + "# x86_64 boot stub - generated by Sage" + NL
    asm = asm + "# Multiboot2 compliant, transitions 32-bit -> 64-bit long mode" + NL
    asm = asm + NL
    # Multiboot2 header
    asm = asm + generate_multiboot_header()
    # GDT (in rodata)
    asm = asm + generate_gdt_load()
    # 32-bit entry
    asm = asm + generate_entry32()
    # A20
    asm = asm + generate_a20_enable()
    # Page tables init
    asm = asm + generate_page_table_init()
    # Long mode
    asm = asm + generate_long_mode_enable()
    # 64-bit entry
    asm = asm + generate_entry64()
    # BSS: page tables + stack
    asm = asm + generate_page_tables()
    asm = asm + generate_stack()
    return asm
end
