## os.boot.a20 — A20 Gate Enabling
## Provides methods to enable the A20 gate for access to memory above 1MB.

let NL = chr(10)
let TAB = chr(9)

## Check if A20 gate is enabled
proc is_enabled():
    let asm = ""
    asm = asm + TAB + "# Check A20 status" + NL
    asm = asm + TAB + "pushw %ds" + NL
    asm = asm + TAB + "pushw %es" + NL
    asm = asm + TAB + "xorw %ax, %ax" + NL
    asm = asm + TAB + "movw %ax, %ds" + NL
    asm = asm + TAB + "decw %ax" + NL
    asm = asm + TAB + "movw %ax, %es" + NL
    asm = asm + TAB + "movw $0x7C00, %si" + NL
    asm = asm + TAB + "movw $0x7C10, %di" + NL
    asm = asm + TAB + "movw (%si), %ax" + NL
    asm = asm + TAB + "pushw %ax" + NL
    asm = asm + TAB + "notw %ax" + NL
    asm = asm + TAB + "movw %ax, %ds:(%si)" + NL
    asm = asm + TAB + "cmpl %ax, %es:(%di)" + NL
    asm = asm + TAB + "popw %ax" + NL
    asm = asm + TAB + "movw %ax, (%si)" + NL
    asm = asm + TAB + "popw %es" + NL
    asm = asm + TAB + "popw %ds" + NL
    return asm
end

## Enable A20 via BIOS (INT 0x15 AX=0x2401)
proc enable_bios():
    let asm = ""
    asm = asm + TAB + "# Enable A20 via BIOS" + NL
    asm = asm + TAB + "movw $0x2401, %ax" + NL
    asm = asm + TAB + "int $0x15" + NL
    return asm
end

## Enable A20 via "Fast A20" (Port 0x92)
proc enable_fast():
    let asm = ""
    asm = asm + TAB + "# Enable A20 via Port 0x92" + NL
    asm = asm + TAB + "inb $0x92, %al" + NL
    asm = asm + TAB + "orb $0x02, %al" + NL
    asm = asm + TAB + "outb %al, $0x92" + NL
    return asm
end

## Enable A20 via Keyboard Controller (legacy)
proc enable_kbd():
    let asm = ""
    asm = asm + TAB + "# Enable A20 via KBD Controller" + NL
    # ... assembly for KBD controller sequence ...
    return asm
end

## Wait for A20 to be enabled with a timeout
proc wait_enabled(timeout):
    let asm = ""
    asm = asm + TAB + "# Wait for A20 enabled (timeout " + str(timeout) + ")" + NL
    # ... loop checking status ...
    return asm
end
