gc_disable()

# sage — Physical Memory Manager
# Bitmap-based allocator, 1 bit per 4KB page.

# ----- Constants -----
let PAGE_SIZE = 4096

# ----- Internal state -----
let bitmap = []
let bitmap_size = 0
let total_pages = 0
let used_pages = 0
let memory_total = 0
let pmm_ready = false

# ----- Alignment helpers -----

proc align_up(addr, alignment):
    let remainder = addr % alignment
    if remainder == 0:
        return addr
    end
    return addr + (alignment - remainder)
end

proc align_down(addr, alignment):
    return addr - (addr % alignment)
end

# ----- Bitmap helpers -----

proc bit_index(page_num):
    return page_num / 32
end

proc bit_offset(page_num):
    return page_num % 32
end

proc set_bit(page_num):
    let idx = bit_index(page_num)
    let off = bit_offset(page_num)
    if idx < bitmap_size:
        # Simulate setting a bit by using a power-of-two flag array
        # In a real kernel this would be bitwise OR on a u32.
        let entry = bitmap[idx]
        let flags = entry["flags"]
        if dict_has(flags, str(off)) == false:
            flags[str(off)] = true
            used_pages = used_pages + 1
        end
    end
end

proc clear_bit(page_num):
    let idx = bit_index(page_num)
    let off = bit_offset(page_num)
    if idx < bitmap_size:
        let entry = bitmap[idx]
        let flags = entry["flags"]
        if dict_has(flags, str(off)):
            dict_delete(flags, str(off))
            used_pages = used_pages - 1
        end
    end
end

proc test_bit(page_num):
    let idx = bit_index(page_num)
    let off = bit_offset(page_num)
    if idx >= bitmap_size:
        return true
    end
    let entry = bitmap[idx]
    let flags = entry["flags"]
    if dict_has(flags, str(off)):
        return true
    end
    return false
end

# ----- Initialize from memory map -----

proc init(memory_map):
    # Default: 16 MB if no map provided
    memory_total = 16 * 1024 * 1024
    if memory_map != nil:
        if len(memory_map) > 0:
            # Find the highest usable address
            let highest = 0
            let i = 0
            while i < len(memory_map):
                let region = memory_map[i]
                let region_end = region["base"] + region["length"]
                if region_end > highest:
                    highest = region_end
                end
                i = i + 1
            end
            if highest > 0:
                memory_total = highest
            end
        end
    end

    total_pages = memory_total / PAGE_SIZE
    used_pages = 0
    bitmap_size = (total_pages / 32) + 1

    # Initialize bitmap — all pages marked free (no bits set)
    bitmap = []
    let i = 0
    while i < bitmap_size:
        let entry = {}
        let flags = {}
        entry["flags"] = flags
        append(bitmap, entry)
        i = i + 1
    end

    # Mark non-usable regions from the memory map as used
    if memory_map != nil:
        let m = 0
        while m < len(memory_map):
            let region = memory_map[m]
            if dict_has(region, "type"):
                if region["type"] != "available":
                    mark_region(region["base"], region["base"] + region["length"], true)
                end
            end
            m = m + 1
        end
    end

    pmm_ready = true
end

# ----- Mark a region as used or free -----

proc mark_region(start, end_addr, used):
    let page_start = align_up(start, PAGE_SIZE) / PAGE_SIZE
    let page_end = align_down(end_addr, PAGE_SIZE) / PAGE_SIZE
    let p = page_start
    while p < page_end:
        if p < total_pages:
            if used:
                set_bit(p)
            end
            if used == false:
                clear_bit(p)
            end
        end
        p = p + 1
    end
end

# ----- Allocate a single 4KB page -----

proc alloc_page():
    let p = 0
    while p < total_pages:
        if test_bit(p) == false:
            set_bit(p)
            return p * PAGE_SIZE
        end
        p = p + 1
    end
    return nil
end

# ----- Free a single page -----

proc free_page(addr):
    let page_num = addr / PAGE_SIZE
    if page_num < total_pages:
        clear_bit(page_num)
    end
end

# ----- Allocate contiguous pages -----

proc alloc_pages(count):
    if count < 1:
        return nil
    end
    let p = 0
    while p <= total_pages - count:
        let found = true
        let c = 0
        while c < count:
            if test_bit(p + c):
                found = false
                break
            end
            c = c + 1
        end
        if found:
            let c2 = 0
            while c2 < count:
                set_bit(p + c2)
                c2 = c2 + 1
            end
            return p * PAGE_SIZE
        end
        p = p + 1
    end
    return nil
end

# ----- Free contiguous pages -----

proc free_pages(addr, count):
    let page_num = addr / PAGE_SIZE
    let c = 0
    while c < count:
        if page_num + c < total_pages:
            clear_bit(page_num + c)
        end
        c = c + 1
    end
end

# ----- Statistics -----

proc total_memory():
    return memory_total
end

proc used_memory():
    return used_pages * PAGE_SIZE
end

proc free_memory():
    return (total_pages - used_pages) * PAGE_SIZE
end

proc stats():
    let s = {}
    s["total_bytes"] = memory_total
    s["total_pages"] = total_pages
    s["used_pages"] = used_pages
    s["free_pages"] = total_pages - used_pages
    s["used_bytes"] = used_memory()
    s["free_bytes"] = free_memory()
    s["page_size"] = PAGE_SIZE
    return s
end
gc_disable()

# sage — Virtual Memory Manager
# x86-64 4-level paging: PML4 -> PDPT -> PD -> PT -> Page

let PAGE_SIZE = 4096

# ----- Page flags -----
let PAGE_PRESENT = 1
let PAGE_WRITABLE = 2
let PAGE_USER = 4
let PAGE_WRITETHROUGH = 8
let PAGE_NOCACHE = 16
let PAGE_ACCESSED = 32
let PAGE_DIRTY = 64
let PAGE_HUGE = 128
let PAGE_GLOBAL = 256
let PAGE_NX = 1 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2

# ----- Internal state -----
# Page tables stored as nested dicts keyed by virtual page number.
# Each entry: { "phys": physical_addr, "flags": flags }
let page_tables = {}
let kernel_pml4 = nil
let current_pml4 = nil
let vmm_ready = false

# ----- Helpers -----

proc page_number(addr):
    return addr / PAGE_SIZE
end

proc page_addr(page_num):
    return page_num * PAGE_SIZE
end

# ----- Initialize kernel address space -----

proc init():
    let state = vmm_init("x86_64")
    page_tables = state["entries"]
    kernel_pml4 = {}
    kernel_pml4["entries"] = state["entries"]
    kernel_pml4["addr"] = 0
    current_pml4 = kernel_pml4
    vmm_ready = true
end

# ----- Map a virtual page to a physical page -----

proc map_page(virt, phys, flags):
    let pn = page_number(virt)
    let entry = {}
    entry["phys"] = phys
    entry["flags"] = flags
    let key = str(pn)
    let entries = current_pml4["entries"]
    entries[key] = entry
end

# ----- Unmap a virtual page -----

proc unmap_page(virt):
    let pn = page_number(virt)
    let key = str(pn)
    let entries = current_pml4["entries"]
    if dict_has(entries, key):
        dict_delete(entries, key)
    end
end

# ----- Map a contiguous region -----

proc map_region(virt, phys, size, flags):
    let offset = 0
    while offset < size:
        map_page(virt + offset, phys + offset, flags)
        offset = offset + PAGE_SIZE
    end
end

# ----- Check if a virtual address is mapped -----

proc is_mapped(virt):
    let pn = page_number(virt)
    let key = str(pn)
    let entries = current_pml4["entries"]
    return dict_has(entries, key)
end

# ----- Translate virtual to physical -----

