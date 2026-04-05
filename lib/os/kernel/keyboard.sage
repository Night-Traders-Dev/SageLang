gc_disable()

# keyboard.sage — PS/2 keyboard driver
# Handles scancodes from port 0x60, US QWERTY layout.

import console

# ----- Special key constants -----
let KEY_ESC = 1
let KEY_ENTER = 28
let KEY_BACKSPACE = 14
let KEY_TAB = 15
let KEY_F1 = 59
let KEY_F2 = 60
let KEY_F3 = 61
let KEY_F4 = 62
let KEY_F5 = 63
let KEY_F6 = 64
let KEY_F7 = 65
let KEY_F8 = 66
let KEY_F9 = 67
let KEY_F10 = 68
let KEY_F11 = 87
let KEY_F12 = 88
let KEY_UP = 72
let KEY_DOWN = 80
let KEY_LEFT = 75
let KEY_RIGHT = 77

let KEY_LSHIFT = 42
let KEY_RSHIFT = 54
let KEY_LCTRL = 29
let KEY_LALT = 56

# ----- Driver state -----
let shift_pressed = false
let ctrl_pressed = false
let alt_pressed = false
let kbd_ready = false

# Scancode buffer (simulated ring buffer)
let scan_buffer = []
let scan_head = 0
let scan_tail = 0
let BUFFER_SIZE = 256

# ----- US QWERTY scancode-to-ASCII tables -----
let scan_normal = []
let scan_shifted = []

proc build_scancode_tables():
    # Initialize with empty strings up to index 128
    let i = 0
    while i < 128:
        append(scan_normal, "")
        append(scan_shifted, "")
        i = i + 1
    end
    # Row 1: number row
    scan_normal[2] = "1"
    scan_normal[3] = "2"
    scan_normal[4] = "3"
    scan_normal[5] = "4"
    scan_normal[6] = "5"
    scan_normal[7] = "6"
    scan_normal[8] = "7"
    scan_normal[9] = "8"
    scan_normal[10] = "9"
    scan_normal[11] = "0"
    scan_normal[12] = "-"
    scan_normal[13] = "="
    scan_normal[15] = chr(9)
    scan_normal[16] = "q"
    scan_normal[17] = "w"
    scan_normal[18] = "e"
    scan_normal[19] = "r"
    scan_normal[20] = "t"
    scan_normal[21] = "y"
    scan_normal[22] = "u"
    scan_normal[23] = "i"
    scan_normal[24] = "o"
    scan_normal[25] = "p"
    scan_normal[26] = "["
    scan_normal[27] = "]"
    scan_normal[28] = chr(10)
    scan_normal[30] = "a"
    scan_normal[31] = "s"
    scan_normal[32] = "d"
    scan_normal[33] = "f"
    scan_normal[34] = "g"
    scan_normal[35] = "h"
    scan_normal[36] = "j"
    scan_normal[37] = "k"
    scan_normal[38] = "l"
    scan_normal[39] = ";"
    scan_normal[40] = "'"
    scan_normal[41] = "`"
    scan_normal[43] = "\\"
    scan_normal[44] = "z"
    scan_normal[45] = "x"
    scan_normal[46] = "c"
    scan_normal[47] = "v"
    scan_normal[48] = "b"
    scan_normal[49] = "n"
    scan_normal[50] = "m"
    scan_normal[51] = ","
    scan_normal[52] = "."
    scan_normal[53] = "/"
    scan_normal[57] = " "

    # Shifted variants
    scan_shifted[2] = "!"
    scan_shifted[3] = "@"
    scan_shifted[4] = "#"
    scan_shifted[5] = "$"
    scan_shifted[6] = "%"
    scan_shifted[7] = "^"
    scan_shifted[8] = "&"
    scan_shifted[9] = "*"
    scan_shifted[10] = "("
    scan_shifted[11] = ")"
    scan_shifted[12] = "_"
    scan_shifted[13] = "+"
    scan_shifted[15] = chr(9)
    scan_shifted[16] = "Q"
    scan_shifted[17] = "W"
    scan_shifted[18] = "E"
    scan_shifted[19] = "R"
    scan_shifted[20] = "T"
    scan_shifted[21] = "Y"
    scan_shifted[22] = "U"
    scan_shifted[23] = "I"
    scan_shifted[24] = "O"
    scan_shifted[25] = "P"
    scan_shifted[26] = "{"
    scan_shifted[27] = "}"
    scan_shifted[28] = chr(10)
    scan_shifted[30] = "A"
    scan_shifted[31] = "S"
    scan_shifted[32] = "D"
    scan_shifted[33] = "F"
    scan_shifted[34] = "G"
    scan_shifted[35] = "H"
    scan_shifted[36] = "J"
    scan_shifted[37] = "K"
    scan_shifted[38] = "L"
    scan_shifted[39] = ":"
    scan_shifted[40] = chr(34)
    scan_shifted[41] = "~"
    scan_shifted[43] = "|"
    scan_shifted[44] = "Z"
    scan_shifted[45] = "X"
    scan_shifted[46] = "C"
    scan_shifted[47] = "V"
    scan_shifted[48] = "B"
    scan_shifted[49] = "N"
    scan_shifted[50] = "M"
    scan_shifted[51] = "<"
    scan_shifted[52] = ">"
    scan_shifted[53] = "?"
    scan_shifted[57] = " "
