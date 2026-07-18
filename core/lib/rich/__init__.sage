# rich.sage — Rich TUI library for SageLang
# Provides colors, styles, panels, tables, progress, and live rendering

import sys

proc RESET(): "\x1b[0m"
proc BOLD(): "\x1b[1m"
proc DIM(): "\x1b[2m"
proc ITALIC(): "\x1b[3m"
proc UNDERLINE(): "\x1b[4m"
proc BLINK(): "\x1b[5m"
proc REVERSE(): "\x1b[7m"
proc HIDDEN(): "\x1b[8m"
proc STRIKETHROUGH(): "\x1b[9m"

proc RED(): "\x1b[31m"
proc GREEN(): "\x1b[32m"
proc YELLOW(): "\x1b[33m"
proc BLUE(): "\x1b[34m"
proc MAGENTA(): "\x1b[35m"
proc CYAN(): "\x1b[36m"
proc GRAY(): "\x1b[90m"
proc WHITE(): "\x1b[97m"

proc BG_RED(): "\x1b[41m"
proc BG_GREEN(): "\x1b[42m"
proc BG_YELLOW(): "\x1b[43m"
proc BG_BLUE(): "\x1b[44m"
proc BG_MAGENTA(): "\x1b[45m"
proc BG_CYAN(): "\x1b[46m"
proc BG_GRAY(): "\x1b[100m"
proc BG_WHITE(): "\x1b[107m"

proc style(text, style):
    return style + text + RESET()

proc color(text, fg):
    return fg + text + RESET()

proc bg(text, bg):
    return bg + text + RESET()

proc bold(text):
    return BOLD() + text + RESET()

proc dim(text):
    return DIM() + text + RESET()

proc italic(text):
    return ITALIC() + text + RESET()

proc underline(text):
    return UNDERLINE() + text + RESET()

proc red(text):
    return RED() + text + RESET()

proc green(text):
    return GREEN() + text + RESET()

proc yellow(text):
    return YELLOW() + text + RESET()

proc blue(text):
    return BLUE() + text + RESET()

proc magenta(text):
    return MAGENTA() + text + RESET()

proc cyan(text):
    return CYAN() + text + RESET()

proc gray(text):
    return GRAY() + text + RESET()

proc white(text):
    return WHITE() + text + RESET()

proc on_red(text):
    return BG_RED() + text + RESET()

proc on_green(text):
    return BG_GREEN() + text + RESET()

proc on_yellow(text):
    return BG_YELLOW() + text + RESET()

proc on_blue(text):
    return BG_BLUE() + text + RESET()

proc on_magenta(text):
    return BG_MAGENTA() + text + RESET()

proc on_cyan(text):
    return BG_CYAN() + text + RESET()

proc on_gray(text):
    return BG_GRAY() + text + RESET()

proc on_white(text):
    return BG_WHITE() + text + RESET()

# ─── Box Drawing ─────────────────────────────────────────────────────────
let BOX_LIGHT = {"tl": "┌", "tr": "┐", "bl": "└", "br": "┘", "h": "─", "v": "│", "ml": "├", "mr": "┤", "mt": "┬", "mb": "┴", "c": "┼"}
let BOX_HEAVY = {"tl": "┏", "tr": "┓", "bl": "┗", "br": "┛", "h": "━", "v": "┃", "ml": "┣", "mr": "┫", "mt": "┳", "mb": "┻", "c": "╋"}
let BOX_DOUBLE = {"tl": "╔", "tr": "╗", "bl": "╚", "br": "╝", "h": "═", "v": "║", "ml": "╠", "mr": "╣", "mt": "╦", "mb": "╩", "c": "╬"}
let BOX_ROUNDED = {"tl": "╭", "tr": "╮", "bl": "╰", "br": "╯", "h": "─", "v": "│", "ml": "├", "mr": "┤", "mt": "┬", "mb": "┴", "c": "┼"}

proc panel(text, border_style, border_color, title, title_align, padding):
    var style = BOX_ROUNDED
    if border_style == "light":
        style = BOX_LIGHT
    elif border_style == "heavy":
        style = BOX_HEAVY
    elif border_style == "double":
        style = BOX_DOUBLE
    let lines = split(text, "\n")
    let max_w = 0
    for l in lines:
        if len(l) > max_w:
            max_w = len(l)
    let inner_w = max_w + padding * 2
    let w = inner_w + 2
    let h = style.h
    let v = style.v
    let tl = style.tl
    let tr = style.tr
    let bl = style.bl
    let br = style.br
    var result = ""
    if title != "":
        let t = " " + title + " "
        let title_len = len(t)
        let left_w = (w - 2 - title_len) / 2
        let right_w = w - 2 - title_len - left_w
        result = result + style(tl + str_repeat(style.h, left_w) + t + str_repeat(style.h, right_w) + tr, border_color) + "\n"
    else:
        result = result + style(tl + str_repeat(style.h, w - 2) + tr, border_color) + "\n"
    for l in lines:
        let pad = w - 2 - len(l)
        result = result + style(v + " " + l + str_repeat(" ", pad) + " " + v, border_color) + "\n"
    result = result + style(bl + str_repeat(style.h, w - 2) + br, border_color)
    return result

