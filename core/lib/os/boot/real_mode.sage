## os.boot.real_mode — x86 Real Mode Utilities
## Provides helpers for memory addressing and stack setup in 16-bit real mode.

let NL = chr(10)
let TAB = chr(9)

## Convert segment and offset to linear address
proc seg_off_to_linear(seg, off):
    return (seg * 16) + off
end

## Convert linear address to segment and offset
proc linear_to_seg_off(linear):
    let seg = (linear >> 4) & 0xF000
    let off = linear & 0xFFFF
    return [seg, off]
end

## Generate real mode stack setup assembly
proc emit_stack_setup(ss, sp):
    let asm = ""
    asm = asm + TAB + "# Setup Real Mode Stack" + NL
    asm = asm + TAB + "movw $" + str(ss) + ", %ax" + NL
    asm = asm + TAB + "movw %ax, %ss" + NL
    asm = asm + TAB + "movw $" + str(sp) + ", %sp" + NL
    return asm
end

## Generate far jump assembly to reset CS
proc emit_far_jmp(seg, off):
    let asm = ""
    asm = asm + TAB + "# Far jump to reset CS" + NL
    asm = asm + TAB + "ljmp $" + str(seg) + ", $" + str(off) + NL
    return asm
end
