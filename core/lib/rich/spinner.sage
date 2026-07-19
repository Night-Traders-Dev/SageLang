gc_disable()
import rich.style

# Spinner animation frames

# Classic spinners
proc dots():
    return ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

proc line():
    return ["|", "/", "-", "\\"]

proc dots_simple():
    return [".  ", ".. ", "...", "   "]

proc arrow():
    return ["←", "↖", "↑", "↗", "→", "↘", "↓", "↙"]

proc bounce():
    return ["[    ]", "[   =]", "[  ==]", "[ ===]", "[====]", "[=== ]", "[==  ]", "[=   ]"]

proc pulse():
    return ["█", "▓", "▒", "░"]

proc point():
    return ["∙∙∙", "●∙∙", "∙●∙", "∙∙●", "∙∙∙"]

proc grow_horizontal():
    return ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "▊", "▋", "▌", "▍", "▎"]

proc grow_vertical():
    return ["▁", "▃", "▄", "▅", "▆", "▇", "▆", "▅", "▄", "▃"]

proc star():
    return ["✶", "✸", "✹", "✺", "✹", "✷"]

proc christmas():
    return ["🌲", "🎄"]

# Get spinner frames by name
proc get_spinner(name):
    if name == nil:
        return dots()
    let lname = lower(name)
    if lname == "dots":
        return dots()
    if lname == "line" or lname == "lines":
        return line()
    if lname == "dots_simple" or lname == "simple_dots":
        return dots_simple()
    if lname == "arrow" or lname == "arrows":
        return arrow()
    if lname == "bounce":
        return bounce()
    if lname == "pulse":
        return pulse()
    if lname == "point":
        return point()
    if lname == "grow_horizontal":
        return grow_horizontal()
    if lname == "grow_vertical":
        return grow_vertical()
    if lname == "star":
        return star()
    if lname == "christmas":
        return christmas()
    return dots()

# Simple spinner display
class Spinner:
    proc init(self, name, text, style):
        self.frames = get_spinner(name)
        self.text = ""
        if text != nil:
            self.text = text
        self.style_str = "green"
        if style != nil:
            self.style_str = style
        self._index = 0

    proc render(self):
        let frame = rich.style.render_styled(self.frames[self._index], rich.style.parse_style(self.style_str))
        self._index = (self._index + 1) % len(self.frames)
        if self.text != "":
            return frame + " " + self.text
        return frame

    proc next_frame(self):
        let frame = self.frames[self._index]
        self._index = (self._index + 1) % len(self.frames)
        return frame

    proc reset(self):
        self._index = 0
