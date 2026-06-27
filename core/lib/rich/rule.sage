gc_disable()
import rich.style
import rich.text
import rich.measure

# Rule component - horizontal rule/divider

class Rule:
    proc init(self, title, style, align, characters):
        self.title = title if title != nil else ""
        self.style_str = style if style != nil else ""
        self.align = align if align != nil else "center"
        self.characters = characters if characters != nil else chr(9472)

    proc render(self, console):
        let width = console.width if console != nil else 80
        let ch = self.characters
        if self.title == "" or self.title == nil:
            let line = ""
            for i in range(width):
                line = line + ch
            if self.style_str != "":
                return rich.style.render_styled(line, rich.style.parse_style(self.style_str))
            return line

        let title_str = " " + self.title + " "
        let visible = rich.measure.measure_text(title_str)
        let remaining = width - visible
        if remaining < 0:
            remaining = 0

        let left_len = 0
        let right_len = 0
        if self.align == "left":
            left_len = 1
            right_len = remaining - left_len
        if self.align == "center":
            left_len = (remaining / 2) | 0
            right_len = remaining - left_len
        if self.align == "right":
            right_len = 1
            left_len = remaining - right_len

        let left_line = ""
        for i in range(left_len):
            left_line = left_line + ch
        let right_line = ""
        for i in range(right_len):
            right_line = right_line + ch

        let result = left_line + title_str + right_line
        if self.style_str != "":
            return rich.style.render_styled(result, rich.style.parse_style(self.style_str))
        return result

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

# Create a rule
proc create_rule(title, style, align, characters):
    return Rule(title, style, align, characters)
