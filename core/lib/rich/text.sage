gc_disable()
import rich.style
import rich.measure

# Rich text - styled text with spans and segments

# A segment is a single piece of text with a style
proc Segment(text, style_obj):
    let seg = {}
    seg["text"] = ""
    if text != nil:
        seg["text"] = text
    seg["style"] = style.style_default()
    if style_obj != nil:
        seg["style"] = style_obj
    return seg

# Create a segment from plain text
proc segment_text(text):
    return Segment(text, style.style_default())

# Render a segment to ANSI
proc render_segment(seg):
    if seg == nil:
        return ""
    let text = seg["text"]
    if type(text) == "number":
        text = str(text)
    return style.style_ansi_open(seg["style"]) + text + style.style_ansi_close(seg["style"])

# Measure segment visible width
proc segment_width(seg):
    return measure.measure_text(seg["text"])

# Optimization: Split segment using native slice()
proc segment_split(seg, pos):
    let seg_text = seg["text"]
    let seg_len = len(seg_text)
    if pos <= 0:
        return (Segment("", seg["style"]), seg)
    if pos >= seg_len:
        return (seg, Segment("", seg["style"]))
    let left = Segment(slice(seg_text, 0, pos), seg["style"])
    let right = Segment(slice(seg_text, pos, seg_len), seg["style"])
    return (left, right)

# Style a segment
proc segment_style(seg, style_obj):
    let new_seg = {}
    new_seg["text"] = seg["text"]
    new_seg["style"] = style.merge_styles(seg["style"], style_obj)
    return new_seg

# --- Text class - collection of styled segments ---