proc get_physical(virt):
    let pn = page_number(virt)
    let key = str(pn)
    let entries = current_pml4["entries"]
    if dict_has(entries, key) == false:
        return nil
    end
    let entry = entries[key]
    let page_offset = virt % PAGE_SIZE
    return entry["phys"] + page_offset
end

# ----- Create a new address space -----

proc create_address_space():
    let pml4 = {}
    pml4["entries"] = {}
    # Allocate a physical page for the PML4 table
    let phys_page = alloc_page()
    if phys_page == nil:
        pml4["addr"] = 0
    end
    if phys_page != nil:
        pml4["addr"] = phys_page
    end
    # Copy kernel mappings (upper half) into the new space
    let k_entries = kernel_pml4["entries"]
    let new_entries = pml4["entries"]
    let keys = dict_keys(k_entries)
    let i = 0
    while i < len(keys):
        let k = keys[i]
        let src = k_entries[k]
        let dst = {}
        dst["phys"] = src["phys"]
        dst["flags"] = src["flags"]
        new_entries[k] = dst
        i = i + 1
    end
    return pml4
end

# ----- Switch address space (set CR3) -----

proc switch_address_space(pml4):
    # In a real kernel: mov cr3, pml4["addr"]
    current_pml4 = pml4
end

# ----- Get kernel address space -----

proc kernel_address_space():
    return kernel_pml4
end

# ----- Get current address space -----

proc current_address_space():
    return current_pml4
end

# ----- Statistics -----

proc stats():
    let entries = current_pml4["entries"]
    let keys = dict_keys(entries)
    let s = {}
    s["mapped_pages"] = len(keys)
    s["mapped_bytes"] = len(keys) * PAGE_SIZE
    s["pml4_addr"] = current_pml4["addr"]
    return s
end

# =========================================================================
# Architecture-Aware VMM Interface
# =========================================================================
# Supports "x86_64", "aarch64", and "riscv64".
# The existing x86_64 functions above remain untouched; these new
# functions dispatch per-architecture using a state dict.

# ----- AArch64 page flags -----
let AARCH64_PAGE_VALID = 1
let AARCH64_PAGE_TABLE = 2
let AARCH64_PAGE_AF    = 1024
let AARCH64_PAGE_AP_RW = 64

# ----- RISC-V 64 page flags -----
let RV64_PAGE_V = 1
let RV64_PAGE_R = 2
let RV64_PAGE_W = 4
let RV64_PAGE_X = 8
let RV64_PAGE_U = 16

# ----- Create an arch-specific VMM state -----

proc vmm_init(arch):
    let state = {}
    state["arch"] = arch
    state["entries"] = {}
    state["ready"] = false

    if arch == "x86_64":
        # Identity-map first 4 MB (1024 pages)
        let addr = 0
        let end_addr = 4 * 1024 * 1024
        let flags = PAGE_PRESENT + PAGE_WRITABLE
        let entries = state["entries"]
        while addr < end_addr:
            let pn = page_number(addr)
            let entry = {}
            entry["phys"] = addr
            entry["flags"] = flags
            entries[str(pn)] = entry
            addr = addr + PAGE_SIZE
        end
        # Map VGA text buffer
        let vga_pn = page_number(753664)
        let vga_entry = {}
        vga_entry["phys"] = 753664
        vga_entry["flags"] = PAGE_PRESENT + PAGE_WRITABLE
        entries[str(vga_pn)] = vga_entry
    end

    if arch == "aarch64":
        # Identity-map first 4 MB with valid + table + AF + AP_RW
        let addr = 0
        let end_addr = 4 * 1024 * 1024
        let flags = AARCH64_PAGE_VALID + AARCH64_PAGE_TABLE + AARCH64_PAGE_AF + AARCH64_PAGE_AP_RW
        let entries = state["entries"]
        while addr < end_addr:
            let pn = page_number(addr)
            let entry = {}
            entry["phys"] = addr
            entry["flags"] = flags
            let key = str(pn)
            entries[key] = entry
            page_tables[key] = entry
            addr = addr + PAGE_SIZE
        end
    end

    if arch == "riscv64":
        # Identity-map first 4 MB with V + R + W
        let addr = 0
        let end_addr = 4 * 1024 * 1024
        let flags = RV64_PAGE_V + RV64_PAGE_R + RV64_PAGE_W
        let entries = state["entries"]
        while addr < end_addr:
            let pn = page_number(addr)
            let entry = {}
            entry["phys"] = addr
            entry["flags"] = flags
            let key = str(pn)
            entries[key] = entry
            page_tables[key] = entry
            addr = addr + PAGE_SIZE
        end
    end

    state["ready"] = true
    return state
end

# ----- Map a virtual page in an arch-aware VMM state -----

proc vmm_map(state, vaddr, paddr, flags):
    let arch = state["arch"]
    let pn = page_number(vaddr)
    let key = str(pn)
    let entry = {}
    entry["phys"] = paddr
    entry["flags"] = flags

    if arch == "x86_64":
        let entries = state["entries"]
        entries[key] = entry
    end
    if arch == "aarch64":
        let entries = state["entries"]
        entries[key] = entry
    end
    if arch == "riscv64":
        let entries = state["entries"]
        entries[key] = entry
    end
end

# ----- Unmap a virtual page in an arch-aware VMM state -----

proc vmm_unmap(state, vaddr):
    let arch = state["arch"]
    let pn = page_number(vaddr)
    let key = str(pn)

    if arch == "x86_64":
        let entries = state["entries"]
        if dict_has(entries, key):
            dict_delete(entries, key)
        end
    end
    if arch == "aarch64":
        let entries = state["entries"]
        if dict_has(entries, key):
            dict_delete(entries, key)
        end
    end
    if arch == "riscv64":
        let entries = state["entries"]
        if dict_has(entries, key):
            dict_delete(entries, key)
        end
    end
end
gc_disable()

# sage — VGA text mode and framebuffer console driver
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

# ================================================================
# Hardware mode flag and bare-metal code generation
# ================================================================
# Controls whether console operations target the simulated buffer
# or generate hardware-targeted assembly for bare-metal execution.

let hardware_mode = "simulated"

# ----- Set hardware mode ("simulated" or "hardware") -----
proc set_hardware_mode(mode):
    if mode == "simulated" or mode == "hardware":
        hardware_mode = mode
    end
end

# ----- Write a character+color to the simulated VGA buffer -----
# Sage-callable proc that computes the VGA buffer offset and stores
# the character+color entry at the correct position in vga_buffer.
proc vga_write_char(x, y, ch, color):
    if vga_ready == false:
        return
    end
    if x < 0 or x >= VGA_WIDTH:
        return
    end
    if y < 0 or y >= VGA_HEIGHT:
        return
    end
    let offset = y * VGA_WIDTH + x
    vga_buffer[offset]["char"] = ch
    vga_buffer[offset]["color"] = color
end

# ----- Generate x86_64 assembly: clear VGA screen -----
# Emits assembly that fills VGA memory at 0xB8000 through 0xB8FA0
# with space characters (0x20) and light-gray-on-black attribute (0x07).
# Total bytes: 80 * 25 * 2 = 4000 (0xFA0).
proc emit_console_init_asm():
    let lines = []
    append(lines, "# emit_console_init_asm: clear VGA text screen")
    append(lines, ".globl console_init")
    append(lines, "console_init:")
    append(lines, "    movq $0xB8000, %rdi")
    append(lines, "    movl $2000, %ecx          # 80*25 = 2000 cells")
    append(lines, "    movw $0x0720, %ax          # space (0x20) + light gray attr (0x07)")
    append(lines, ".Lclear_loop:")
    append(lines, "    movw %ax, (%rdi)")
    append(lines, "    addq $2, %rdi")
    append(lines, "    decl %ecx")
    append(lines, "    jnz .Lclear_loop")
    append(lines, "    # Reset cursor position to (0, 0)")
    append(lines, "    movl $0, cursor_x_hw(%rip)")
    append(lines, "    movl $0, cursor_y_hw(%rip)")
    append(lines, "    ret")
    append(lines, "")
    append(lines, ".section .bss")
    append(lines, "cursor_x_hw: .long 0")
    append(lines, "cursor_y_hw: .long 0")
    append(lines, ".section .text")
    return lines
