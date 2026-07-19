gc_disable()
import rich.style
import rich.measure

# Rich text - styled text with spans and segments

# A segment is a single piece of text with a style
proc Segment(text, style):
    let seg = {}
    seg["text"] = ""
    if text != nil:
        seg["text"] = text
    seg["style"] = rich.style.style_default()
    if style != nil:
        seg["style"] = style
    return seg

# Create a segment from plain text
proc segment_text(text):
    return Segment(text, rich.style.style_default())

# Render a segment to ANSI
proc render_segment(seg):
    if seg == nil:
        return ""
    let text = seg["text"]
    if type(text) == "number":
        text = str(text)
    return rich.style.style_ansi_open(seg["style"]) + text + rich.style.style_ansi_close(seg["style"])

# Measure segment visible width
proc segment_width(seg):
    return rich.measure.measure_text(seg["text"])

# Split a segment at position
proc segment_split(seg, pos):
    if pos <= 0:
        return (Segment("", seg["style"]), seg)
    if pos >= len(seg["text"]):
        return (seg, Segment("", seg["style"]))
    let left = Segment("", seg["style"])
    left["text"] = ""
    for i in range(pos):
        left["text"] = left["text"] + seg["text"][i]
    let right = Segment("", seg["style"])
    right["text"] = ""
    for i in range(len(seg["text"]) - pos):
        right["text"] = right["text"] + seg["text"][pos + i]
    return (left, right)

# Style a segment
proc segment_style(seg, style):
    let new_seg = {}
    new_seg["text"] = seg["text"]
    new_seg["style"] = rich.style.merge_styles(seg["style"], style)
    return new_seg

# --- Text class - collection of styled segments ---

class Text:
    proc init(self, text, style):
        if text == nil:
            text = ""
        self.segments = []
        if type(text) == "array":
            self.segments = text
        else:
            self.append(text, style)
        self.justify = nil
        self.end = ""
        self.overflow = "fold"

    # Append text with optional style
    proc append(self, text, style):
        if type(text) == "string" or type(text) == "number":
            push(self.segments, Segment(str(text), style))
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

    # Stylize - apply a style to the whole text
    proc stylize(self, style, start, end_pos):
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
                let before_text = ""
                let during_text = ""
                let after_text = ""
                let j = 0
                while j < seg_len:
                    let char_pos = pos + j
                    if char_pos < actual_start:
                        before_text = before_text + seg_text[j]
                    if char_pos >= actual_start and char_pos < actual_end:
                        during_text = during_text + seg_text[j]
                    if char_pos >= actual_end:
                        after_text = after_text + seg_text[j]
                    j = j + 1
                if len(before_text) > 0:
                    push(new_segs, Segment(before_text, seg["style"]))
                if len(during_text) > 0:
                    let new_style = rich.style.merge_styles(seg["style"], style)
                    push(new_segs, Segment(during_text, new_style))
                if len(after_text) > 0:
                    push(new_segs, Segment(after_text, seg["style"]))
            pos = pos + seg_len
        self.segments = new_segs
        return self

    # Stylize entire text
    proc stylize_all(self, style):
        return self.stylize(style, 0, self._total_chars())

    # Add an inline style to a slice
    proc on(self, style):
        self.stylize_all(style)
        return self

    # Concat with + operator support via join
    proc join(self, other):
        let result = Text("")
        let all_segs = self.segments
        for i in range(len(other.segments)):
            push(all_segs, other.segments[i])
        result.segments = all_segs
        return result

    # Get plain text without styling
    proc plain(self):
        let result = ""
        for i in range(len(self.segments)):
            result = result + self.segments[i]["text"]
        return result

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
            total = total + rich.measure.measure_text(self.segments[i]["text"])
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

    # Render to ANSI string
    proc render(self):
        let result = ""
        for i in range(len(self.segments)):
            result = result + render_segment(self.segments[i])
        return result

    # Render a single line of the text (for wrapping)
    proc render_line(self):
        return self.render()

    # Split text into lines at newline characters
    proc split_lines(self):
        let lines_list = []
        let current = Text("")
        for i in range(len(self.segments)):
            let seg = self.segments[i]
            let text = seg["text"]
            let start = 0
            let j = 0
            while j < len(text):
                if text[j] == chr(10):
                    if j > start:
                        let line_text = ""
                        for k in range(j - start):
                            line_text = line_text + text[start + k]
                        current.append(line_text, seg["style"])
                    push(lines_list, current)
                    current = Text("")
                    start = j + 1
                j = j + 1
            if start < len(text):
                let remaining = ""
                for k in range(len(text) - start):
                    remaining = remaining + text[start + k]
                current.append(remaining, seg["style"])
        if current._total_chars() > 0 or len(lines_list) == 0:
            push(lines_list, current)
        return lines_list

    # Wrap text to a maximum width
    proc wrap(self, max_width):
        if max_width <= 0:
            return self.split_lines()
        let lines_list = []
        let current = Text("")
        let current_width = 0
        for i in range(len(self.segments)):
            let seg = self.segments[i]
            let text = seg["text"]
            let start = 0
            let j = 0
            while j < len(text):
                if text[j] == chr(10):
                    if j > start:
                        let line_text = ""
                        for k in range(j - start):
                            line_text = line_text + text[start + k]
                        current.append(line_text, seg["style"])
                    push(lines_list, current)
                    current = Text("")
                    current_width = 0
                    start = j + 1
                    j = start
                    continue
                let char_w = rich.measure.measure_char(text[j])
                if current_width + char_w > max_width and current_width > 0:
                    if j > start:
                        let line_text = ""
                        for k in range(j - start):
                            line_text = line_text + text[start + k]
                        current.append(line_text, seg["style"])
                    push(lines_list, current)
                    current = Text("")
                    current_width = 0
                    start = j
                current_width = current_width + char_w
                j = j + 1
            if start < len(text):
                let remaining = ""
                for k in range(len(text) - start):
                    remaining = remaining + text[start + k]
                current.append(remaining, seg["style"])
        if current._total_chars() > 0 or len(lines_list) == 0:
            push(lines_list, current)
        return lines_list

    # Render with wrapping
    proc render_wrapped(self, width):
        let lines_list = self.wrap(width)
        let result = ""
        for i in range(len(lines_list)):
            if i > 0:
                result = result + chr(10)
            result = result + lines_list[i].render()
        return result

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

    # Truncate text with ellipsis
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
            let added = ""
            let j = 0
            while j < len(text) and current_width < remaining:
                added = added + text[j]
                current_width = current_width + rich.measure.measure_char(text[j])
                j = j + 1
            if len(added) > 0:
                result.append(added, seg["style"])
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
proc text_from_string(s, style):
    return Text(s, style)

# Create styled text
proc styled_text(text, style_str):
    let style = rich.style.parse_style(style_str)
    return Text(text, style)

# Create a span (like Segment but public)
proc span(text, style):
    return Segment(text, style)

# Assemble multiple Text pieces
proc assemble(pieces):
    let result = Text("")
    for i in range(len(pieces)):
        if type(pieces[i]) == "string" or type(pieces[i]) == "number":
            result.append(str(pieces[i]), nil)
        else:
            result.append(pieces[i], nil)
    return result
