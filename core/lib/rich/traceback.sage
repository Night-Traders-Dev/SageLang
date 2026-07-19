gc_disable()
import rich.style
import rich.text
import rich.panel

# Traceback formatting

# Create a formatted traceback display
proc Traceback(exception, frames, show_locals, width, extra_lines):
    let tb = {}
    tb["exception"] = exception
    tb["frames"] = []
    if frames != nil:
        tb["frames"] = frames
    tb["show_locals"] = false
    if show_locals != nil:
        tb["show_locals"] = show_locals
    tb["width"] = 100
    if width != nil:
        tb["width"] = width
    tb["extra_lines"] = 0
    if extra_lines != nil:
        tb["extra_lines"] = extra_lines
    return tb

# Add a frame to the traceback
proc add_frame(tb, filename, line, func, code, locals_dict):
    let frame = {}
    frame["filename"] = filename
    frame["line"] = line
    frame["func"] = ""
    if func != nil:
        frame["func"] = func
    frame["code"] = ""
    if code != nil:
        frame["code"] = code
    frame["locals"] = {}
    if locals_dict != nil:
        frame["locals"] = locals_dict
    push(tb["frames"], frame)

# Format a traceback as a string
proc format_traceback(tb):
    let lines = []
    let nl = chr(10)

    push(lines, rich.style.render_styled("Traceback (most recent call last):", rich.style.parse_style("bold red")))

    let frame_count = len(tb["frames"])
    let max_frames = 8  # Show at most 8 frames

    let start_idx = 0
    if frame_count > max_frames:
        start_idx = frame_count - max_frames
        push(lines, rich.style.render_styled("  ... " + str(frame_count - max_frames) + " frames hidden ...", rich.style.parse_style("dim")))

    for i in range(len(tb["frames"])):
        if i < start_idx:
            continue
        let frame = tb["frames"][i]
        let filename = frame["filename"]
        let line_num = frame["line"]
        let func_name = frame["func"]

        let file_style = rich.style.render_styled(filename, rich.style.parse_style("bright_green"))
        let line_style = rich.style.render_styled(str(line_num), rich.style.parse_style("cyan"))
        let func_style = rich.style.render_styled(func_name, rich.style.parse_style("yellow"))

        let location = "  File " + file_style + ", line " + line_style + ", in " + func_style
        push(lines, location)

        # Show code snippet
        let code = frame["code"]
        if code != nil and code != "":
            push(lines, "    " + rich.style.render_styled(code, rich.style.parse_style("on bright_black")))

    # Exception message
    let exc_style = rich.style.render_styled(str(tb["exception"]), rich.style.parse_style("bold red"))
    push(lines, exc_style)

    let result = ""
    for i in range(len(lines)):
        if i > 0:
            result = result + nl
        result = result + lines[i]
    return result

# Render traceback
proc render_traceback(tb, console):
    let text = format_traceback(tb)
    if console != nil:
        console._output(text + chr(10))
    return text

# Create a traceback from a caught exception
proc from_exception(exc):
    return Traceback(exc, [], false, nil, 0)