end

# ----- Generate x86_64 assembly: write char+attr to VGA memory -----
# Emits assembly for a procedure that takes:
#   %dil  = ASCII character
#   %sil  = color attribute byte
# Writes the 16-bit value (attr << 8 | char) to VGA memory at
# 0xB8000 + (cursor_y_hw * 80 + cursor_x_hw) * 2, then advances
# the cursor. Handles newline (0x0A) and line wrapping/scrolling.
proc emit_vga_putchar_asm():
    let lines = []
    append(lines, "# emit_vga_putchar_asm: write char to VGA memory")
    append(lines, ".globl vga_putchar_hw")
    append(lines, "vga_putchar_hw:")
    append(lines, "    pushq %rbx")
    append(lines, "    pushq %r12")
    append(lines, "    pushq %r13")
    append(lines, "    movzbl %dil, %r12d         # r12 = character")
    append(lines, "    movzbl %sil, %r13d         # r13 = color attribute")
    append(lines, "")
    append(lines, "    # Handle newline (0x0A)")
    append(lines, "    cmpl $0x0A, %r12d")
    append(lines, "    jne .Lvga_not_newline")
    append(lines, "    movl $0, cursor_x_hw(%rip)")
    append(lines, "    movl cursor_y_hw(%rip), %eax")
    append(lines, "    incl %eax")
    append(lines, "    cmpl $25, %eax")
    append(lines, "    jl .Lvga_newline_ok")
    append(lines, "    movl $24, %eax             # clamp to last row (scroll not impl here)")
    append(lines, ".Lvga_newline_ok:")
    append(lines, "    movl %eax, cursor_y_hw(%rip)")
    append(lines, "    jmp .Lvga_done")
    append(lines, "")
    append(lines, ".Lvga_not_newline:")
    append(lines, "    # Compute offset: (cursor_y * 80 + cursor_x) * 2")
    append(lines, "    movl cursor_y_hw(%rip), %eax")
    append(lines, "    imull $80, %eax, %eax")
    append(lines, "    addl cursor_x_hw(%rip), %eax")
    append(lines, "    shll $1, %eax              # * 2 for 16-bit cells")
    append(lines, "    movl %eax, %ebx")
    append(lines, "")
    append(lines, "    # Build 16-bit value: attr << 8 | char")
    append(lines, "    movl %r13d, %eax")
    append(lines, "    shll $8, %eax")
    append(lines, "    orl %r12d, %eax")
    append(lines, "")
    append(lines, "    # Write to VGA memory")
    append(lines, "    movq $0xB8000, %rdi")
    append(lines, "    movslq %ebx, %rbx")
    append(lines, "    movw %ax, (%rdi, %rbx)")
    append(lines, "")
    append(lines, "    # Advance cursor_x, wrap at 80")
    append(lines, "    movl cursor_x_hw(%rip), %eax")
    append(lines, "    incl %eax")
    append(lines, "    cmpl $80, %eax")
    append(lines, "    jl .Lvga_no_wrap")
    append(lines, "    movl $0, %eax")
    append(lines, "    movl cursor_y_hw(%rip), %ecx")
    append(lines, "    incl %ecx")
    append(lines, "    cmpl $25, %ecx")
    append(lines, "    jl .Lvga_wrap_ok")
    append(lines, "    movl $24, %ecx             # clamp to bottom row")
    append(lines, ".Lvga_wrap_ok:")
    append(lines, "    movl %ecx, cursor_y_hw(%rip)")
    append(lines, ".Lvga_no_wrap:")
    append(lines, "    movl %eax, cursor_x_hw(%rip)")
    append(lines, "")
    append(lines, ".Lvga_done:")
    append(lines, "    popq %r13")
    append(lines, "    popq %r12")
    append(lines, "    popq %rbx")
    append(lines, "    ret")
    return lines
end

# ----- Generate x86_64 assembly: output char to COM1 serial port -----
# Emits assembly for a serial console fallback. Takes character in %dil.
# Writes to I/O port 0x3F8 (COM1) after waiting for the transmit
# holding register to be empty (status port 0x3FD, bit 5).
proc emit_serial_console_asm():
    let lines = []
    append(lines, "# emit_serial_console_asm: write char to COM1 (0x3F8)")
    append(lines, ".globl serial_putchar")
    append(lines, "serial_putchar:")
    append(lines, "    pushq %rbx")
    append(lines, "    movzbl %dil, %ebx          # save character in ebx")
    append(lines, "")
    append(lines, "    # Wait for transmit holding register empty (bit 5 of LSR)")
    append(lines, ".Lserial_wait:")
    append(lines, "    movw $0x3FD, %dx           # Line Status Register")
    append(lines, "    inb %dx, %al")
    append(lines, "    testb $0x20, %al            # bit 5 = THRE")
    append(lines, "    jz .Lserial_wait")
    append(lines, "")
    append(lines, "    # Send character")
    append(lines, "    movw $0x3F8, %dx           # COM1 data port")
    append(lines, "    movb %bl, %al")
    append(lines, "    outb %al, %dx")
    append(lines, "")
    append(lines, "    popq %rbx")
    append(lines, "    ret")
    return lines
end
gc_disable()

# sage — PS/2 keyboard driver
# Handles scancodes from port 0x60, US QWERTY layout.


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
            print_line("")
            done = true
            continue
        end
        if key["scancode"] == KEY_BACKSPACE:
            if len(line) > 0:
                line = line[0:len(line) - 1]
                let pos = get_cursor()
                let nx = pos["x"] - 1
                if nx < 0:
                    nx = 0
                end
                set_cursor(nx, pos["y"])
                putchar(" ", 7)
                set_cursor(nx, pos["y"])
            end
            continue
        end
        line = line + ch
        print_str(ch)
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
gc_disable()

# sage — Programmable Interval Timer (PIT) driver
# Configures PIT channel 0 for periodic interrupts.

# ----- PIT constants -----
let PIT_FREQ = 1193182
let PIT_CHANNEL0 = 64
let PIT_CMD = 67

# ----- Timer state -----
let tick_count = 0
let timer_freq = 0
let ms_per_tick = 0
let timer_handler = nil
let timer_ready = false

proc init(frequency_hz):
    if frequency_hz < 1:
        frequency_hz = 1
    end
    timer_freq = frequency_hz
    # Calculate the PIT divisor
    let divisor = PIT_FREQ / frequency_hz

    # In a real kernel we would:
    #   outb(PIT_CMD, 0x36)        — channel 0, lo/hi, rate generator
    #   outb(PIT_CHANNEL0, divisor & 0xFF)
    #   outb(PIT_CHANNEL0, (divisor >> 8) & 0xFF)

    ms_per_tick = 1000 / frequency_hz
    tick_count = 0
    timer_handler = nil
    timer_ready = true
end

proc tick():
    # Called by the IRQ0 handler on each timer interrupt.
    tick_count = tick_count + 1
    if timer_handler != nil:
        timer_handler()
    end
end

proc get_ticks():
    return tick_count
end

proc get_uptime_ms():
    return tick_count * ms_per_tick
end

proc get_uptime_s():
    return get_uptime_ms() / 1000
end

proc sleep_ms(ms):
    if timer_ready == false:
        return
    end
    let target = get_uptime_ms() + ms
    while get_uptime_ms() < target:
        # busy-wait
        let dummy = 0
    end
