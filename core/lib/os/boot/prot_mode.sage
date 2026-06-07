## os.boot.prot_mode — x86 Protected Mode Transition
## Handles the transition from 16-bit real mode to 32-bit protected mode.

let NL = chr(10)
let TAB = chr(9)

## Generate transition assembly to enter protected mode
proc emit_enter_prot_mode(gdt_label, cs_sel, ds_sel, target):
    let asm = ""
    asm = asm + TAB + "# Enter Protected Mode" + NL
    asm = asm + TAB + "cli" + NL
    asm = asm + TAB + "lgdt (" + gdt_label + ")" + NL
    asm = asm + TAB + "movl %cr0, %eax" + NL
    asm = asm + TAB + "orl $0x01, %eax" + NL # PE bit
    asm = asm + TAB + "movl %eax, %cr0" + NL
    asm = asm + TAB + "ljmp $" + str(cs_sel) + ", $" + target + NL
    return asm
end

## Generate a minimal flat 32-bit GDT
proc emit_flat_gdt():
    let asm = ""
    asm = asm + emit_label("gdt_pm")
    # Null
    asm = asm + TAB + ".quad 0" + NL
    # 32-bit code: base=0, limit=0xFFFFF, type=0x9A, flags=0xC (4KB granularity, 32-bit)
    asm = asm + TAB + ".quad 0x00CF9A000000FFFF" + NL
    # 32-bit data: base=0, limit=0xFFFFF, type=0x92, flags=0xC
    asm = asm + TAB + ".quad 0x00CF92000000FFFF" + NL
    asm = asm + emit_label("gdt_pm_end")
    asm = asm + emit_label("gdt_pm_desc")
    asm = asm + TAB + ".short gdt_pm_end - gdt_pm - 1" + NL
    asm = asm + TAB + ".long gdt_pm" + NL
    return asm
end

proc emit_label(name):
    return name + ":" + chr(10)
end
