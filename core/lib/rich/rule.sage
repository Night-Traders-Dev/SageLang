gc_disable()
import rich.style as style
import rich.text as text
import rich.measure as measure

# Rule component - horizontal rule/divider

class Rule:
    proc init(self, title, style_name, align, characters):
        self.title = ""
        if title != nil:
            self.title = title
        self.style_str = ""
        if style_name != nil:
            self.style_str = style_name
        self.align = "center"
        if align != nil:
            self.align = align
        self.characters = "─"
        if characters != nil:
            self.characters = characters

    proc render(self, console):
        let width = 80
        if console != nil:
            width = console.width
        let ch = self.characters
        if self.title == "" or self.title == nil:
            # Optimization: Use native string_repeat VM built-in to avoid O(N^2) string concatenation
            let line = string_repeat(ch, width)
            if self.style_str != "":
                return style.render_styled(line, style.parse_style(self.style_str))
            return line

        let title_str = " " + self.title + " "
        let visible = measure.measure_text(title_str)
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

        # Optimization: Use native string_repeat VM built-in to avoid O(N^2) string concatenation
        let left_line = string_repeat(ch, left_len)
        let right_line = string_repeat(ch, right_len)

        let result = left_line + title_str + right_line
        if self.style_str != "":
            return style.render_styled(result, style.parse_style(self.style_str))
        return result

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

# Create a rule
proc create_rule(title, style_name, align, characters):
    return Rule(title, style_name, align, characters)