end

proc sleep_s(s):
    sleep_ms(s * 1000)
end

proc set_handler(callback):
    timer_handler = callback
end

proc get_frequency():
    return timer_freq
end

proc reset():
    tick_count = 0
end

proc stats():
    let s = {}
    s["ticks"] = tick_count
    s["frequency_hz"] = timer_freq
    s["ms_per_tick"] = ms_per_tick
    s["uptime_ms"] = get_uptime_ms()
    s["uptime_s"] = get_uptime_s()
    return s
end

# ================================================================
# aarch64 Generic Timer support
# ================================================================
# The ARM Generic Timer uses system registers:
#   CNTFRQ_EL0  — counter frequency (set by firmware)
#   CNTP_TVAL_EL0 — timer value (countdown)
#   CNTP_CTL_EL0  — control (bit 0 = ENABLE, bit 1 = IMASK)

proc aarch64_timer_config(freq_hz):
    let cfg = {}
    # CNTFRQ is typically set by firmware (e.g., 62.5 MHz on many boards)
    # but we store the desired interrupt frequency
    cfg["arch"] = "aarch64"
    cfg["freq_hz"] = freq_hz
    cfg["cntfrq"] = 62500000
    # Timer value: number of counter ticks between interrupts
    cfg["cntp_tval"] = cfg["cntfrq"] / freq_hz
    # Control: ENABLE=1, IMASK=0
    cfg["cntp_ctl"] = 1
    return cfg
end

proc aarch64_timer_init_sequence(freq_hz):
    let cfg = aarch64_timer_config(freq_hz)
    let seq = []
    # Step 1: Write CNTP_TVAL_EL0 (countdown value)
    let s1 = {}
    s1["reg"] = "CNTP_TVAL_EL0"
    s1["value"] = cfg["cntp_tval"]
    push(seq, s1)
    # Step 2: Write CNTP_CTL_EL0 (enable timer, unmask interrupt)
    let s2 = {}
    s2["reg"] = "CNTP_CTL_EL0"
    s2["value"] = cfg["cntp_ctl"]
    push(seq, s2)
    return seq
end

# ================================================================
# riscv64 CLINT timer support
# ================================================================
# CLINT memory-mapped registers:
#   MTIME    — 64-bit free-running counter (at clint_base + 0xBFF8)
#   MTIMECMP — 64-bit compare register (at clint_base + 0x4000, per-hart)

proc riscv64_timer_config(clint_base, freq_hz):
    let cfg = {}
    cfg["arch"] = "riscv64"
    cfg["clint_base"] = clint_base
    cfg["freq_hz"] = freq_hz
    cfg["mtime_addr"] = clint_base + 49144
    cfg["mtimecmp_addr"] = clint_base + 16384
    # Assume 10 MHz default timer frequency (common in QEMU/SiFive)
    cfg["timer_freq"] = 10000000
    cfg["interval"] = cfg["timer_freq"] / freq_hz
    return cfg
end

proc riscv64_timer_init_sequence(clint_base, freq_hz):
    let cfg = riscv64_timer_config(clint_base, freq_hz)
    let seq = []
    # Step 1: Read MTIME to get current counter
    let s1 = {}
    s1["addr"] = cfg["mtime_addr"]
    s1["action"] = "read64"
    s1["label"] = "current_time"
    push(seq, s1)
    # Step 2: Write MTIMECMP = current_time + interval
    let s2 = {}
    s2["addr"] = cfg["mtimecmp_addr"]
    s2["value"] = cfg["interval"]
    s2["action"] = "write64_add_current"
    push(seq, s2)
    return seq
end

# ================================================================
# Multi-architecture timer dispatcher
# ================================================================

proc timer_init(arch, config):
    if arch == "x86" or arch == "x86_64":
        let freq = 100
        if config != nil:
            if config["freq_hz"] != nil:
                freq = config["freq_hz"]
            end
        end
        init(freq)
        return stats()
    end
    if arch == "aarch64":
        let freq = 100
        if config != nil:
            if config["freq_hz"] != nil:
                freq = config["freq_hz"]
            end
        end
        let result = {}
        result["arch"] = "aarch64"
        result["config"] = aarch64_timer_config(freq)
        result["init_sequence"] = aarch64_timer_init_sequence(freq)
        return result
    end
    if arch == "riscv64":
        let clint_base = 33554432
        let freq = 100
        if config != nil:
            if config["clint_base"] != nil:
                clint_base = config["clint_base"]
            end
            if config["freq_hz"] != nil:
                freq = config["freq_hz"]
            end
        end
        let result = {}
        result["arch"] = "riscv64"
        result["config"] = riscv64_timer_config(clint_base, freq)
        result["init_sequence"] = riscv64_timer_init_sequence(clint_base, freq)
        return result
    end
    return nil
end

# ================================================================
# Hardware I/O Assembly Emission
# ================================================================

comptime:
    let PIT_BASE_FREQ = 1193182
    let PIT_CHANNEL0_PORT = 64
    let PIT_CMD_PORT = 67
    let PIT_MODE3_CMD = 54
    let PIC_CMD_PORT = 32
    let EOI_BYTE = 32
    let CLINT_MTIMECMP_OFFSET = 16384
    let CLINT_MTIME_OFFSET = 49144
end

proc emit_pit_init_asm(frequency):
    # x86_64 assembly to initialize PIT channel 0
    let nl = chr(10)
    let tab = chr(9)
    let divisor = 1193182 / frequency
    let divisor_lo = divisor % 256
    let divisor_hi = (divisor / 256) % 256
    let asm = ""
    asm = asm + ".global pit_init" + nl
    asm = asm + ".type pit_init, @function" + nl
    asm = asm + "pit_init:" + nl
    # Command byte: channel 0, lo/hi byte, mode 3 (square wave)
    asm = asm + tab + "movb $0x36, %al" + nl
    asm = asm + tab + "outb %al, $0x43" + nl
    # Send low byte of divisor to channel 0 data port
    asm = asm + tab + "movb $" + str(divisor_lo) + ", %al" + nl
    asm = asm + tab + "outb %al, $0x40" + nl
    # Send high byte of divisor to channel 0 data port
    asm = asm + tab + "movb $" + str(divisor_hi) + ", %al" + nl
    asm = asm + tab + "outb %al, $0x40" + nl
    asm = asm + tab + "ret" + nl
    return asm
end

proc emit_timer_isr_asm():
    # x86_64 assembly for IRQ0 (timer) interrupt handler
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global timer_isr" + nl
    asm = asm + ".type timer_isr, @function" + nl
    asm = asm + "timer_isr:" + nl
    # Save rax
    asm = asm + tab + "push %rax" + nl
    # Increment global tick_count
    asm = asm + tab + "movq tick_count_hw(%rip), %rax" + nl
    asm = asm + tab + "incq %rax" + nl
    asm = asm + tab + "movq %rax, tick_count_hw(%rip)" + nl
    # Send EOI to PIC
    asm = asm + tab + "movb $0x20, %al" + nl
    asm = asm + tab + "outb %al, $0x20" + nl
    # Restore rax
    asm = asm + tab + "pop %rax" + nl
    asm = asm + tab + "iretq" + nl
    asm = asm + nl
    # Global tick counter variable
    asm = asm + ".section .bss" + nl
    asm = asm + ".global tick_count_hw" + nl
    asm = asm + "tick_count_hw:" + nl
    asm = asm + tab + ".quad 0" + nl
    return asm
end

