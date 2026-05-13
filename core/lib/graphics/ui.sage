gc_disable()
# -----------------------------------------
# ui.sage - Immediate-Mode GPU UI Widget Library
# Provides windows, panels, buttons, labels, menus,
# scrollbars, checkboxes, sliders, and text inputs
# Works with both Vulkan and OpenGL backends
# -----------------------------------------

import gpu

# ============================================================================
# Theme (colors as [r, g, b, a] arrays)
# ============================================================================
proc ui_default_theme():
    let t = {}
    t["bg"] = [0.15, 0.15, 0.18, 0.95]
    t["bg_hover"] = [0.22, 0.22, 0.26, 1.0]
    t["bg_active"] = [0.28, 0.28, 0.34, 1.0]
    t["panel"] = [0.12, 0.12, 0.14, 0.92]
    t["border"] = [0.35, 0.35, 0.40, 1.0]
    t["title_bg"] = [0.18, 0.30, 0.55, 1.0]
    t["text"] = [0.92, 0.92, 0.94, 1.0]
    t["text_dim"] = [0.55, 0.55, 0.60, 1.0]
    t["accent"] = [0.35, 0.55, 0.95, 1.0]
    t["accent_hover"] = [0.45, 0.65, 1.0, 1.0]
    t["check"] = [0.30, 0.75, 0.40, 1.0]
    t["slider_bg"] = [0.10, 0.10, 0.12, 1.0]
    t["slider_fill"] = [0.35, 0.55, 0.95, 1.0]
    t["slider_knob"] = [0.85, 0.85, 0.90, 1.0]
    t["input_bg"] = [0.08, 0.08, 0.10, 1.0]
    t["input_cursor"] = [0.90, 0.90, 0.95, 1.0]
    t["scroll_bg"] = [0.10, 0.10, 0.12, 0.8]
    t["scroll_thumb"] = [0.40, 0.40, 0.45, 0.9]
    t["menu_bg"] = [0.14, 0.14, 0.17, 0.98]
    t["menu_hover"] = [0.25, 0.40, 0.70, 1.0]
    t["font_size"] = 16
    t["padding"] = 6
    t["border_width"] = 1
    t["title_height"] = 24
    t["scrollbar_width"] = 12
    t["slider_height"] = 20
    t["checkbox_size"] = 16
    t["input_height"] = 24
    return t

# ============================================================================
# UI Context (immediate-mode state)
# ============================================================================
proc ui_create():
    let ctx = {}
    ctx["theme"] = ui_default_theme()
    ctx["hot"] = ""
    ctx["active"] = ""
    ctx["mouse_x"] = 0
    ctx["mouse_y"] = 0
    ctx["mouse_down"] = false
    ctx["mouse_clicked"] = false
    ctx["mouse_released"] = false
    ctx["prev_mouse_down"] = false
    ctx["cursor_x"] = 0
    ctx["cursor_y"] = 0
    ctx["draw_list"] = []
    ctx["id_stack"] = []
    ctx["next_id"] = 0
    ctx["scroll_offsets"] = {}
    ctx["text_buffers"] = {}
    ctx["open_menus"] = {}
    ctx["drag_data"] = {}
    return ctx

# ============================================================================
# Input update (call once per frame before any widgets)
# ============================================================================
proc ui_begin_frame(ctx):
    let pos = gpu.mouse_pos()
    ctx["mouse_x"] = pos["x"]
    ctx["mouse_y"] = pos["y"]
    let down = gpu.mouse_button(0)
    ctx["prev_mouse_down"] = ctx["mouse_down"]
    ctx["mouse_down"] = down
    ctx["mouse_clicked"] = down and not ctx["prev_mouse_down"]
    ctx["mouse_released"] = not down and ctx["prev_mouse_down"]
    ctx["draw_list"] = []
    ctx["cursor_x"] = 0
    ctx["cursor_y"] = 0
    ctx["hot"] = ""
    ctx["next_id"] = 0

proc ui_end_frame(ctx):
    if not ctx["mouse_down"]:
        ctx["active"] = ""

# ============================================================================
# Hit testing
# ============================================================================
proc ui_point_in_rect(ctx, x, y, w, h):
    let mx = ctx["mouse_x"]
    let my = ctx["mouse_y"]
    if mx >= x and mx < x + w and my >= y and my < y + h:
        return true
    return false

proc ui_make_id(ctx, label):
    ctx["next_id"] = ctx["next_id"] + 1
    return label + "_" + str(ctx["next_id"])

