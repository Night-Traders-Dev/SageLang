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

# ================================================================
# Architecture-neutral framebuffer text console
# ================================================================
# Works on ALL architectures (x86_64, aarch64, riscv64) since it
# operates on a generic memory-mapped framebuffer. Uses a simple
# built-in 8x8 bitmap font.

# Simple 8x8 bitmap font for printable ASCII (32-126)
# Each character is 8 bytes, one byte per row, MSB = leftmost pixel.
proc _font_get_glyph(ch):
    let code = ord(ch)
    if code < 32 or code > 126:
        code = 32
    end
    # Minimal built-in bitmaps for printable ASCII
    # We define a small subset inline; everything else gets a filled block
    let glyph = [0, 0, 0, 0, 0, 0, 0, 0]
    if code == 32:
        # space
        return glyph
    end
    if code == 33:
        # !
        glyph = [24, 24, 24, 24, 24, 0, 24, 0]
        return glyph
    end
    if code == 48:
        # 0
        glyph = [60, 102, 110, 126, 118, 102, 60, 0]
        return glyph
    end
    if code == 49:
        # 1
        glyph = [24, 56, 24, 24, 24, 24, 126, 0]
        return glyph
    end
    if code == 50:
        # 2
        glyph = [60, 102, 6, 12, 24, 48, 126, 0]
        return glyph
    end
    if code == 51:
        # 3
        glyph = [60, 102, 6, 28, 6, 102, 60, 0]
        return glyph
    end
    if code == 52:
        # 4
        glyph = [12, 28, 44, 76, 126, 12, 12, 0]
        return glyph
    end
    if code == 53:
        # 5
        glyph = [126, 96, 124, 6, 6, 102, 60, 0]
        return glyph
    end
    if code == 54:
        # 6
        glyph = [60, 102, 96, 124, 102, 102, 60, 0]
        return glyph
    end
    if code == 55:
        # 7
        glyph = [126, 6, 12, 24, 48, 48, 48, 0]
        return glyph
    end
    if code == 56:
        # 8
        glyph = [60, 102, 102, 60, 102, 102, 60, 0]
        return glyph
    end
    if code == 57:
        # 9
        glyph = [60, 102, 102, 62, 6, 102, 60, 0]
        return glyph
    end
    if code >= 65 and code <= 90:
        # Uppercase A-Z: simple block representation
        glyph = [126, 102, 102, 126, 102, 102, 102, 0]
        return glyph
    end
    if code >= 97 and code <= 122:
        # Lowercase a-z: smaller block
        glyph = [0, 0, 60, 6, 62, 102, 62, 0]
        return glyph
    end
    if code == 46:
        # .
        glyph = [0, 0, 0, 0, 0, 24, 24, 0]
        return glyph
    end
    if code == 44:
        # ,
        glyph = [0, 0, 0, 0, 0, 24, 24, 48]
        return glyph
    end
    if code == 58:
        # :
        glyph = [0, 24, 24, 0, 24, 24, 0, 0]
        return glyph
    end
    if code == 45:
        # -
        glyph = [0, 0, 0, 126, 0, 0, 0, 0]
        return glyph
    end
    if code == 95:
        # _
        glyph = [0, 0, 0, 0, 0, 0, 0, 255]
        return glyph
    end
    if code == 61:
        # =
        glyph = [0, 0, 126, 0, 126, 0, 0, 0]
        return glyph
    end
    if code == 47:
        # /
        glyph = [2, 4, 8, 16, 32, 64, 128, 0]
        return glyph
    end
    if code == 42:
        # *
        glyph = [0, 102, 60, 255, 60, 102, 0, 0]
        return glyph
    end
    if code == 40:
        # (
        glyph = [12, 24, 48, 48, 48, 24, 12, 0]
        return glyph
    end
    if code == 41:
        # )
        glyph = [48, 24, 12, 12, 12, 24, 48, 0]
        return glyph
    end
    # Default: filled block for unrecognized characters
    glyph = [255, 129, 129, 129, 129, 129, 255, 0]
    return glyph
