gc_disable()
import rich.style as style
import rich.text as text
import rich.measure as measure

# Columns component - side-by-side layout

class Columns:
    proc init(self, renderables, align, padding, expand, width, equal, title):
        self.renderables = []
        if renderables != nil:
            self.renderables = renderables
        self.align = "left"
        if align != nil:
            self.align = align
        self.padding = [0, 1]
        if padding != nil:
            self.padding = padding
        self.expand = false
        if expand != nil:
            self.expand = expand
        self.width = nil
        if width != nil:
            self.width = width
        self.equal = false
        if equal != nil:
            self.equal = equal
        self.title = nil
        if title != nil:
            self.title = title

    proc render(self, console):
        let available_width = 80
        if console != nil:
            available_width = console.width
        if self.width != nil:
            available_width = self.width
        let num_cols = len(self.renderables)
        if num_cols == 0:
            return ""
        if num_cols == 1:
            return self._render_single(self.renderables[0])

        # Calculate column width
        let pad = 0
        if len(self.padding) > 1:
            pad = self.padding[1]
        let space_for_padding = pad * 2 * num_cols + (num_cols - 1)
        let column_width = (available_width - space_for_padding) / num_cols
        column_width = column_width | 0
        if column_width < 1:
            column_width = 1

        # Precompute left padding string
        let lp = string_repeat(" ", pad)

        let rendered_cols = []
        for i in range(num_cols):
            let content = self._render_renderable(self.renderables[i])
            let lines = split(content, chr(10))
            let padded_lines = []
            for j in range(len(lines)):
                let line = lines[j]
                let visible = measure.measure_text(line)
                let right_pad = column_width - visible
                if right_pad < 0:
                    right_pad = 0
                let rp = string_repeat(" ", pad + right_pad)
                push(padded_lines, lp + line + rp)
            push(rendered_cols, padded_lines)

        # Find max lines
        let max_lines = 0
        for i in range(len(rendered_cols)):
            if len(rendered_cols[i]) > max_lines:
                max_lines = len(rendered_cols[i])

        # Pad all columns to same height using precalculated blank line
        let blank = string_repeat(" ", column_width + pad * 2)
        for i in range(len(rendered_cols)):
            while len(rendered_cols[i]) < max_lines:
                push(rendered_cols[i], blank)

        # Assemble result lines using array push + join to avoid O(N^2) string concatenation
        let result_lines = []
        for line_idx in range(max_lines):
            let line_parts = []
            for col_idx in range(num_cols):
                if line_idx < len(rendered_cols[col_idx]):
                    push(line_parts, rendered_cols[col_idx][line_idx])
            push(result_lines, join(line_parts, ""))

        return join(result_lines, chr(10))

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