proc str_repeat(s, n):
    var r = ""
    for i in range(n):
        r = r + s
    return r

# ─── Tables ──────────────────────────────────────────────────────────────
proc table(headers, rows, border):
    let cols = len(headers)
    let widths = []
    for i in range(len(headers)):
        widths[i] = len(headers[i])
    for row in rows:
        for i in range(len(row)):
            if len(str(row[i])) > widths[i]:
                widths[i] = len(str(row[i]))
    let h = "─"
    let v = "│"
    let tl = "┌"
    let tr = "┐"
    let bl = "└"
    let br = "┘"
    let ml = "├"
    let mr = "┤"
    let mt = "┬"
    let mb = "┴"
    let c = "┼"
    var result = ""
    if border:
        result = result + "┌"
        for i in range(len(widths)):
            result = result + str_repeat("─", widths[i] + 2)
            if i < len(widths) - 1:
                result = result + "┬"
        result = result + "┐\n"
    result = result + "│"
    for i in range(len(headers)):
        let pad = widths[i] - len(headers[i])
        result = result + " " + headers[i] + str_repeat(" ", pad) + " │"
    result = result + "\n"
    if border:
        result = result + "├"
        for i in range(len(widths)):
            result = result + str_repeat("─", widths[i] + 2)
            if i < len(widths) - 1:
                result = result + "┼"
        result = result + "┤\n"
    for ri in range(len(rows)):
        result = result + "│"
        for i in range(len(rows[ri])):
            let cell = str(rows[ri][i])
            let pad = widths[i] - len(cell)
            result = result + " " + cell + str_repeat(" ", pad) + " │"
        result = result + "\n"
    if border:
        result = result + "└"
        for i in range(len(widths)):
            result = result + str_repeat("─", widths[i] + 2)
            if i < len(widths) - 1:
                result = result + "┴"
        result = result + "┘"
    return result

# ─── Progress / Spinner ──────────────────────────────────────────────────
let SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
let SPINNER_BRAILLE = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
let SPINNER_DOTS = [".  ", ".. ", "..."]

proc spinner(frames, delay_ms, prefix, suffix):
    var i = 0
    sys.stdout_write(prefix)
    while true:
        sys.stdout_write(frames[i] + suffix)
        sys.stdout_write("\r")
        sys.sleep(delay_ms)
        i = (i + 1) % len(frames)

proc progress_bar(current, total, width, filled, empty, color):
    let pct = current / total
    let filled_w = int(current * width / total)
    let empty_w = width - filled_w
    let bar = color + str_repeat("█", filled_w) + DIM() + str_repeat("░", width - filled_w) + RESET()
    return "[" + bar + "] " + str(int(current * 100 / total)) + "%"

# ─── Live Rendering ──────────────────────────────────────────────────────
proc live_render(render_fn, fps):
    let delay = int(1000 / fps)
    hide_cursor()
    save_cursor()
    var running = true
    while running:
        restore_cursor()
        let output = render_fn()
        print_raw(output)
        sys.sleep(delay)
    show_cursor()

proc hide_cursor():
    sys.stdout_write("\x1b[?25l")

proc show_cursor():
    sys.stdout_write("\x1b[?25h")

proc save_cursor():
    sys.stdout_write("\x1b[s")

proc restore_cursor():
    sys.stdout_write("\x1b[u")

proc clear():
    sys.stdout_write("\x1b[2J\x1b[H")

proc clear_line():
    sys.stdout_write("\x1b[2K\r")

proc cursor_up(n):
    sys.stdout_write("\x1b[" + str(n) + "A")

proc cursor_down(n):
    sys.stdout_write("\x1b[" + str(n) + "B")

proc cursor_left(n):
    sys.stdout_write("\x1b[" + str(n) + "D")

proc cursor_right(n):
    sys.stdout_write("\x1b[" + str(n) + "C")

proc print(text):
    sys.stdout_write(text)

proc println(text):
    sys.stdout_write(text + "\n")

# ─── Rich Console ────────────────────────────────────────────────────────
# ─── Rich Console ────────────────────────────────────────────────────────
proc _rule_impl(title, style):
    var title_str = ""
    if title != "":
        let title_str = " " + title + " "
    end
    let w = 80 - len(title_str)
    sys.stdout_write(style(str_repeat("─", w / 2) + title_str + str_repeat("─", w - w / 2), style) + "\n")

let CONSOLE_METHODS = {
    "log": proc(text): sys.stdout_write(text + "\n"),
    "info": proc(text): sys.stdout_write(BLUE() + "ℹ " + RESET() + text + "\n"),
    "success": proc(text): sys.stdout_write(GREEN() + "✓ " + RESET() + text + "\n"),
    "warning": proc(text): sys.stdout_write(YELLOW() + "⚠ " + RESET() + text + "\n"),
    "error": proc(text): sys.stdout_write(RED() + "✗ " + RESET() + text + "\n"),
    "debug": proc(text): sys.stdout_write(GRAY() + "» " + RESET() + text + "\n"),
    "rule": _rule_impl,
    "print": proc(text): sys.stdout_write(str(text) + "\n")
}

