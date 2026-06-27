gc_disable()
import rich.style
import rich.color
import rich.theme
import rich.text
import rich.measure

# Core console output with styling, sizing, and terminal detection

# Terminal capabilities
proc detect_terminal_size():
    # Try to detect terminal size
    # Returns {"width": w, "height": h}
    # Default to 80x24 if can't detect
    return {"width": 80, "height": 24}

# Console class
class Console:
    proc init(self, color_system, theme, width, height, force_terminal, no_color):
        if color_system == nil:
            color_system = "truecolor"
        self.color_system = color_system
        self.theme = theme if theme != nil else rich.theme.create_theme("default")
        self.width = width if width != nil else 80
        self.height = height if height != nil else 25
        self.force_terminal = force_terminal if force_terminal != nil else true
        self.no_color = no_color if no_color != nil else false
        self.record = false
        self.export_html = false
        self.export_svg = false
        self._recorded = []
        self._live = nil
        self._file = nil
        let size = detect_terminal_size()
        if width == nil:
            self.width = size["width"]
        if height == nil:
            self.height = size["height"]

    # Print a rich renderable object
    proc print(self, obj, end, style, highlight):
        if end == nil:
            end = chr(10)
        let rendered = self.render(obj)
        self._output(rendered + end)

    # Output raw text (low level)
    proc _output(self, text):
        if self.record:
            push(self._recorded, text)
        if self.export_html:
            push(self._recorded, text)
            return
        if self.no_color:
            # Strip ANSI codes
            let clean = rich.measure.strip_ansi(text)
            print(clean)
            return
        print(text)

    # Render a renderable object
    proc render(self, obj):
        if obj == nil:
            return ""
        if type(obj) == "string":
            return obj
        if type(obj) == "number":
            return str(obj)
        if type(obj) == "instance":
            # Check if it's a Text
            if dict_has(obj, "segments"):
                return obj.render()
            # Check if it's a Panel, Table, etc
            if dict_has(obj, "__rich__"):
                return obj.__rich__(self)
            # Default: use str
            return obj.__str__()
        return str(obj)

    # Render a Rule
    proc rule(self, title, style, align):
        if style == nil:
            style = "dim"
        let width = self.width
        let char_str = chr(9472)
        if title == nil or title == "":
            let line = ""
            for i in range(width):
                line = line + char_str
            self._output(rich.style.render_styled(line, rich.style.parse_style(style)) + chr(10))
            return
        let title_str = " " + str(title) + " "
        let visible = rich.measure.measure_text(title_str)
        let remaining = width - visible
        if remaining < 0:
            remaining = 0
        let left_len = (remaining / 2) | 0
        let right_len = remaining - left_len
        let left_line = ""
        for i in range(left_len):
            left_line = left_line + char_str
        let right_line = ""
        for i in range(right_len):
            right_line = right_line + char_str
        let result = left_line + title_str + right_line
        self._output(rich.style.render_styled(result, rich.style.parse_style(style)) + chr(10))

    # Start a Live display
    proc live(self, renderable, refresh_per_second, transient):
        let live = Live(renderable, self, refresh_per_second, transient)
        self._live = live
        return live

    # Start recording output
    proc start_capture(self):
        self.record = true
        self._recorded = []

    # Stop recording and return captured lines
    proc stop_capture(self):
        self.record = false
        return self._recorded

    # Export captured output as text
    proc export_text(self):
        let result = ""
        for i in range(len(self._recorded)):
            result = result + self._recorded[i]
        return result

    # Clear the screen
    proc clear(self):
        self._output(chr(27) + "[2J" + chr(27) + "[H")

    # Clear current line
    proc clear_line(self):
        self._output(chr(27) + "[2K")

    # Show cursor
    proc show_cursor(self, show):
        if show:
            self._output(chr(27) + "[?25h")
        else:
            self._output(chr(27) + "[?25l")

    # Move cursor up n lines
    proc cursor_up(self, n):
        if n == nil:
            n = 1
        self._output(chr(27) + "[" + str(n) + "A")

    # Move cursor down n lines
    proc cursor_down(self, n):
        if n == nil:
            n = 1
        self._output(chr(27) + "[" + str(n) + "B")

    # Save cursor position
    proc save_cursor(self):
        self._output(chr(27) + "[s")

    # Restore cursor position
    proc restore_cursor(self):
        self._output(chr(27) + "[u")

    # Check if this is a terminal
    proc is_terminal(self):
        return self.force_terminal

    # Get terminal size
    proc size(self):
        return {"width": self.width, "height": self.height}

    # Out (print with no newline)
    proc out(self, obj, style):
        let rendered = self.render(obj)
        if style != nil:
            rendered = rich.style.render_styled(rendered, rich.style.parse_style(style))
        self._output(rendered)

    # Log a warning/error message with theme styling
    proc log(self, message, log_locals):
        self.print(message)

    # Print JSON with syntax highlighting (basic)
    proc print_json(self, data):
        self.print(self._format_json(data, ""))

    proc _format_json(self, data, indent):
        let nl = chr(10)
        if data == nil:
            return rich.style.render_styled("null", rich.style.parse_style("dim"))
        if type(data) == "number":
            return rich.style.render_styled(str(data), rich.style.parse_style("cyan"))
        if type(data) == "string":
            return rich.style.render_styled(str(data), rich.style.parse_style("green"))
        if type(data) == "bool":
            if data:
                return rich.style.render_styled("true", rich.style.parse_style("bold green"))
            return rich.style.render_styled("false", rich.style.parse_style("bold red"))
        if type(data) == "array":
            if len(data) == 0:
                return "[]"
            let next_indent = indent + "  "
            let result = "[" + nl
            for i in range(len(data)):
                result = result + next_indent + self._format_json(data[i], next_indent)
                if i < len(data) - 1:
                    result = result + ","
                result = result + nl
            result = result + indent + "]"
            return result
        if type(data) == "dict":
            if len(dict_keys(data)) == 0:
                return "{}"
            let next_indent = indent + "  "
            let result = "{" + nl
            let keys = dict_keys(data)
            for i in range(len(keys)):
                let key_rendered = rich.style.render_styled(keys[i], rich.style.parse_style("bright_cyan"))
                result = result + next_indent + key_rendered + ": " + self._format_json(data[keys[i]], next_indent)
                if i < len(keys) - 1:
                    result = result + ","
                result = result + nl
            result = result + indent + "}"
            return result
        return str(data)

# Live display class
class Live:
    proc init(self, renderable, console, refresh_per_second, transient):
        self.renderable = renderable
        self.console = console
        self.refresh_per_second = refresh_per_second if refresh_per_second != nil else 4
        self.transient = transient if transient != nil else false
        self._visible = false
        self._last_lines = 0

    proc start(self, refresh):
        self._visible = true
        self.update(refresh)

    proc stop(self):
        if self._visible:
            if self.transient:
                # Clear the lines
                for i in range(self._last_lines):
                    self.console.cursor_up(1)
                    self.console.clear_line()
            self._visible = false

    proc update(self, renderable):
        if renderable != nil:
            self.renderable = renderable
        if self._visible:
            # Clear previous lines
            for i in range(self._last_lines):
                self.console.cursor_up(1)
                self.console.clear_line()
        # Render new content
        let rendered = self.console.render(self.renderable)
        let lines = split(rendered, chr(10))
        self._last_lines = len(lines)
        self.console._output(rendered)

    proc __enter__(self):
        self.start(nil)
        return self

    proc __exit__(self):
        self.stop()

# Convenience function to print rich output
proc print_rich(obj, style):
    let c = Console(nil, nil, nil, nil, true, false)
    c.print(obj)
