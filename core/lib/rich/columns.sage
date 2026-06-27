gc_disable()
import rich.style
import rich.text
import rich.measure

# Columns component - side-by-side layout

class Columns:
    proc init(self, renderables, align, padding, expand, width, equal, title):
        self.renderables = renderables if renderables != nil else []
        self.align = align if align != nil else "left"
        self.padding = padding if padding != nil else [0, 1]
        self.expand = expand if expand != nil else false
        self.width = width if width != nil else nil
        self.equal = equal if equal != nil else false
        self.title = title if title != nil else nil

    proc render(self, console):
        let available_width = self.width if self.width != nil else (console.width if console != nil else 80)
        let num_cols = len(self.renderables)
        if num_cols == 0:
            return ""
        if num_cols == 1:
            return self._render_single(self.renderables[0])

        # Calculate column width
        let pad = self.padding[1] if len(self.padding) > 1 else 0
        let space_for_padding = pad * 2 * num_cols + (num_cols - 1)
        let column_width = (available_width - space_for_padding) / num_cols
        column_width = column_width | 0
        if column_width < 1:
            column_width = 1

        let rendered_cols = []
        for i in range(num_cols):
            let content = self._render_renderable(self.renderables[i])
            let lines = split(content, chr(10))
            let padded_lines = []
            for j in range(len(lines)):
                let line = lines[j]
                let visible = rich.measure.measure_text(line)
                let right_pad = column_width - visible
                if right_pad < 0:
                    right_pad = 0
                let lp = ""
                for k in range(pad):
                    lp = lp + " "
                let rp = ""
                for k in range(pad + right_pad):
                    rp = rp + " "
                push(padded_lines, lp + line + rp)
            push(rendered_cols, padded_lines)

        # Find max lines
        let max_lines = 0
        for i in range(len(rendered_cols)):
            if len(rendered_cols[i]) > max_lines:
                max_lines = len(rendered_cols[i])

        # Pad all columns to same height
        for i in range(len(rendered_cols)):
            while len(rendered_cols[i]) < max_lines:
                let blank = ""
                for k in range(column_width + pad * 2):
                    blank = blank + " "
                push(rendered_cols[i], blank)

        # Assemble result
        let result_lines = []
        for line_idx in range(max_lines):
            let line = ""
            for col_idx in range(num_cols):
                if line_idx < len(rendered_cols[col_idx]):
                    line = line + rendered_cols[col_idx][line_idx]
            push(result_lines, line)

        let result = ""
        for i in range(len(result_lines)):
            if i > 0:
                result = result + chr(10)
            result = result + result_lines[i]
        return result

    proc _render_renderable(self, obj):
        if obj == nil:
            return ""
        if type(obj) == "string":
            return obj
        if type(obj) == "number":
            return str(obj)
        if type(obj) == "instance":
            if dict_has(obj, "render"):
                return obj.render(nil)
            if dict_has(obj, "__rich__"):
                return obj.__rich__(nil)
            if dict_has(obj, "__str__"):
                return obj.__str__()
        return str(obj)

    proc _render_single(self, obj):
        return self._render_renderable(obj)

    proc add_renderable(self, obj):
        push(self.renderables, obj)
        return self

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

# Create columns
proc create_columns(renderables, padding, expand, width):
    return Columns(renderables, nil, padding, expand, width, false, nil)
