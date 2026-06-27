gc_disable()
import rich.box
import rich.style
import rich.text
import rich.measure
import rich.align
import rich.color

# Panel component - content surrounded by a border

class Panel:
    proc init(self, content, title, title_align, subtitle, subtitle_align,
              box_style, border_style, padding, expand, width, style):
        self.content = content
        self.title = title if title != nil else nil
        self.title_align = title_align if title_align != nil else "left"
        self.subtitle = subtitle if subtitle != nil else nil
        self.subtitle_align = subtitle_align if subtitle_align != nil else "right"
        self.box_style = box_style if box_style != nil else rich.box.get_box("single")
        self.border_style = rich.style.parse_style(border_style) if border_style != nil else nil
        self.padding = padding if padding != nil else [0, 1]  # [top_bottom, left_right]
        self.expand = expand if expand != nil else true
        self.width = width if width != nil else nil
        self.style = rich.style.parse_style(style) if style != nil else nil

    # Render the panel
    proc render(self, console):
        let box = self.box_style
        let cl = box["top_left"]
        let cr = box["top_right"]
        let bl = box["bottom_left"]
        let br = box["bottom_right"]
        let h = box["top"]
        let v = box["left"]
        let rv = box["right"]

        # Get content as string
        let content_str = self._render_content(console)
        let content_lines = split(content_str, chr(10))

        # Calculate width
        let max_content_width = 0
        for i in range(len(content_lines)):
            let lw = rich.measure.measure_text(content_lines[i])
            if lw > max_content_width:
                max_content_width = lw
        let pad = self.padding[1] if len(self.padding) >= 2 else 0
        let width = max_content_width + pad * 2
        if self.width != nil:
            width = self.width
        if width < 4:
            width = 4

        let border = rich.style.render_styled("", self.border_style) if self.border_style != nil else ""
        # Build output
        let lines = []

        # Top border with title
        let top_line = self._make_border_line(box, "top", width, self.title, self.title_align, self.subtitle, self.subtitle_align)
        lines = push(lines, top_line)

        # Top padding
        let top_pad = self.padding[0] if len(self.padding) > 0 else 0
        for i in range(top_pad):
            let pad_line = v + self._repeat_char(" ", width) + rv
            if self.border_style != nil:
                pad_line = rich.style.render_styled(pad_line, self.border_style)
            push(lines, pad_line)

        # Content lines
        for i in range(len(content_lines)):
            let line = content_lines[i]
            let visible = rich.measure.measure_text(line)
            let right_pad = width - visible
            if right_pad < 0:
                right_pad = 0
            let padded = self._repeat_char(" ", pad) + line + self._repeat_char(" ", right_pad + pad)
            let border_line = v + padded + rv
            if self.border_style != nil:
                border_line = rich.style.render_styled(border_line, self.border_style)
            push(lines, border_line)

        # Bottom padding
        for i in range(top_pad):
            let pad_line = v + self._repeat_char(" ", width) + rv
            if self.border_style != nil:
                pad_line = rich.style.render_styled(pad_line, self.border_style)
            push(lines, pad_line)

        # Bottom border
        let bottom_line = self._make_border_line(box, "bottom", width, nil, nil, nil, nil)
        push(lines, bottom_line)

        let result = ""
        for i in range(len(lines)):
            if i > 0:
                result = result + chr(10)
            result = result + lines[i]
        return result

    proc _render_content(self, console):
        if self.content == nil:
            return ""
        if type(self.content) == "string":
            return self.content
        if type(self.content) == "number":
            return str(self.content)
        if type(self.content) == "instance":
            if dict_has(self.content, "render"):
                return self.content.render()
            if dict_has(self.content, "__rich__"):
                return self.content.__rich__(console)
        return str(self.content)

    proc _make_border_line(self, box, edge, width, title, title_align, subtitle, subtitle_align):
        let h = box[edge]
        if edge == "top":
            let left_corner = box["top_left"]
            let right_corner = box["top_right"]
        else:
            let left_corner = box["bottom_left"]
            let right_corner = box["bottom_right"]

        let has_title = title != nil and len(title) > 0
        let has_subtitle = subtitle != nil and len(subtitle) > 0

        if not has_title and not has_subtitle:
            let line = left_corner + self._repeat_char(h, width) + right_corner
            if self.border_style != nil:
                return rich.style.render_styled(line, self.border_style)
            return line

        let title_text = ""
        if has_title:
            title_text = title_text + " " + str(title) + " "
        if has_subtitle:
            title_text = title_text + " " + str(subtitle) + " "

        let title_len = len(title_text)
        let available = width - title_len
        if available < 0:
            available = 0

        let left_len = 0
        let right_len = 0
        if title_align == nil or title_align == "left":
            left_len = 2
            right_len = available - left_len
        if title_align == "center":
            left_len = (available / 2) | 0
            right_len = available - left_len
        if title_align == "right":
            right_len = 2
            left_len = available - right_len

        let line = left_corner + self._repeat_char(h, left_len) + title_text + self._repeat_char(h, right_len) + right_corner
        if self.border_style != nil:
            return rich.style.render_styled(line, self.border_style)
        return line

    proc _repeat_char(self, ch, n):
        let result = ""
        for i in range(n):
            result = result + ch
        return result

    # Fit panel to a given width
    proc fit(self, width):
        self.width = width
        return self

    # __rich__ protocol for console rendering
    proc __rich__(self, console):
        return self.render(console)

    # __str__ for basic printing
    proc __str__(self):
        return self.render(nil)

# Create a panel from text
proc create_panel(content, title, border_style, box, padding, expand, width, style, subtitle, title_align):
    return Panel(content, title, title_align, subtitle, nil, box, border_style, padding, expand, width, style)