proc emit_aarch64_timer_init_asm(freq):
    # aarch64 assembly to initialize the Generic Timer
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global aarch64_timer_init_hw" + nl
    asm = asm + ".type aarch64_timer_init_hw, @function" + nl
    asm = asm + "aarch64_timer_init_hw:" + nl
    # Load interval value into x0
    asm = asm + tab + "mov x0, #" + str(freq) + nl
    # Set CNTV_TVAL_EL0 (virtual timer value)
    asm = asm + tab + "msr CNTV_TVAL_EL0, x0" + nl
    # Enable virtual timer: set bit 0 of CNTV_CTL_EL0
    asm = asm + tab + "mov x0, #1" + nl
    asm = asm + tab + "msr CNTV_CTL_EL0, x0" + nl
    asm = asm + tab + "ret" + nl
    return asm
end

proc emit_riscv64_timer_init_asm(interval):
    # riscv64 assembly to initialize CLINT timer (QEMU virt platform)
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global riscv64_timer_init_hw" + nl
    asm = asm + ".type riscv64_timer_init_hw, @function" + nl
    asm = asm + "riscv64_timer_init_hw:" + nl
    # Load CLINT base address (0x02000000 for QEMU virt)
    asm = asm + tab + "li t0, 0x02000000" + nl
    # Load MTIME: base + 0xBFF8
    asm = asm + tab + "li t1, 0xBFF8" + nl
    asm = asm + tab + "add t1, t0, t1" + nl
    asm = asm + tab + "ld t2, 0(t1)" + nl
    # Add interval to current MTIME
    asm = asm + tab + "li t3, " + str(interval) + nl
    asm = asm + tab + "add t2, t2, t3" + nl
    # Store to MTIMECMP: base + 0x4000
    asm = asm + tab + "li t1, 0x4000" + nl
    asm = asm + tab + "add t1, t0, t1" + nl
    asm = asm + tab + "sd t2, 0(t1)" + nl
    asm = asm + tab + "ret" + nl
    return asm
end
gc_disable()

# sage — System call dispatch table
# Handles int 0x80 / SYSCALL instruction dispatch.


# ----- Syscall number constants -----
let SYS_EXIT = 0
let SYS_WRITE = 1
let SYS_READ = 2
let SYS_OPEN = 3
let SYS_CLOSE = 4
let SYS_MMAP = 5
let SYS_FORK = 6
let SYS_EXEC = 7
let SYS_GETPID = 8
let SYS_YIELD = 9

# ----- Internal state -----
let syscall_handlers = []
let syscall_names = []
let syscall_counts = []
let max_syscalls = 256
let next_pid = 1
let syscall_ready = false

proc init():
    syscall_handlers = []
    syscall_names = []
    syscall_counts = []
    let i = 0
    while i < max_syscalls:
        append(syscall_handlers, nil)
        append(syscall_names, "")
        append(syscall_counts, 0)
        i = i + 1
    end
    # Register built-in syscalls
    register(SYS_EXIT, "exit", builtin_exit)
    register(SYS_WRITE, "write", builtin_write)
    register(SYS_READ, "read", builtin_read)
    register(SYS_OPEN, "open", builtin_open)
    register(SYS_CLOSE, "close", builtin_close)
    register(SYS_MMAP, "mmap", builtin_mmap)
    register(SYS_FORK, "fork", builtin_fork)
    register(SYS_EXEC, "exec", builtin_exec)
    register(SYS_GETPID, "getpid", builtin_getpid)
    register(SYS_YIELD, "yield", builtin_yield)
    syscall_ready = true
end

proc register(number, name, handler):
    if number < 0:
        return false
    end
    if number >= max_syscalls:
        return false
    end
    syscall_handlers[number] = handler
    syscall_names[number] = name
    syscall_counts[number] = 0
    return true
end

proc dispatch(syscall_num, args):
    if syscall_num < 0:
        return -1
    end
    if syscall_num >= max_syscalls:
        return -1
    end
    let handler = syscall_handlers[syscall_num]
    if handler == nil:
        return -1
    end
    syscall_counts[syscall_num] = syscall_counts[syscall_num] + 1
    return handler(args)
end

# ----- Built-in syscall implementations -----

proc sys_write(fd, buf, length):
    let args = {}
    args["fd"] = fd
    args["buf"] = buf
    args["len"] = length
    return dispatch(SYS_WRITE, args)
end

proc sys_read(fd, buf, length):
    let args = {}
    args["fd"] = fd
    args["buf"] = buf
    args["len"] = length
    return dispatch(SYS_READ, args)
end

proc sys_exit(code):
    let args = {}
    args["code"] = code
    return dispatch(SYS_EXIT, args)
end

# ----- Built-in handlers -----

proc builtin_exit(args):
    let code = 0
    if args != nil:
        if dict_has(args, "code"):
            code = args["code"]
        end
    end
    # In a real kernel this terminates the current process.
    return code
end

proc builtin_write(args):
    if args == nil:
        return -1
    end
    let fd = args["fd"]
    let buf = args["buf"]
    let length = args["len"]
    # fd 1 = stdout, fd 2 = stderr
    if fd == 1:
        print_str(buf)
        return length
    end
    if fd == 2:
        let old_fg = current_fg
        set_color(RED, BLACK)
        print_str(buf)
        set_color(old_fg, BLACK)
        return length
    end
    return -1
end

proc builtin_read(args):
    if args == nil:
        return -1
    end
    let fd = args["fd"]
    let count = 0
    if dict_has(args, "count"):
        count = args["count"]
    end
    # fd 0 = stdin — read from keyboard buffer
    if fd == 0:
        if dict_has(args, "buffer"):
            # Copy available bytes into buffer (non-blocking)
            let buf = args["buffer"]
            let read_count = 0
            while read_count < count:
                if dict_has(args, "kbd_buffer"):
                    if len(args["kbd_buffer"]) > 0:
                        push(buf, args["kbd_buffer"][0])
                        let new_buf = []
                        let ki = 1
                        while ki < len(args["kbd_buffer"]):
                            push(new_buf, args["kbd_buffer"][ki])
                            ki = ki + 1
                        end
                        args["kbd_buffer"] = new_buf
                        read_count = read_count + 1
                    else:
                        return read_count
                    end
                else:
                    return read_count
                end
            end
            return read_count
        end
        return 0
    end
    # fd 1, 2 = stdout/stderr (not readable)
    if fd == 1 or fd == 2:
        return -1
    end
    # Other fds: check open file table
    if dict_has(args, "file_table"):
        if dict_has(args["file_table"], str(fd)):
            let file = args["file_table"][str(fd)]
            if dict_has(file, "data"):
                let data = file["data"]
                let pos = file["pos"]
                let result = []
                let read_count = 0
                while read_count < count and pos < len(data):
                    push(result, data[pos])
                    pos = pos + 1
                    read_count = read_count + 1
                end
                file["pos"] = pos
                return read_count
            end
        end
    end
    return -1
end

# In-memory file table for the kernel
let _file_table = {}
let _next_fd = 3

proc builtin_open(args):
    if args == nil:
        return -1
    end
    if not dict_has(args, "path"):
        return -1
    end
    let path = args["path"]
    let flags = 0
    if dict_has(args, "flags"):
        flags = args["flags"]
    end
    # Allocate a file descriptor
    let fd = _next_fd
    _next_fd = _next_fd + 1
    let file = {}
    file["path"] = path
    file["flags"] = flags
    file["pos"] = 0
    file["data"] = []
    _file_table[str(fd)] = file
    return fd
end

proc builtin_close(args):
    if args == nil:
        return -1
    end
    let fd = args["fd"]
    let key = str(fd)
    if dict_has(_file_table, key):
        dict_delete(_file_table, key)
        return 0
    end
    return -1
end

proc builtin_mmap(args):
    if args == nil:
        return -1
    end
    let addr = 0
    if dict_has(args, "addr"):
        addr = args["addr"]
    end
    let length = 4096
    if dict_has(args, "length"):
        length = args["length"]
    end
    # Allocate a simulated memory region (array of zeros)
    let region = {}
    region["addr"] = addr
    region["length"] = length
    region["data"] = []
    let i = 0
    while i < length:
        push(region["data"], 0)
        i = i + 1
    end
    return region