end

proc init():
    build_scancode_tables()
    shift_pressed = false
    ctrl_pressed = false
    alt_pressed = false
    scan_buffer = []
    let i = 0
    while i < BUFFER_SIZE:
        append(scan_buffer, 0)
        i = i + 1
    end
    scan_head = 0
    scan_tail = 0
    kbd_ready = true
end

proc read_scancode():
    # In a real kernel this reads port 0x60 via inb().
    # Here we return from the simulated buffer.
    if scan_head == scan_tail:
        return nil
    end
    let code = scan_buffer[scan_head]
    scan_head = (scan_head + 1) % BUFFER_SIZE
    return code
end

proc push_scancode(code):
    let next_tail = (scan_tail + 1) % BUFFER_SIZE
    if next_tail == scan_head:
        return
    end
    scan_buffer[scan_tail] = code
    scan_tail = next_tail
end

proc scancode_to_ascii(code, shift):
    if code < 0:
        return ""
    end
    if code >= 128:
        return ""
    end
    if shift:
        return scan_shifted[code]
    end
    return scan_normal[code]
end

proc update_modifiers(code, pressed):
    if code == KEY_LSHIFT:
        shift_pressed = pressed
        return
    end
    if code == KEY_RSHIFT:
        shift_pressed = pressed
        return
    end
    if code == KEY_LCTRL:
        ctrl_pressed = pressed
        return
    end
    if code == KEY_LALT:
        alt_pressed = pressed
    end
end

proc is_shift_pressed():
    return shift_pressed
end

proc is_ctrl_pressed():
    return ctrl_pressed
end

proc is_alt_pressed():
    return alt_pressed
end

proc poll_key():
    let code = read_scancode()
    if code == nil:
        return nil
    end
    # Key release (bit 7 set) — scancode >= 128
    if code >= 128:
        let release_code = code - 128
        update_modifiers(release_code, false)
        return nil
    end
    # Key press
    update_modifiers(code, true)
    let ch = scancode_to_ascii(code, shift_pressed)
    if ch == "":
        let result = {}
        result["scancode"] = code
        result["char"] = nil
        return result
    end
    let result = {}
    result["scancode"] = code
    result["char"] = ch
    return result
end

proc wait_key():
    let key = nil
    while key == nil:
        key = poll_key()
    end
    return key
end

proc read_line():
    let line = ""
    let done = false
    while done == false:
        let key = wait_key()
        if key["char"] == nil:
            continue
        end
        let ch = key["char"]
        if ch == chr(10):
            console.print_line("")
            done = true
            continue
        end
        if key["scancode"] == KEY_BACKSPACE:
            if len(line) > 0:
                line = line[0:len(line) - 1]
                let pos = console.get_cursor()
                let nx = pos["x"] - 1
                if nx < 0:
                    nx = 0
                end
                console.set_cursor(nx, pos["y"])
                console.putchar(" ", 7)
                console.set_cursor(nx, pos["y"])
            end
            continue
        end
        line = line + ch
        console.print_str(ch)
    end
    return line