# ============================================================================
# Draw primitives (accumulated into draw_list for batch rendering)
# ============================================================================
proc ui_draw_rect(ctx, x, y, w, h, color):
    let cmd = {}
    cmd["type"] = "rect"
    cmd["x"] = x
    cmd["y"] = y
    cmd["w"] = w
    cmd["h"] = h
    cmd["color"] = color
    push(ctx["draw_list"], cmd)

proc ui_draw_border(ctx, x, y, w, h, color, width):
    ui_draw_rect(ctx, x, y, w, width, color)
    ui_draw_rect(ctx, x, y + h - width, w, width, color)
    ui_draw_rect(ctx, x, y, width, h, color)
    ui_draw_rect(ctx, x + w - width, y, width, h, color)

proc ui_draw_text(ctx, x, y, text, color):
    let cmd = {}
    cmd["type"] = "text"
    cmd["x"] = x
    cmd["y"] = y
    cmd["text"] = text
    cmd["color"] = color
    push(ctx["draw_list"], cmd)

# ============================================================================
# Label — static text display
# ============================================================================
proc ui_label(ctx, x, y, text):
    let t = ctx["theme"]
    ui_draw_text(ctx, x, y, text, t["text"])

proc ui_label_colored(ctx, x, y, text, color):
    ui_draw_text(ctx, x, y, text, color)

# ============================================================================
# Button — clickable with hover/press states
# Returns true if clicked
# ============================================================================
proc ui_button(ctx, x, y, w, h, label):
    let t = ctx["theme"]
    let id = ui_make_id(ctx, label)
    let hovered = ui_point_in_rect(ctx, x, y, w, h)
    let clicked = false

    if hovered:
        ctx["hot"] = id
        if ctx["mouse_clicked"]:
            ctx["active"] = id
        if ctx["mouse_released"] and ctx["active"] == id:
            clicked = true

    let bg = t["bg"]
    if ctx["active"] == id:
        bg = t["bg_active"]
    if hovered:
        if ctx["active"] == id:
            bg = t["bg_active"]
        if ctx["active"] != id:
            bg = t["bg_hover"]

    ui_draw_rect(ctx, x, y, w, h, bg)
    ui_draw_border(ctx, x, y, w, h, t["border"], t["border_width"])

    let tx = x + t["padding"]
    let ty = y + (h - t["font_size"]) / 2
    ui_draw_text(ctx, tx, ty, label, t["text"])

    return clicked

# ============================================================================
# Panel — rectangular container with optional title and border
# ============================================================================
proc ui_panel(ctx, x, y, w, h, title):
    let t = ctx["theme"]
    ui_draw_rect(ctx, x, y, w, h, t["panel"])
    ui_draw_border(ctx, x, y, w, h, t["border"], t["border_width"])

    if title != "":
        let th = t["title_height"]
        ui_draw_rect(ctx, x, y, w, th, t["title_bg"])
        let tx = x + t["padding"]
        let ty = y + (th - t["font_size"]) / 2
        ui_draw_text(ctx, tx, ty, title, t["text"])

# ============================================================================
# Window — draggable panel with title bar
# Returns dict with content area {x, y, w, h}
# ============================================================================
proc ui_window(ctx, x, y, w, h, title):
    let t = ctx["theme"]
    let th = t["title_height"]
    let id = ui_make_id(ctx, "win_" + title)

    # Title bar drag
    let title_hovered = ui_point_in_rect(ctx, x, y, w, th)
    if title_hovered and ctx["mouse_clicked"]:
        ctx["active"] = id
        let dd = {}
        dd["ox"] = ctx["mouse_x"] - x
        dd["oy"] = ctx["mouse_y"] - y
        ctx["drag_data"][id] = dd

    if ctx["active"] == id and ctx["mouse_down"]:
        if dict_has(ctx["drag_data"], id):
            let dd = ctx["drag_data"][id]
            x = ctx["mouse_x"] - dd["ox"]
            y = ctx["mouse_y"] - dd["oy"]

    ui_panel(ctx, x, y, w, h, title)

    let content = {}
    content["x"] = x + t["padding"]
    content["y"] = y + th + t["padding"]
    content["w"] = w - t["padding"] * 2
    content["h"] = h - th - t["padding"] * 2
    return content

