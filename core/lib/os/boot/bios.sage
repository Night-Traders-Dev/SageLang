## os.boot.bios — BIOS / Firmware Interface for x86 Legacy Boot
## Provides code generation for BIOS interrupts from real mode.

let NL = chr(10)
let TAB = chr(9)

## Set video mode via INT 0x10
proc set_video_mode(mode):
    let asm = ""
    asm = asm + TAB + "# BIOS set video mode " + str(mode) + NL
    asm = asm + TAB + "movb $" + str(mode) + ", %al" + NL
    asm = asm + TAB + "movb $0x00, %ah" + NL
    asm = asm + TAB + "int $0x10" + NL
    return asm

## Print a character via INT 0x10
proc putchar(c, attr):
    let asm = ""
    asm = asm + TAB + "# BIOS putchar '" + str(c) + "'" + NL
    asm = asm + TAB + "movb $" + str(ord(c)) + ", %al" + NL
    asm = asm + TAB + "movb $0x0E, %ah" + NL # Teletype output
    asm = asm + TAB + "movb $0x00, %bh" + NL # Page number
    asm = asm + TAB + "movb $" + str(attr) + ", %bl" + NL # Attribute
    asm = asm + TAB + "int $0x10" + NL
    return asm

## Set cursor position via INT 0x10
proc set_cursor(row, col):
    let asm = ""
    asm = asm + TAB + "# BIOS set cursor to " + str(row) + "," + str(col) + NL
    asm = asm + TAB + "movb $0x02, %ah" + NL
    asm = asm + TAB + "movb $0x00, %bh" + NL # Page 0
    asm = asm + TAB + "movb $" + str(row) + ", %dh" + NL
    asm = asm + TAB + "movb $" + str(col) + ", %dl" + NL
    asm = asm + TAB + "int $0x10" + NL
    return asm

## Disk Address Packet for INT 0x13 AH=0x42
proc disk_address_packet(lba, count, dest):
    # This returns a struct-like dict that can be serialized
    return {
        "size": 16,
        "reserved": 0,
        "count": count,
        "offset": dest & 0xFFFF,
        "segment": (dest >> 4) & 0xF000, # Assuming linear to seg:off simplified
        "lba": lba
    }

## Read disk sectors via INT 0x13 Extension (AH=0x42)
proc int13_read(drive, dap_label):
    let asm = ""
    asm = asm + TAB + "# BIOS Extended Read from drive " + str(drive) + NL
    asm = asm + TAB + "movb $" + str(drive) + ", %dl" + NL
    asm = asm + TAB + "movw $" + dap_label + ", %si" + NL
    asm = asm + TAB + "movb $0x42, %ah" + NL
    asm = asm + TAB + "int $0x13" + NL
    return asm

## Memory map (E820) iteration
proc e820_next(continuation_label):
    let asm = ""
    asm = asm + TAB + "# BIOS E820 Memory Map entry" + NL
    asm = asm + TAB + "movl $0xE820, %eax" + NL
    asm = asm + TAB + "movl $0x534D4150, %edx" + NL # 'SMAP'
    asm = asm + TAB + "movl $24, %ecx" + NL
    asm = asm + TAB + "int $0x15" + NL
    return asm

## Get key via INT 0x16
proc getkey():
    let asm = ""
    asm = asm + TAB + "# BIOS get key" + NL
    asm = asm + TAB + "movb $0x00, %ah" + NL
    asm = asm + TAB + "int $0x16" + NL
    return asm

## Raw interrupt dispatch code generation
proc interrupt(int_num, ax, bx, cx, dx, es_di):
    let asm = ""
    asm = asm + TAB + "# BIOS Raw INT " + str(int_num) + NL
    if ax != nil: asm = asm + TAB + "movw $" + str(ax) + ", %ax" + NL
    if bx != nil: asm = asm + TAB + "movw $" + str(bx) + ", %bx" + NL
    if cx != nil: asm = asm + TAB + "movw $" + str(cx) + ", %cx" + NL
    if dx != nil: asm = asm + TAB + "movw $" + str(dx) + ", %dx" + NL
    if es_di != nil:
        # Simplified: assume dest is a label
        asm = asm + TAB + "movw $" + es_di + ", %di" + NL
    end
    asm = asm + TAB + "int $" + str(int_num) + NL
    return asm