proc console():
    return CONSOLE_METHODS

# ─── Progress ────────────────────────────────────────────────────────────
let PROGRESS_STATE = {"_task_id": 0, "_tasks": {}, "_running": false}

proc progress():
    let p = {}
    p["add_task"] = proc(description, total, completed, visible):
        let id = PROGRESS_STATE._task_id
        PROGRESS_STATE._task_id = PROGRESS_STATE._task_id + 1
        PROGRESS_STATE._tasks[id] = {"desc": description, "total": total, "completed": completed, "visible": visible}
        return id

    p["update"] = proc(task_id, completed, total, description, visible):
        if dict_has(PROGRESS_STATE._tasks, task_id):
            let t = PROGRESS_STATE._tasks[task_id]
            if completed >= 0:
                t["completed"] = completed
            if total >= 0:
                t["total"] = total
            if description != "":
                t["desc"] = description
            t["visible"] = visible

    p["remove_task"] = proc(task_id):
        if dict_has(PROGRESS_STATE._tasks, task_id):
            let t = PROGRESS_STATE._tasks[task_id]
            t["visible"] = false

    p["start"] = proc():
        PROGRESS_STATE._running = true
        hide_cursor()
        save_cursor()

    p["stop"] = proc():
        PROGRESS_STATE._running = false
        show_cursor()
        restore_cursor()

    p["render"] = proc():
        restore_cursor()
        for id in dict_keys(PROGRESS_STATE._tasks):
            let t = PROGRESS_STATE._tasks[id]
            if not t["visible"]:
                continue
            let pct = t["completed"] / t["total"]
            let bar = progress_bar(t["completed"], t["total"], 40)
            sys.stdout_write("  " + t["desc"] + " " + bar + "\n")

    return p

# ─── Layout ──────────────────────────────────────────────────────────────
proc columns(items, width, gap, equal):
    let n = len(items)
    if n == 0:
        return ""
    let col_w = int((width - gap * (n - 1)) / n)
    let lines_per_item = []
    let max_h = 0
    for item in items:
        let lines = split(item, "\n")
        push(lines_per_item, lines)
        if len(lines) > max_h:
            max_h = len(lines)
    var result = ""
    for row in range(max_h):
        var line = ""
        for ci in range(n):
            let item_lines = lines_per_item[ci]
            if row < len(item_lines):
                let cell = item_lines[row]
                line = line + cell + str_repeat(" ", col_w - len(cell))
            else:
                line = line + str_repeat(" ", col_w)
            if ci < n - 1:
                line = line + str_repeat(" ", gap)
        result = result + line + "\n"
    return result

# ─── Tree ────────────────────────────────────────────────────────────────
proc tree(root_label, children, guide_style):
    var result = style(root_label, BOLD()) + "\n"
    let prefix = "   "
    let mid = "├─ "
    let end = "└─ "
    let cont = "│  "
    proc render(name, child, depth, is_last):
        var line = str_repeat(prefix, depth)
        if is_last:
            line = line + end
        else:
            line = line + mid
        line = line + name
        return line
    for i in range(len(children)):
        let child = children[i]
        let is_last = (i == len(children) - 1)
        let line = render(child["label"] or child, child, 0, is_last)
        result = result + style(line, guide_style) + "\n"
        if dict_has(child, "children"):
            pass
    return result

# ─── Syntax Highlighting (basic) ─────────────────────────────────────────
proc highlight_json(text):
    let t = replace(text, "\"", YELLOW() + "\"" + RESET())
    t = replace(t, ":", MAGENTA() + ":" + RESET())
    t = replace(t, "{", CYAN() + "{" + RESET())
    t = replace(t, "}", CYAN() + "}" + RESET())
    t = replace(t, "[", CYAN() + "[" + RESET())
    t = replace(t, "]", CYAN() + "]" + RESET())
    t = replace(t, "true", GREEN() + "true" + RESET())
    t = replace(t, "false", RED() + "false" + RESET())
    t = replace(t, "null", DIM() + "null" + RESET())
    return t

proc highlight_sage(text):
    let t = replace(text, "proc", CYAN() + "proc" + RESET())
    t = replace(t, "let", MAGENTA() + "let" + RESET())
    t = replace(t, "var", MAGENTA() + "var" + RESET())
    t = replace(t, "if", CYAN() + "if" + RESET())
    t = replace(t, "else", CYAN() + "else" + RESET())
    t = replace(t, "for", CYAN() + "for" + RESET())
    t = replace(t, "while", CYAN() + "while" + RESET())
    t = replace(t, "return", YELLOW() + "return" + RESET())
    t = replace(t, "import", BLUE() + "import" + RESET())
    t = replace(t, "true", GREEN() + "true" + RESET())
    t = replace(t, "false", RED() + "false" + RESET())
    t = replace(t, "nil", DIM() + "nil" + RESET())
    return t

# ─── Export ──────────────────────────────────────────────────────────────
let console = console()
let progress = progress()