end

proc builtin_fork(args):
    # Allocate a new PID for the child process
    let pid = next_pid
    next_pid = next_pid + 1
    return pid
end

proc builtin_exec(args):
    if args == nil:
        return -1
    end
    if not dict_has(args, "path"):
        return -1
    end
    # In kernel context, exec replaces the current process image
    # Return the path as confirmation (actual exec requires ELF loader)
    let path = args["path"]
    let result = {}
    result["status"] = 0
    result["path"] = path
    result["pid"] = builtin_getpid(nil)
    return result
end

proc builtin_getpid(args):
    # Return current PID (kernel init process = 1)
    return 1
end

proc builtin_yield(args):
    # Cooperative yield: in a single-tasked kernel, this is a no-op
    # In a multi-tasked kernel, this would switch to the next ready task
    # Return 0 to indicate success
    return 0
end

# ----- Introspection -----

proc syscall_table():
    let entries = []
    let i = 0
    while i < max_syscalls:
        if syscall_names[i] != "":
            let entry = {}
            entry["number"] = i
            entry["name"] = syscall_names[i]
            append(entries, entry)
        end
        i = i + 1
    end
    return entries
end

proc stats():
    let s = {}
    s["total_calls"] = 0
    let entries = []
    let i = 0
    while i < max_syscalls:
        if syscall_names[i] != "":
            let entry = {}
            entry["number"] = i
            entry["name"] = syscall_names[i]
            entry["count"] = syscall_counts[i]
            s["total_calls"] = s["total_calls"] + syscall_counts[i]
            append(entries, entry)
        end
        i = i + 1
    end
    s["syscalls"] = entries
    return s
end

# ================================================================
# Hardware I/O Assembly Emission
# ================================================================

comptime:
    let MSR_STAR = 3221225601
    let MSR_LSTAR = 3221225602
    let MSR_SFMASK = 3221225604
    let KERNEL_CS = 8
    let KERNEL_SS = 16
    let USER_CS = 24
    let USER_SS = 32
    let IF_FLAG_BIT = 512
end

proc emit_syscall_entry_asm():
    # x86_64 assembly for SYSCALL instruction entry point
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global syscall_entry" + nl
    asm = asm + ".type syscall_entry, @function" + nl
    asm = asm + "syscall_entry:" + nl
    # Swap to kernel GS base (per-cpu data)
    asm = asm + tab + "swapgs" + nl
    # Save user RSP to per-cpu area, load kernel RSP
    asm = asm + tab + "movq %rsp, %gs:8" + nl
    asm = asm + tab + "movq %gs:0, %rsp" + nl
    # Push all general-purpose registers
    asm = asm + tab + "push %r15" + nl
    asm = asm + tab + "push %r14" + nl
    asm = asm + tab + "push %r13" + nl
    asm = asm + tab + "push %r12" + nl
    asm = asm + tab + "push %r11" + nl
    asm = asm + tab + "push %r10" + nl
    asm = asm + tab + "push %r9" + nl
    asm = asm + tab + "push %r8" + nl
    asm = asm + tab + "push %rbp" + nl
    asm = asm + tab + "push %rdi" + nl
    asm = asm + tab + "push %rsi" + nl
    asm = asm + tab + "push %rdx" + nl
    asm = asm + tab + "push %rcx" + nl
    asm = asm + tab + "push %rbx" + nl
    asm = asm + tab + "push %rax" + nl
    # Syscall number in rax -> first arg (rdi) for syscall_dispatch
    asm = asm + tab + "movq %rax, %rdi" + nl
    asm = asm + tab + "call syscall_dispatch" + nl
    # Pop all general-purpose registers
    asm = asm + tab + "pop %rax" + nl
    asm = asm + tab + "pop %rbx" + nl
    asm = asm + tab + "pop %rcx" + nl
    asm = asm + tab + "pop %rdx" + nl
    asm = asm + tab + "pop %rsi" + nl
    asm = asm + tab + "pop %rdi" + nl
    asm = asm + tab + "pop %rbp" + nl
    asm = asm + tab + "pop %r8" + nl
    asm = asm + tab + "pop %r9" + nl
    asm = asm + tab + "pop %r10" + nl
    asm = asm + tab + "pop %r11" + nl
    asm = asm + tab + "pop %r12" + nl
    asm = asm + tab + "pop %r13" + nl
    asm = asm + tab + "pop %r14" + nl
    asm = asm + tab + "pop %r15" + nl
    # Restore user RSP, swap back to user GS
    asm = asm + tab + "movq %gs:8, %rsp" + nl
    asm = asm + tab + "swapgs" + nl
    asm = asm + tab + "sysretq" + nl
    return asm
end

proc emit_syscall_init_asm():
    # x86_64 assembly to configure SYSCALL/SYSRET via MSRs
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global syscall_msr_init" + nl
    asm = asm + ".type syscall_msr_init, @function" + nl
    asm = asm + "syscall_msr_init:" + nl
    # Write STAR MSR (0xC0000081): kernel CS/SS in bits 47:32, user CS/SS in bits 63:48
    # Kernel CS=0x08, SS=0x10 -> bits 47:32 = 0x0008
    # User CS=0x18|3=0x1B, SS=0x20|3=0x23 -> bits 63:48 = 0x0018 (base, CPU adds 16+3)
    asm = asm + tab + "movl $0xC0000081, %ecx" + nl
    asm = asm + tab + "xorl %edx, %edx" + nl
    asm = asm + tab + "movl $0x00180008, %edx" + nl
    asm = asm + tab + "xorl %eax, %eax" + nl
    asm = asm + tab + "wrmsr" + nl
    # Write LSTAR MSR (0xC0000082): address of syscall_entry
    asm = asm + tab + "movl $0xC0000082, %ecx" + nl
    asm = asm + tab + "leaq syscall_entry(%rip), %rax" + nl
    asm = asm + tab + "movq %rax, %rdx" + nl
    asm = asm + tab + "shrq $32, %rdx" + nl
    asm = asm + tab + "wrmsr" + nl
    # Write SFMASK MSR (0xC0000084): mask IF flag (bit 9 = 0x200)
    asm = asm + tab + "movl $0xC0000084, %ecx" + nl
    asm = asm + tab + "xorl %edx, %edx" + nl
    asm = asm + tab + "movl $0x200, %eax" + nl
    asm = asm + tab + "wrmsr" + nl
    asm = asm + tab + "ret" + nl
    return asm
end

