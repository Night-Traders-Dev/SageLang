## os.boot.long_mode — x86 Long Mode Transition
## Handles the transition from 32-bit protected mode to 64-bit long mode.

let NL = chr(10)
let TAB = chr(9)

## Generate transition assembly to enter long mode
proc emit_enter_long_mode(pml4_addr, gdt64_label, cs_sel, target):
    let asm = ""
    asm = asm + TAB + "# Enter Long Mode" + NL
    # 1. Enable PAE
    asm = asm + TAB + "movl %cr4, %eax" + NL
    asm = asm + TAB + "orl $0x20, %eax" + NL
    asm = asm + TAB + "movl %eax, %cr4" + NL
    # 2. Load PML4
    asm = asm + TAB + "movl $" + str(pml4_addr) + ", %eax" + NL
    asm = asm + TAB + "movl %eax, %cr3" + NL
    # 3. Enable Long Mode in EFER MSR
    asm = asm + TAB + "movl $0xC0000080, %ecx" + NL
    asm = asm + TAB + "rdmsr" + NL
    asm = asm + TAB + "orl $0x100, %eax" + NL
    asm = asm + TAB + "wrmsr" + NL
    # 4. Enable Paging
    asm = asm + TAB + "movl %cr0, %eax" + NL
    asm = asm + TAB + "orl $0x80000001, %eax" + NL
    asm = asm + TAB + "movl %eax, %cr0" + NL
    # 5. Load 64-bit GDT
    asm = asm + TAB + "lgdt (" + gdt64_label + ")" + NL
    # 6. Far jump to 64-bit target
    asm = asm + TAB + "ljmp $" + str(cs_sel) + ", $" + target + NL
    return asm
end
