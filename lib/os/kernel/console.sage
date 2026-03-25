gc_disable()

# console.sage — VGA text mode and framebuffer console driver
# VGA text buffer at 0xB8000, 80x25 characters, 16 colors.

# ----- Color constants -----
let BLACK = 0
let BLUE = 1
let GREEN = 2
let CYAN = 3
let RED = 4
let MAGENTA = 5
let BROWN = 6
let LIGHT_GRAY = 7
let DARK_GRAY = 8
let LIGHT_BLUE = 9
let LIGHT_GREEN = 10
let LIGHT_CYAN = 11
let LIGHT_RED = 12
let LIGHT_MAGENTA = 13
let YELLOW = 14
let WHITE = 15

# ----- VGA state -----
let VGA_BASE = 753664
let VGA_WIDTH = 80
let VGA_HEIGHT = 25

let cursor_x = 0
let cursor_y = 0
let current_fg = LIGHT_GRAY
let current_bg = BLACK

# VGA text buffer (simulated as array of {char, color} entries)
let vga_buffer = []
let vga_ready = false

# ----- Framebuffer state -----
let fb_addr = 0
let fb_width = 0
let fb_height = 0
let fb_pitch = 0
let fb_bpp = 0
let fb_buffer = []
let fb_ready = false

# ----- Helper: make VGA color attribute byte -----
proc make_color(fg, bg):
    return (bg * 16) + fg
end

# ----- Helper: buffer index from x, y -----
proc vga_index(x, y):
    return y * VGA_WIDTH + x
end

# ----- Initialize VGA text mode -----
proc init_vga():
    cursor_x = 0
    cursor_y = 0
    current_fg = LIGHT_GRAY
    current_bg = BLACK
    vga_buffer = []
    let total = VGA_WIDTH * VGA_HEIGHT
    let i = 0
    while i < total:
        let cell = {}
        cell["char"] = " "
        cell["color"] = make_color(current_fg, current_bg)
        append(vga_buffer, cell)
        i = i + 1
    end
    vga_ready = true
end

# ----- Set foreground and background color -----
proc set_color(fg, bg):
    current_fg = fg
    current_bg = bg
end

# ----- Get cursor position -----
proc get_cursor():
    let pos = {}
    pos["x"] = cursor_x
    pos["y"] = cursor_y
    return pos
end

# ----- Set cursor position -----
proc set_cursor(x, y):
    if x < 0:
        x = 0
    end
    if x >= VGA_WIDTH:
        x = VGA_WIDTH - 1
    end
    if y < 0:
        y = 0
    end
    if y >= VGA_HEIGHT:
        y = VGA_HEIGHT - 1
    end
    cursor_x = x
    cursor_y = y
end

# ----- Scroll the screen up by one line -----
proc scroll_up():
    # Move every row up by one
    let y = 1
    while y < VGA_HEIGHT:
        let x = 0
        while x < VGA_WIDTH:
            let src = vga_index(x, y)
            let dst = vga_index(x, y - 1)
            vga_buffer[dst]["char"] = vga_buffer[src]["char"]
            vga_buffer[dst]["color"] = vga_buffer[src]["color"]
            x = x + 1
        end
        y = y + 1
    end
    # Clear the last row
    let x2 = 0
    while x2 < VGA_WIDTH:
        let idx = vga_index(x2, VGA_HEIGHT - 1)
        vga_buffer[idx]["char"] = " "
        vga_buffer[idx]["color"] = make_color(current_fg, current_bg)
        x2 = x2 + 1
    end
end

# ----- Advance cursor, scrolling if needed -----
proc advance_cursor():
    cursor_x = cursor_x + 1
    if cursor_x >= VGA_WIDTH:
        cursor_x = 0
        cursor_y = cursor_y + 1
    end
    if cursor_y >= VGA_HEIGHT:
        scroll_up()
        cursor_y = VGA_HEIGHT - 1
    end
end

# ----- Handle newline -----
proc newline():
    cursor_x = 0
    cursor_y = cursor_y + 1
    if cursor_y >= VGA_HEIGHT:
        scroll_up()
        cursor_y = VGA_HEIGHT - 1
    end
end

# ----- Put a single character at cursor position -----
proc putchar(ch, color):
    if ch == chr(10):
        newline()
        return
    end
    if ch == chr(9):
        # Tab: advance to next 8-column boundary
        let spaces = 8 - (cursor_x % 8)
        let s = 0
        while s < spaces:
            putchar(" ", color)
            s = s + 1
        end
        return
    end
    let idx = vga_index(cursor_x, cursor_y)
    vga_buffer[idx]["char"] = ch
    vga_buffer[idx]["color"] = color
    advance_cursor()
end

# ----- Print a string at current cursor with current colors -----
proc print_str(text):
    let color = make_color(current_fg, current_bg)
    let i = 0
    let tlen = len(text)
    while i < tlen:
        let ch = text[i]
        putchar(ch, color)
        i = i + 1
    end
end

# ----- Print a string followed by newline -----
proc print_line(text):
    print_str(text)
    newline()
end

# ----- Clear the entire screen with a background color -----
proc clear_screen(color):
    let attr = make_color(current_fg, color)
    let total = VGA_WIDTH * VGA_HEIGHT
    let i = 0
    while i < total:
        vga_buffer[i]["char"] = " "
        vga_buffer[i]["color"] = attr
        i = i + 1
    end
    cursor_x = 0
    cursor_y = 0
end

# ----- Framebuffer initialization -----
proc init_framebuffer(addr, width, height, pitch, bpp):
    fb_addr = addr
    fb_width = width
    fb_height = height
    fb_pitch = pitch
    fb_bpp = bpp
    fb_buffer = []
    let total_pixels = width * height
    let i = 0
    while i < total_pixels:
        append(fb_buffer, 0)
        i = i + 1
    end
    fb_ready = true
end

# ----- Put a pixel in the framebuffer -----
proc fb_putpixel(x, y, color):
    if fb_ready == false:
        return
    end
    if x < 0:
        return
    end
    if y < 0:
        return
    end
    if x >= fb_width:
        return
    end
    if y >= fb_height:
        return
    end
    let idx = y * fb_width + x
    fb_buffer[idx] = color
end

# ----- Fill a rectangle in the framebuffer -----
proc fb_fill_rect(x, y, w, h, color):
    if fb_ready == false:
        return
    end
    let row = y
    while row < y + h:
        if row >= 0:
            if row < fb_height:
                let col = x
                while col < x + w:
                    if col >= 0:
                        if col < fb_width:
                            let idx = row * fb_width + col
                            fb_buffer[idx] = color
                        end
                    end
                    col = col + 1
                end
            end
        end
        row = row + 1
    end
end