proc emit_svc_entry_aarch64():
    # aarch64 assembly for SVC (supervisor call) exception entry
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global svc_entry" + nl
    asm = asm + ".type svc_entry, @function" + nl
    asm = asm + "svc_entry:" + nl
    # Save general-purpose registers x0-x30 and ELR_EL1 to stack
    asm = asm + tab + "sub sp, sp, #264" + nl
    asm = asm + tab + "stp x0, x1, [sp, #0]" + nl
    asm = asm + tab + "stp x2, x3, [sp, #16]" + nl
    asm = asm + tab + "stp x4, x5, [sp, #32]" + nl
    asm = asm + tab + "stp x6, x7, [sp, #48]" + nl
    asm = asm + tab + "stp x8, x9, [sp, #64]" + nl
    asm = asm + tab + "stp x10, x11, [sp, #80]" + nl
    asm = asm + tab + "stp x12, x13, [sp, #96]" + nl
    asm = asm + tab + "stp x14, x15, [sp, #112]" + nl
    asm = asm + tab + "stp x16, x17, [sp, #128]" + nl
    asm = asm + tab + "stp x18, x19, [sp, #144]" + nl
    asm = asm + tab + "stp x20, x21, [sp, #160]" + nl
    asm = asm + tab + "stp x22, x23, [sp, #176]" + nl
    asm = asm + tab + "stp x24, x25, [sp, #192]" + nl
    asm = asm + tab + "stp x26, x27, [sp, #208]" + nl
    asm = asm + tab + "stp x28, x29, [sp, #224]" + nl
    asm = asm + tab + "str x30, [sp, #240]" + nl
    asm = asm + tab + "mrs x0, ELR_EL1" + nl
    asm = asm + tab + "str x0, [sp, #248]" + nl
    # Read ESR_EL1 to get exception syndrome
    asm = asm + tab + "mrs x0, ESR_EL1" + nl
    # Extract EC field (bits 31:26) to verify SVC
    asm = asm + tab + "lsr x1, x0, #26" + nl
    asm = asm + tab + "cmp x1, #0x15" + nl
    asm = asm + tab + "b.ne .Lsvc_not_svc" + nl
    # x8 holds syscall number (AArch64 calling convention)
    asm = asm + tab + "ldr x0, [sp, #64]" + nl
    asm = asm + tab + "bl syscall_dispatch" + nl
    # Store return value
    asm = asm + tab + "str x0, [sp, #0]" + nl
    asm = asm + ".Lsvc_not_svc:" + nl
    # Restore registers
    asm = asm + tab + "ldr x0, [sp, #248]" + nl
    asm = asm + tab + "msr ELR_EL1, x0" + nl
    asm = asm + tab + "ldp x0, x1, [sp, #0]" + nl
    asm = asm + tab + "ldp x2, x3, [sp, #16]" + nl
    asm = asm + tab + "ldp x4, x5, [sp, #32]" + nl
    asm = asm + tab + "ldp x6, x7, [sp, #48]" + nl
    asm = asm + tab + "ldp x8, x9, [sp, #64]" + nl
    asm = asm + tab + "ldp x10, x11, [sp, #80]" + nl
    asm = asm + tab + "ldp x12, x13, [sp, #96]" + nl
    asm = asm + tab + "ldp x14, x15, [sp, #112]" + nl
    asm = asm + tab + "ldp x16, x17, [sp, #128]" + nl
    asm = asm + tab + "ldp x18, x19, [sp, #144]" + nl
    asm = asm + tab + "ldp x20, x21, [sp, #160]" + nl
    asm = asm + tab + "ldp x22, x23, [sp, #176]" + nl
    asm = asm + tab + "ldp x24, x25, [sp, #192]" + nl
    asm = asm + tab + "ldp x26, x27, [sp, #208]" + nl
    asm = asm + tab + "ldp x28, x29, [sp, #224]" + nl
    asm = asm + tab + "ldr x30, [sp, #240]" + nl
    asm = asm + tab + "add sp, sp, #264" + nl
    asm = asm + tab + "eret" + nl
    return asm
end

proc emit_ecall_entry_riscv64():
    # riscv64 assembly for ECALL trap entry (M-mode trap handler)
    let nl = chr(10)
    let tab = chr(9)
    let asm = ""
    asm = asm + ".global ecall_entry" + nl
    asm = asm + ".type ecall_entry, @function" + nl
    asm = asm + "ecall_entry:" + nl
    # Save registers to trap frame (allocate 256 bytes on stack)
    asm = asm + tab + "addi sp, sp, -256" + nl
    asm = asm + tab + "sd ra, 0(sp)" + nl
    asm = asm + tab + "sd t0, 8(sp)" + nl
    asm = asm + tab + "sd t1, 16(sp)" + nl
    asm = asm + tab + "sd t2, 24(sp)" + nl
    asm = asm + tab + "sd a0, 32(sp)" + nl
    asm = asm + tab + "sd a1, 40(sp)" + nl
    asm = asm + tab + "sd a2, 48(sp)" + nl
    asm = asm + tab + "sd a3, 56(sp)" + nl
    asm = asm + tab + "sd a4, 64(sp)" + nl
    asm = asm + tab + "sd a5, 72(sp)" + nl
    asm = asm + tab + "sd a6, 80(sp)" + nl
    asm = asm + tab + "sd a7, 88(sp)" + nl
    asm = asm + tab + "sd t3, 96(sp)" + nl
    asm = asm + tab + "sd t4, 104(sp)" + nl
    asm = asm + tab + "sd t5, 112(sp)" + nl
    asm = asm + tab + "sd t6, 120(sp)" + nl
    asm = asm + tab + "sd s0, 128(sp)" + nl
    asm = asm + tab + "sd s1, 136(sp)" + nl
    asm = asm + tab + "sd s2, 144(sp)" + nl
    asm = asm + tab + "sd s3, 152(sp)" + nl
    asm = asm + tab + "sd s4, 160(sp)" + nl
    asm = asm + tab + "sd s5, 168(sp)" + nl
    asm = asm + tab + "sd s6, 176(sp)" + nl
    asm = asm + tab + "sd s7, 184(sp)" + nl
    asm = asm + tab + "sd s8, 192(sp)" + nl
    asm = asm + tab + "sd s9, 200(sp)" + nl
    asm = asm + tab + "sd s10, 208(sp)" + nl
    asm = asm + tab + "sd s11, 216(sp)" + nl
    # Save MEPC
    asm = asm + tab + "csrr t0, mepc" + nl
    asm = asm + tab + "sd t0, 224(sp)" + nl
    # Read mcause to determine trap type
    asm = asm + tab + "csrr t0, mcause" + nl
    # Check for environment call from U-mode (cause=8)
    asm = asm + tab + "li t1, 8" + nl
    asm = asm + tab + "beq t0, t1, .Lecall_dispatch" + nl
    # Check for environment call from M-mode (cause=11)
    asm = asm + tab + "li t1, 11" + nl
    asm = asm + tab + "beq t0, t1, .Lecall_dispatch" + nl
    # Not an ecall, jump to restore
    asm = asm + tab + "j .Lecall_restore" + nl
    asm = asm + ".Lecall_dispatch:" + nl
    # a7 holds syscall number (RISC-V convention), pass as first arg (a0)
    asm = asm + tab + "mv a0, a7" + nl
    asm = asm + tab + "call syscall_dispatch" + nl
    # Store return value back to a0 slot in trap frame
    asm = asm + tab + "sd a0, 32(sp)" + nl
    # Advance MEPC past ecall instruction (+4 bytes)
    asm = asm + tab + "ld t0, 224(sp)" + nl
    asm = asm + tab + "addi t0, t0, 4" + nl
    asm = asm + tab + "sd t0, 224(sp)" + nl
    asm = asm + ".Lecall_restore:" + nl
    # Restore MEPC
    asm = asm + tab + "ld t0, 224(sp)" + nl
    asm = asm + tab + "csrw mepc, t0" + nl
    # Restore registers
    asm = asm + tab + "ld ra, 0(sp)" + nl
    asm = asm + tab + "ld t0, 8(sp)" + nl
    asm = asm + tab + "ld t1, 16(sp)" + nl
    asm = asm + tab + "ld t2, 24(sp)" + nl
    asm = asm + tab + "ld a0, 32(sp)" + nl
    asm = asm + tab + "ld a1, 40(sp)" + nl
    asm = asm + tab + "ld a2, 48(sp)" + nl
    asm = asm + tab + "ld a3, 56(sp)" + nl
    asm = asm + tab + "ld a4, 64(sp)" + nl
    asm = asm + tab + "ld a5, 72(sp)" + nl
    asm = asm + tab + "ld a6, 80(sp)" + nl
    asm = asm + tab + "ld a7, 88(sp)" + nl
    asm = asm + tab + "ld t3, 96(sp)" + nl
    asm = asm + tab + "ld t4, 104(sp)" + nl
    asm = asm + tab + "ld t5, 112(sp)" + nl
    asm = asm + tab + "ld t6, 120(sp)" + nl
    asm = asm + tab + "ld s0, 128(sp)" + nl
    asm = asm + tab + "ld s1, 136(sp)" + nl
    asm = asm + tab + "ld s2, 144(sp)" + nl
    asm = asm + tab + "ld s3, 152(sp)" + nl
    asm = asm + tab + "ld s4, 160(sp)" + nl
    asm = asm + tab + "ld s5, 168(sp)" + nl
    asm = asm + tab + "ld s6, 176(sp)" + nl
    asm = asm + tab + "ld s7, 184(sp)" + nl
    asm = asm + tab + "ld s8, 192(sp)" + nl
    asm = asm + tab + "ld s9, 200(sp)" + nl
    asm = asm + tab + "ld s10, 208(sp)" + nl
    asm = asm + tab + "ld s11, 216(sp)" + nl
    asm = asm + tab + "addi sp, sp, 256" + nl
    asm = asm + tab + "mret" + nl
    return asm