# ============================================================================
# Checkbox — toggle with label
# Returns new checked state
# ============================================================================
proc ui_checkbox(ctx, x, y, label, checked):
    let t = ctx["theme"]
    let sz = t["checkbox_size"]
    let id = ui_make_id(ctx, "chk_" + label)
    let hovered = ui_point_in_rect(ctx, x, y, sz, sz)

    if hovered and ctx["mouse_clicked"]:
        checked = not checked

    let bg = t["bg"]
    if hovered:
        bg = t["bg_hover"]

    ui_draw_rect(ctx, x, y, sz, sz, bg)
    ui_draw_border(ctx, x, y, sz, sz, t["border"], t["border_width"])

    if checked:
        let inset = 3
        ui_draw_rect(ctx, x + inset, y + inset, sz - inset * 2, sz - inset * 2, t["check"])

    let tx = x + sz + t["padding"]
    let ty = y + (sz - t["font_size"]) / 2
    ui_draw_text(ctx, tx, ty, label, t["text"])

    return checked

# ============================================================================
# Slider — horizontal value slider
# Returns new value (0.0 to 1.0)
# ============================================================================
proc ui_slider(ctx, x, y, w, label, value):
    let t = ctx["theme"]
    let sh = t["slider_height"]
    let id = ui_make_id(ctx, "sld_" + label)
    let hovered = ui_point_in_rect(ctx, x, y, w, sh)

    if hovered and ctx["mouse_clicked"]:
        ctx["active"] = id

    if ctx["active"] == id and ctx["mouse_down"]:
        let rel = (ctx["mouse_x"] - x) / w
        if rel < 0:
            rel = 0
        if rel > 1:
            rel = 1
        value = rel

    # Background
    ui_draw_rect(ctx, x, y, w, sh, t["slider_bg"])

    # Fill
    let fill_w = w * value
    if fill_w > 0:
        ui_draw_rect(ctx, x, y, fill_w, sh, t["slider_fill"])

    # Knob
    let knob_x = x + fill_w - 4
    if knob_x < x:
        knob_x = x
    ui_draw_rect(ctx, knob_x, y, 8, sh, t["slider_knob"])

    # Label
    let tx = x
    let ty = y + sh + 2
    ui_draw_text(ctx, tx, ty, label + ": " + str(value), t["text_dim"])

    return value

# ============================================================================
# Scrollbar — vertical scrollbar
# Returns new scroll position (0.0 to 1.0)
# ============================================================================
proc ui_scrollbar_v(ctx, x, y, h, content_h, scroll):
    let t = ctx["theme"]
    let sw = t["scrollbar_width"]
    let id = ui_make_id(ctx, "scr")

    if content_h <= h:
        return 0

    let thumb_h = (h * h) / content_h
    if thumb_h < 20:
        thumb_h = 20
    let track_h = h - thumb_h
    let thumb_y = y + track_h * scroll

    ui_draw_rect(ctx, x, y, sw, h, t["scroll_bg"])

    let thumb_hovered = ui_point_in_rect(ctx, x, thumb_y, sw, thumb_h)

    if thumb_hovered and ctx["mouse_clicked"]:
        ctx["active"] = id

    if ctx["active"] == id and ctx["mouse_down"]:
        let rel = (ctx["mouse_y"] - y - thumb_h / 2) / track_h
        if rel < 0:
            rel = 0
        if rel > 1:
            rel = 1
        scroll = rel

    let thumb_color = t["scroll_thumb"]
    if thumb_hovered or ctx["active"] == id:
        thumb_color = t["accent"]

    ui_draw_rect(ctx, x, thumb_y, sw, thumb_h, thumb_color)

    return scroll

# ============================================================================
# Menu — dropdown menu with items
# Returns index of clicked item or -1
# ============================================================================
proc ui_menu_button(ctx, x, y, w, h, label, items):
    let t = ctx["theme"]
    let id = ui_make_id(ctx, "menu_" + label)
    let is_open = false
    if dict_has(ctx["open_menus"], id):
        is_open = ctx["open_menus"][id]

    # Menu button
    let btn_clicked = ui_button(ctx, x, y, w, h, label)
    if btn_clicked:
        is_open = not is_open
        ctx["open_menus"][id] = is_open

    let result = -1

    if is_open:
        let item_h = h
        let menu_h = len(items) * item_h
        let menu_y = y + h

        ui_draw_rect(ctx, x, menu_y, w, menu_h, t["menu_bg"])
        ui_draw_border(ctx, x, menu_y, w, menu_h, t["border"], t["border_width"])

        let i = 0
        while i < len(items):
            let iy = menu_y + i * item_h
            let item_hovered = ui_point_in_rect(ctx, x, iy, w, item_h)

            if item_hovered:
                ui_draw_rect(ctx, x, iy, w, item_h, t["menu_hover"])
                if ctx["mouse_clicked"]:
                    result = i
                    ctx["open_menus"][id] = false

            let tx = x + t["padding"]
            let ty = iy + (item_h - t["font_size"]) / 2
            ui_draw_text(ctx, tx, ty, items[i], t["text"])

            i = i + 1

    return result