end

# ================================================================
# Hardware I/O Assembly Emission
# ================================================================

comptime:
    let PS2_DATA_PORT = 96
    let PS2_STATUS_PORT = 100
    let PIC_CMD_PORT = 32
    let PIC_DATA_PORT = 33
    let EOI_BYTE = 32
    let KBD_ENABLE_CMD = 174
end

proc emit_keyboard_isr_asm():
    # x86_64 assembly for IRQ1 (keyboard) interrupt handler
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global keyboard_isr" + nl
    asm = asm + ".type keyboard_isr, @function" + nl
    asm = asm + "keyboard_isr:" + nl
    # Save registers
    asm = asm + tab + "push %rax" + nl
    asm = asm + tab + "push %rcx" + nl
    asm = asm + tab + "push %rdx" + nl
    # Read scancode from PS/2 data port 0x60
    asm = asm + tab + "inb $0x60, %al" + nl
    # Store scancode to global buffer
    asm = asm + tab + "movzbq %al, %rax" + nl
    asm = asm + tab + "movq %rax, scancode_buffer(%rip)" + nl
    # Send EOI to PIC
    asm = asm + tab + "movb $0x20, %al" + nl
    asm = asm + tab + "outb %al, $0x20" + nl
    # Restore registers
    asm = asm + tab + "pop %rdx" + nl
    asm = asm + tab + "pop %rcx" + nl
    asm = asm + tab + "pop %rax" + nl
    asm = asm + tab + "iretq" + nl
    asm = asm + nl
    # Global scancode buffer variable
    asm = asm + ".section .bss" + nl
    asm = asm + ".global scancode_buffer" + nl
    asm = asm + "scancode_buffer:" + nl
    asm = asm + tab + ".quad 0" + nl
    return asm
end

proc emit_keyboard_init_asm():
    # x86_64 assembly to initialize PS/2 keyboard controller
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global keyboard_init" + nl
    asm = asm + ".type keyboard_init, @function" + nl
    asm = asm + "keyboard_init:" + nl
    # Wait for controller ready (poll port 0x64 bit 1 clear)
    asm = asm + ".Lkbd_wait_input:" + nl
    asm = asm + tab + "inb $0x64, %al" + nl
    asm = asm + tab + "testb $0x02, %al" + nl
    asm = asm + tab + "jnz .Lkbd_wait_input" + nl
    # Send 0xAE to port 0x64 (enable keyboard interface)
    asm = asm + tab + "movb $0xAE, %al" + nl
    asm = asm + tab + "outb %al, $0x64" + nl
    # Wait for data ready (poll port 0x64 bit 0 set)
    asm = asm + ".Lkbd_wait_data:" + nl
    asm = asm + tab + "inb $0x64, %al" + nl
    asm = asm + tab + "testb $0x01, %al" + nl
    asm = asm + tab + "jz .Lkbd_wait_data" + nl
    # Read and discard ACK from port 0x60
    asm = asm + tab + "inb $0x60, %al" + nl
    # Enable IRQ1 in PIC: read mask, clear bit 1, write back
    asm = asm + tab + "inb $0x21, %al" + nl
    asm = asm + tab + "andb $0xFD, %al" + nl
    asm = asm + tab + "outb %al, $0x21" + nl
    asm = asm + tab + "ret" + nl
    return asm
end

@inline
proc emit_keyboard_read_asm():
    # x86_64 assembly for blocking keyboard_read function
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global keyboard_read" + nl
    asm = asm + ".type keyboard_read, @function" + nl
    asm = asm + "keyboard_read:" + nl
    # Poll scancode_buffer until non-zero
    asm = asm + ".Lkbd_poll:" + nl
    asm = asm + tab + "movq scancode_buffer(%rip), %rax" + nl
    asm = asm + tab + "testq %rax, %rax" + nl
    asm = asm + tab + "jz .Lkbd_poll" + nl
    # Clear buffer
    asm = asm + tab + "movq $0, scancode_buffer(%rip)" + nl
    # Value already in rax (return register)
    asm = asm + tab + "ret" + nl
    return asm
end