class Text:
    proc init(self, text, style_obj):
        if text == nil:
            text = ""
        self.segments = []
        if type(text) == "array":
            self.segments = text
        else:
            self.append(text, style_obj)
        self.justify = nil
        self.end = ""
        self.overflow = "fold"

    # Append text with optional style
    proc append(self, text, style_obj):
        if type(text) == "string" or type(text) == "number":
            push(self.segments, Segment(str(text), style_obj))
        if type(text) == "instance":
            # Append another Text or Segment
            if self._is_segment(text):
                push(self.segments, text)
            if self._is_text(text):
                let other_segs = text.segments
                for i in range(len(other_segs)):
                    push(self.segments, other_segs[i])
        return self

    # Append text with plain formatting
    proc append_text(self, text):
        return self.append(text, nil)

    # Optimization: Stylize using native slice() instead of O(N^2) character loops
    proc stylize(self, style_obj, start, end_pos):
        let actual_start = start
        let actual_end = end_pos
        if actual_start == nil:
            actual_start = 0
        let total = self._total_chars()
        if actual_end == nil:
            actual_end = total
        let pos = 0
        let new_segs = []
        for i in range(len(self.segments)):
            let seg = self.segments[i]
            let seg_text = seg["text"]
            let seg_len = len(seg_text)
            let seg_start = pos
            let seg_end_pos = pos + seg_len
            if seg_end_pos <= actual_start or seg_start >= actual_end:
                push(new_segs, seg)
            else:
                let cut1 = actual_start - seg_start
                if cut1 < 0:
                    cut1 = 0
                if cut1 > seg_len:
                    cut1 = seg_len

                let cut2 = actual_end - seg_start
                if cut2 < 0:
                    cut2 = 0
                if cut2 > seg_len:
                    cut2 = seg_len

                if cut1 > 0:
                    push(new_segs, Segment(slice(seg_text, 0, cut1), seg["style"]))
                if cut2 > cut1:
                    let new_style = style.merge_styles(seg["style"], style_obj)
                    push(new_segs, Segment(slice(seg_text, cut1, cut2), new_style))
                if seg_len > cut2:
                    push(new_segs, Segment(slice(seg_text, cut2, seg_len), seg["style"]))
            pos = pos + seg_len
        self.segments = new_segs
        return self

    # Stylize entire text
    proc stylize_all(self, style_obj):
        return self.stylize(style_obj, 0, self._total_chars())

    # Add an inline style to a slice
    proc on(self, style_obj):
        self.stylize_all(style_obj)
        return self

    # Concat with + operator support via join
    proc join(self, other):
        let result = Text("")
        let all_segs = self.segments
        for i in range(len(other.segments)):
            push(all_segs, other.segments[i])
        result.segments = all_segs
        return result

    # Optimization: Use array push and join("") to build plain text in O(N) time
    proc plain(self):
        let parts = []
        for i in range(len(self.segments)):
            push(parts, self.segments[i]["text"])
        return join(parts, "")

    # Get plain text
    proc str(self):
        return self.plain()

    # __str__ dunder
    proc __str__(self):
        return self.plain()

    # Get total character count
    proc _total_chars(self):
        let total = 0
        for i in range(len(self.segments)):
            total = total + len(self.segments[i]["text"])
        return total

    # Length of text in characters
    proc len(self):
        return self._total_chars()

    # Measure total visible width
    proc measure_width(self):
        let total = 0
        for i in range(len(self.segments)):
            total = total + measure.measure_text(self.segments[i]["text"])
        return total

    # Set justification
    proc set_justify(self, justify):
        self.justify = justify
        return self

    # Set end character(s)
    proc set_end(self, end_str):
        self.end = end_str
        return self

    # Set overflow behavior
    proc set_overflow(self, overflow):
        self.overflow = overflow
        return self

    # Optimization: Use array push and join("") to assemble ANSI string in O(N) time
    proc render(self):
        let parts = []
        for i in range(len(self.segments)):
            push(parts, render_segment(self.segments[i]))
        return join(parts, "")

    # Render a single line of the text (for wrapping)
    proc render_line(self):
        return self.render()

    # Optimization: Use native slice() for line segment extraction
    proc split_lines(self):
        let lines_list = []
        let current = Text("")
        for i in range(len(self.segments)):
            let seg = self.segments[i]
            let text = seg["text"]
            let text_len = len(text)
            let start = 0
            for j in range(text_len):
                if text[j] == chr(10):
                    if j > start:
                        current.append(slice(text, start, j), seg["style"])
                    push(lines_list, current)
                    current = Text("")
                    start = j + 1
            if start < text_len:
                current.append(slice(text, start, text_len), seg["style"])
        if current._total_chars() > 0 or len(lines_list) == 0:
            push(lines_list, current)
        return lines_list

    # Optimization: Use native slice() for line wrapping segment extractions
    proc wrap(self, max_width):
        if max_width <= 0:
            return self.split_lines()
        let lines_list = []
        let current = Text("")
        let current_width = 0
        for i in range(len(self.segments)):
            let seg = self.segments[i]
            let text = seg["text"]
            let text_len = len(text)
            let start = 0
            let j = 0
            while j < text_len:
                if text[j] == chr(10):
                    if j > start:
                        current.append(slice(text, start, j), seg["style"])
                    push(lines_list, current)
                    current = Text("")
                    current_width = 0
                    start = j + 1
                    j = start
                    continue
                let char_w = measure.measure_char(text[j])
                if current_width + char_w > max_width and current_width > 0:
                    if j > start:
                        current.append(slice(text, start, j), seg["style"])
                    push(lines_list, current)
                    current = Text("")
                    current_width = 0
                    start = j
                current_width = current_width + char_w
                j = j + 1
            if start < text_len:
                current.append(slice(text, start, text_len), seg["style"])
        if current._total_chars() > 0 or len(lines_list) == 0:
            push(lines_list, current)
        return lines_list

    # Optimization: Use array push and join(chr(10)) for wrapped line rendering
    proc render_wrapped(self, width):
        let lines_list = self.wrap(width)
        let rendered_lines = []
        for i in range(len(lines_list)):
            push(rendered_lines, lines_list[i].render())
        return join(rendered_lines, chr(10))

    # Helper to check if an object is a segment
    proc _is_segment(self, obj):
        if type(obj) != "instance":
            return false
        return dict_has(obj, "text") and dict_has(obj, "style")

    # Helper to check if an object is a Text
    proc _is_text(self, obj):
        if type(obj) != "instance":
            return false
        return dict_has(obj, "segments")

    # Optimization: Use native slice() for text truncation segment extraction
    proc truncate(self, max_width, overflow):
        if overflow == nil:
            overflow = "ellipsis"
        let width = self.measure_width()
        if width <= max_width:
            return self
        let result = Text("")
        let remaining = max_width - 3
        if remaining < 0:
            remaining = 0
        let current_width = 0
        for i in range(len(self.segments)):
            let seg = self.segments[i]
            let text = seg["text"]
            let text_len = len(text)
            let j = 0
            while j < text_len and current_width < remaining:
                current_width = current_width + measure.measure_char(text[j])
                j = j + 1
            if j > 0:
                result.append(slice(text, 0, j), seg["style"])
            if current_width >= remaining:
                break
        if overflow == "ellipsis":
            result.append("...", nil)
        return result

    # Copy text object
    proc copy(self):
        let t = Text("")
        t.segments = self.segments
        t.justify = self.justify
        t.end = self.end
        return t

# Create a text from a string (convenience)
proc text_from_string(s, style_obj):
    return Text(s, style_obj)

# Create styled text
proc styled_text(text, style_str):
    let style_obj = style.parse_style(style_str)
    return Text(text, style_obj)

# Create a span (like Segment but public)
proc span(text, style_obj):
    return Segment(text, style_obj)

# Assemble multiple Text pieces
proc assemble(pieces):
    let result = Text("")
    for i in range(len(pieces)):
        if type(pieces[i]) == "string" or type(pieces[i]) == "number":
            result.append(str(pieces[i]), nil)
        else:
            result.append(pieces[i], nil)
    return result