# ============================================================================
# Text Input — single-line editable text field
# Returns current text value
# ============================================================================
proc ui_text_input(ctx, x, y, w, label, text):
    let t = ctx["theme"]
    let ih = t["input_height"]
    let id = ui_make_id(ctx, "inp_" + label)
    let hovered = ui_point_in_rect(ctx, x, y, w, ih)
    let is_active = ctx["active"] == id

    if hovered and ctx["mouse_clicked"]:
        ctx["active"] = id

    # Background
    let bg = t["input_bg"]
    if is_active:
        bg = t["bg"]

    ui_draw_rect(ctx, x, y, w, ih, bg)
    ui_draw_border(ctx, x, y, w, ih, t["border"], t["border_width"])

    if is_active:
        ui_draw_border(ctx, x, y, w, ih, t["accent"], 2)

    # Text content
    let display = text
    if display == "" and not is_active:
        display = label
        ui_draw_text(ctx, x + t["padding"], y + (ih - t["font_size"]) / 2, display, t["text_dim"])
    if display != "" or is_active:
        ui_draw_text(ctx, x + t["padding"], y + (ih - t["font_size"]) / 2, display, t["text"])

    # Cursor blink (simple — always show when active)
    if is_active:
        let cursor_x = x + t["padding"] + len(text) * 8
        ui_draw_rect(ctx, cursor_x, y + 3, 2, ih - 6, t["input_cursor"])

    # Handle keyboard input when active
    if is_active:
        if gpu.key_just_pressed(gpu.KEY_BACKSPACE):
            if len(text) > 0:
                text = text[0:len(text) - 1]
        # Check for printable text input
        if gpu.text_input_available():
            let ch = gpu.text_input_read()
            text = text + ch

    return text

# ============================================================================
# Separator — horizontal line
# ============================================================================
proc ui_separator(ctx, x, y, w):
    let t = ctx["theme"]
    ui_draw_rect(ctx, x, y, w, 1, t["border"])

# ============================================================================
# Progress bar
# ============================================================================
proc ui_progress(ctx, x, y, w, h, value, label):
    let t = ctx["theme"]
    ui_draw_rect(ctx, x, y, w, h, t["slider_bg"])

    let fill_w = w * value
    if fill_w > 0:
        ui_draw_rect(ctx, x, y, fill_w, h, t["accent"])

    if label != "":
        let tx = x + (w - len(label) * 8) / 2
        let ty = y + (h - t["font_size"]) / 2
        ui_draw_text(ctx, tx, ty, label, t["text"])

# ============================================================================
# Tooltip — popup text near cursor
# ============================================================================
proc ui_tooltip(ctx, text):
    let t = ctx["theme"]
    let mx = ctx["mouse_x"] + 12
    let my = ctx["mouse_y"] + 12
    let tw = len(text) * 8 + t["padding"] * 2
    let th = t["font_size"] + t["padding"] * 2

    ui_draw_rect(ctx, mx, my, tw, th, t["menu_bg"])
    ui_draw_border(ctx, mx, my, tw, th, t["border"], t["border_width"])
    ui_draw_text(ctx, mx + t["padding"], my + t["padding"], text, t["text"])

# ============================================================================
# Render all accumulated draw commands
# (Call at end of frame — this is where GPU commands are issued)
# ============================================================================
proc ui_render(ctx, cmd_buf, font):
    let dl = ctx["draw_list"]
    let i = 0
    while i < len(dl):
        let c = dl[i]
        if c["type"] == "rect":
            # Emit a colored quad via push constants or vertex buffer
            # This uses the GPU command recording API
            # In practice, batch all rects into a single vertex buffer
            let x = c["x"]
            let y = c["y"]
            let w = c["w"]
            let h = c["h"]
            let color = c["color"]
            # Push constants: [x, y, w, h, r, g, b, a]
            let data = [x, y, w, h, color[0], color[1], color[2], color[3]]
            # Actual rendering depends on pipeline setup
            # gpu.cmd_push_constants(cmd_buf, layout, gpu.STAGE_VERTEX, data)
            # gpu.cmd_draw(cmd_buf, 6, 1, 0, 0)  # 2 triangles = 1 quad
        if c["type"] == "text":
            if font != nil:
                let verts = gpu.font_text_verts(font, c["text"])
                # Render text vertices at c["x"], c["y"]
        i = i + 1

# ============================================================================
# Convenience: get draw list for custom rendering
# ============================================================================
proc ui_get_draw_list(ctx):
    return ctx["draw_list"]

proc ui_draw_count(ctx):
    return len(ctx["draw_list"])