end
gc_disable()

# sage — Minimal SageOS Shell
# Provides a terminal-based interface for user interaction.


proc print_prompt():
    set_color(LIGHT_CYAN, BLACK)
    print_str("sage@os")
    set_color(WHITE, BLACK)
    print_str(":")
    set_color(LIGHT_BLUE, BLACK)
    print_str("~")
    set_color(WHITE, BLACK)
    print_str("$ ")
end

proc handle_command(cmd):
    if cmd == "":
        return
    end
    
    if cmd == "help":
        print_line("Available commands:")
        print_line("  help     - Show this help message")
        print_line("  ls       - List files (simulated)")
        print_line("  clear    - Clear the screen")
        print_line("  version  - Show SageOS version")
        print_line("  exit     - Exit the shell")
        return
    end
    
    if cmd == "ls":
        print_line("bin/  etc/  home/  kernel.bin")
        return
    end
    
    if cmd == "clear":
        clear_screen(BLACK)
        return
    end
    
    if cmd == "version":
        print_line("SageOS v0.1.0 (x86_64)")
        return
    end
    
    if cmd == "exit":
        print_line("Shutting down...")
        sys_exit(0)
        return
    end
    
    print_line("sh: command not found: " + cmd)
end

proc sh_main():
    print_line("SageOS Shell v0.1.0")
    print_line("Type 'help' for available commands.")
    print_line("")
    
    let cmd_buffer = ""
    while true:
        print_prompt()
        
        # Read line from keyboard
        cmd_buffer = ""
        let reading = true
        while reading:
            let ch = get_char()
            if ch != nil:
                if ch == chr(10): # Enter
                    newline()
                    reading = false
                elif ch == chr(8): # Backspace
                    if len(cmd_buffer) > 0:
                        # Simple backspace: move cursor back, print space, move back
                        let pos = get_cursor()
                        if pos["x"] > 0:
                            set_cursor(pos["x"] - 1, pos["y"])
                            print_str(" ")
                            set_cursor(pos["x"] - 1, pos["y"])
                            # Truncate cmd_buffer
                            let new_cmd = ""
                            for i in range(len(cmd_buffer) - 1):
                                new_cmd = new_cmd + cmd_buffer[i]
                            end
                            cmd_buffer = new_cmd
                        end
                    end
                else:
                    cmd_buffer = cmd_buffer + ch
                    print_str(ch)
                end
            end
            # Yield to other tasks if multi-tasking was enabled
            builtin_yield(nil)
        end
        
        handle_command(cmd_buffer)
    end
end
gc_disable()

# kmain.sage — Kernel entry point for SageOS
# Initializes all subsystems and provides panic/halt primitives.


let KERNEL_NAME = "SageOS"
let KERNEL_VERSION = "0.1.0"

proc kernel_version():
    return KERNEL_NAME + " " + KERNEL_VERSION
end

proc create_kernel(name, version):
    let cfg = {}
    cfg["name"] = name
    cfg["version"] = version
    cfg["console_ready"] = false
    cfg["memory_ready"] = false
    cfg["interrupts_ready"] = false
    cfg["keyboard_ready"] = false
    cfg["timer_ready"] = false
    cfg["syscalls_ready"] = false
    cfg["vmm_ready"] = false
    return cfg
end

proc panic(msg):
    let nl = chr(10)
    let line = "==============================="
    set_color(WHITE, RED)
    print_line("")
    print_line(line)
    print_line("  KERNEL PANIC")
    print_line(line)
    print_line("")
    print_line("  " + msg)
    print_line("")
    print_line(line)
    halt()
end

proc halt():
    # Halt the CPU. In compiled bare-metal mode, this emits a HLT loop.
    # In interpreter mode, it busy-waits as a simulation fallback.
    while true:
        # On real hardware, the compiler emits: cli; hlt; jmp halt
        # In interpreted mode, this is a safe infinite loop.
        let dummy = 0
    end
end

# Generate x86_64 assembly for a proper hardware halt loop
proc emit_halt_asm():
    return ".Lhalt:" + chr(10) + "    cli" + chr(10) + "    hlt" + chr(10) + "    jmp .Lhalt" + chr(10)
end

proc init_console(boot_info):
    init_vga()
    set_color(LIGHT_GREEN, BLACK)
    clear_screen(BLACK)
    print_line(kernel_version() + " booting...")
    print_line("")
    if boot_info != nil:
        if dict_has(boot_info, "framebuffer"):
            let fb = boot_info["framebuffer"]
            init_framebuffer(fb["addr"], fb["width"], fb["height"], fb["pitch"], fb["bpp"])
        end
    end
    return true
end

proc init_memory(boot_info):
    let mem_map = nil
    let arch = "x86_64"
    if boot_info != nil:
        if dict_has(boot_info, "memory_map"):
            mem_map = boot_info["memory_map"]
        end
        if dict_has(boot_info, "arch"):
            arch = boot_info["arch"]
        end
    end
    if mem_map == nil:
        mem_map = []
    end
    init(mem_map)
    vmm_init(arch)
    let total_mb = total_memory() / 1048576
    print_line("  Memory: " + str(total_mb) + " MB total")
    return true
end

proc init_interrupts():
    init()
    print_line("  Interrupts: IDT installed")
    return true
end

proc init_keyboard():
    init()
    print_line("  Keyboard: PS/2 driver ready")
    return true
end

proc init_timer(freq_hz):
    init(freq_hz)
    print_line("  Timer: PIT at " + str(freq_hz) + " Hz")
    return true
end

proc kmain(boot_info):
    if boot_info == nil:
        boot_info = {}
    end
    let kernel = create_kernel(KERNEL_NAME, KERNEL_VERSION)

    # Phase 1: Console (needed for all output)
    kernel["console_ready"] = init_console(boot_info)

    print_line("[1/6] Console initialized")

    # Phase 2: Physical + Virtual memory
    kernel["memory_ready"] = init_memory(boot_info)
    kernel["vmm_ready"] = true
    print_line("[2/6] Memory manager initialized")

    # Phase 3: Interrupts / syscall table
    kernel["interrupts_ready"] = init_interrupts()
    kernel["syscalls_ready"] = true
    print_line("[3/6] Interrupts initialized")

    # Phase 4: Keyboard
    kernel["keyboard_ready"] = init_keyboard()
    print_line("[4/6] Keyboard initialized")

    # Phase 5: Timer
    kernel["timer_ready"] = init_timer(100)
    print_line("[5/6] Timer initialized")

    # Phase 6: Ready
    print_line("[6/6] All subsystems ready")
    print_line("")
    set_color(WHITE, BLACK)
    print_line(kernel_version() + " is running.")
    print_line("")

    # Launch Shell
    sh_main()

    return kernel
end