end

# Initialize a framebuffer text console (architecture-neutral)
# Returns a console state dict used by fb_putchar / fb_puts
proc framebuffer_console_init(fb_address, width, height, pitch):
    let con = {}
    con["fb_addr"] = fb_address
    con["width"] = width
    con["height"] = height
    con["pitch"] = pitch
    con["char_w"] = 8
    con["char_h"] = 8
    con["cols"] = width / 8
    con["rows"] = height / 8
    con["cx"] = 0
    con["cy"] = 0
    con["fg_color"] = 16777215
    con["bg_color"] = 0
    # Pixel buffer (simulated as flat array for codegen)
    let total_pixels = width * height
    let pixels = []
    let i = 0
    while i < total_pixels:
        push(pixels, 0)
        i = i + 1
    end
    con["pixels"] = pixels
    return con
end

# Set the text colors for the framebuffer console
proc fb_console_set_color(con, fg, bg):
    con["fg_color"] = fg
    con["bg_color"] = bg
end

# Scroll the framebuffer console up by one text row (8 pixels)
proc _fb_scroll_up(con):
    let w = con["width"]
    let h = con["height"]
    let pixels = con["pixels"]
    let char_h = con["char_h"]
    # Move all rows up by char_h pixels
    let y = char_h
    while y < h:
        let x = 0
        while x < w:
            let src_idx = y * w + x
            let dst_idx = (y - char_h) * w + x
            pixels[dst_idx] = pixels[src_idx]
            x = x + 1
        end
        y = y + 1
    end
    # Clear the bottom char_h rows
    let clear_y = h - char_h
    while clear_y < h:
        let x = 0
        while x < w:
            let idx = clear_y * w + x
            pixels[idx] = con["bg_color"]
            x = x + 1
        end
        clear_y = clear_y + 1
    end
end

# Render a single character at the current cursor position
proc fb_putchar(con, ch):
    let cols = con["cols"]
    let rows = con["rows"]
    let char_w = con["char_w"]
    let char_h = con["char_h"]
    let w = con["width"]
    let pixels = con["pixels"]
    let fg = con["fg_color"]
    let bg = con["bg_color"]
    # Handle newline
    if ch == chr(10):
        con["cx"] = 0
        con["cy"] = con["cy"] + 1
        if con["cy"] >= rows:
            _fb_scroll_up(con)
            con["cy"] = rows - 1
        end
        return
    end
    # Handle carriage return
    if ch == chr(13):
        con["cx"] = 0
        return
    end
    # Handle tab
    if ch == chr(9):
        let spaces = 8 - (con["cx"] % 8)
        let s = 0
        while s < spaces:
            fb_putchar(con, " ")
            s = s + 1
        end
        return
    end
    # Get the 8x8 glyph bitmap
    let glyph = _font_get_glyph(ch)
    # Draw the glyph pixel by pixel
    let px = con["cx"] * char_w
    let py = con["cy"] * char_h
    let row = 0
    while row < 8:
        let bits = glyph[row]
        let col = 0
        while col < 8:
            let screen_x = px + col
            let screen_y = py + row
            if screen_x < w and screen_y < con["height"]:
                let idx = screen_y * w + screen_x
                # Check bit (MSB first): bit 7-col
                let mask = 128 >> col
                if (bits & mask) != 0:
                    pixels[idx] = fg
                else:
                    pixels[idx] = bg
                end
            end
            col = col + 1
        end
        row = row + 1
    end
    # Advance cursor
    con["cx"] = con["cx"] + 1
    if con["cx"] >= cols:
        con["cx"] = 0
        con["cy"] = con["cy"] + 1
        if con["cy"] >= rows:
            _fb_scroll_up(con)
            con["cy"] = rows - 1
        end
    end
end

# Render a string on the framebuffer console
proc fb_puts(con, text):
    let i = 0
    let tlen = len(text)
    while i < tlen:
        fb_putchar(con, text[i])
        i = i + 1
    end
end
