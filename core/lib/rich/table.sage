gc_disable()
import rich.box
import rich.style
import rich.text
import rich.measure
import rich.align
import rich.color

# Table rendering component

class Table:
    proc init(self, title, caption, box_style, border_style, show_header,
              show_footer, show_edge, show_lines, padding, expand, width, style,
              header_style, title_style, caption_style, row_styles, leading, safe_box):
        self.title = title if title != nil else nil
        self.caption = caption if caption != nil else nil
        self.box_style = box_style if box_style != nil else rich.box.get_box("single")
        self.border_style = border_style if border_style != nil else "blue"
        self.show_header = show_header if show_header != nil else true
        self.show_footer = show_footer if show_footer != nil else false
        self.show_edge = show_edge if show_edge != nil else true
        self.show_lines = show_lines if show_lines != nil else false
        self.padding = padding if padding != nil else [0, 1]
        self.expand = expand if expand != nil else false
        self.width = width if width != nil else nil
        self.style = style if style != nil else nil
        self.header_style = header_style if header_style != nil else "bold white"
        self.title_style = title_style if title_style != nil else "bold"
        self.caption_style = caption_style if caption_style != nil else "italic dim"
        self.row_styles = row_styles if row_styles != nil else []
        self.leading = leading if leading != nil else 0
        self.safe_box = safe_box if safe_box != nil else true
        self.columns = []
        self.rows = []
        self._column_widths = nil

    # Add a column definition
    proc add_column(self, header, footer, justify, style, header_style, footer_style,
                    width, min_width, max_width, ratio, no_wrap, overflow, vertical):
        if justify == nil:
            justify = "left"
        if no_wrap == nil:
            no_wrap = false
        let col = {}
        col["header"] = header if header != nil else ""
        col["footer"] = footer if footer != nil else ""
        col["justify"] = justify
        col["style"] = style if style != nil else nil
        col["header_style"] = header_style if header_style != nil else nil
        col["footer_style"] = footer_style if footer_style != nil else nil
        col["width"] = width if width != nil else nil
        col["min_width"] = min_width if min_width != nil else 1
        col["max_width"] = max_width if max_width != nil else nil
        col["ratio"] = ratio if ratio != nil else 1
        col["no_wrap"] = no_wrap
        col["overflow"] = overflow if overflow != nil else "fold"
        col["vertical"] = vertical if vertical != nil else "top"
        push(self.columns, col)
        return self

    # Add a row of data
    proc add_row(self, row_data):
        let processed_row = []
        for i in range(len(row_data)):
            push(processed_row, row_data[i])
        push(self.rows, processed_row)
        return self

    # Render the table
    proc render(self, console):
        if console != nil and self.width == nil:
            self.width = console.width
        let box = self.box_style
        let num_cols = len(self.columns)
        if num_cols == 0:
            return ""

        # Calculate column widths
        let widths = self._calculate_widths()

        # Calculate total width
        let total_width = 0
        for i in range(len(widths)):
            total_width = total_width + widths[i]
        let num_separators = num_cols - 1
        let total_with_borders = total_width + num_separators + 2  # +2 for outer borders

        let lines = []

        # Title
        if self.title != nil:
            let title_line = rich.style.render_styled(self.title, rich.style.parse_style(self.title_style))
            push(lines, title_line)

        # Top border
        if self.show_edge:
            let top_border = self._render_row_border(box, widths, "top")
            if self.border_style != nil:
                top_border = rich.style.render_styled(top_border, rich.style.parse_style(self.border_style))
            push(lines, top_border)

        # Header
        if self.show_header:
            let header_line = self._render_data_row(widths, self.columns, "header")
            if self.border_style != nil:
                header_line = rich.style.render_styled(header_line, rich.style.parse_style(self.border_style))
            push(lines, header_line)
            # Header separator
            if self.show_edge:
                let sep = self._render_row_border(box, widths, "mid")
                if self.border_style != nil:
                    sep = rich.style.render_styled(sep, rich.style.parse_style(self.border_style))
                push(lines, sep)

        # Data rows
        for row_idx in range(len(self.rows)):
            let row = self.rows[row_idx]
            let row_line = self._render_data_row(widths, row, "data")
            if self.border_style != nil:
                row_line = rich.style.render_styled(row_line, rich.style.parse_style(self.border_style))
            push(lines, row_line)
            # Row separators
            if self.show_lines and row_idx < len(self.rows) - 1:
                if self.show_edge:
                    let sep = self._render_row_border(box, widths, "mid")
                    if self.border_style != nil:
                        sep = rich.style.render_styled(sep, rich.style.parse_style(self.border_style))
                    push(lines, sep)

        # Footer
        if self.show_footer:
            if self.show_edge:
                let sep = self._render_row_border(box, widths, "mid")
                if self.border_style != nil:
                    sep = rich.style.render_styled(sep, rich.style.parse_style(self.border_style))
                push(lines, sep)
            let footer_line = self._render_data_row(widths, self.columns, "footer")
            if self.border_style != nil:
                footer_line = rich.style.render_styled(footer_line, rich.style.parse_style(self.border_style))
            push(lines, footer_line)

        # Bottom border
        if self.show_edge:
            let bottom = self._render_row_border(box, widths, "bottom")
            if self.border_style != nil:
                bottom = rich.style.render_styled(bottom, rich.style.parse_style(self.border_style))
            push(lines, bottom)

        # Caption
        if self.caption != nil:
            let caption_line = rich.style.render_styled(self.caption, rich.style.parse_style(self.caption_style))
            push(lines, caption_line)

        let result = ""
        for i in range(len(lines)):
            if i > 0:
                result = result + chr(10)
            result = result + lines[i]
        return result

    proc _calculate_widths(self):
        if self._column_widths != nil:
            return self._column_widths

        let num_cols = len(self.columns)
        let widths = []
        # Calculate max width needed per column
        for c in range(num_cols):
            let max_w = 0
            let col = self.columns[c]
            # Header width
            let hw = rich.measure.measure_text(col["header"])
            if hw > max_w:
                max_w = hw
            # Data widths (only measure visible portion)
            for r in range(len(self.rows)):
                if c < len(self.rows[r]):
                    let val = str(self.rows[r][c])
                    let dw = rich.measure.measure_text(val)
                    if dw > max_w:
                        max_w = dw
            # Apply min/max
            let w = max_w + 2  # +2 for padding
            if w < col["min_width"]:
                w = col["min_width"]
            if col["max_width"] != nil and w > col["max_width"]:
                w = col["max_width"]
            push(widths, w)

        # Distribute available width if expanding
        if self.width != nil:
            let total = 0
            for i in range(len(widths)):
                total = total + widths[i]
            let separators = num_cols - 1
            let available = self.width - total - separators - 2  # -2 for outer borders
            if available > 0 and self.expand:
                let extra_per = (available / num_cols) | 0
                for i in range(len(widths)):
                    widths[i] = widths[i] + extra_per

        self._column_widths = widths
        return widths

    proc _render_row_border(self, box, widths, section):
        let result = ""
        if section == "top":
            result = box["top_left"]
        if section == "bottom":
            result = box["bottom_left"]
        if section == "mid":
            result = box["mid_left"]
        if section == "header_sep":
            result = box["title_left"]

        for c in range(len(widths)):
            if c > 0:
                if section == "top":
                    result = result + box["mid_top"]
                if section == "bottom":
                    result = result + box["mid_bottom"]
                if section == "mid":
                    result = result + box["mid"]
                if section == "header_sep":
                    result = result + box["mid_top"]
            let h = box[section] if section == "top" or section == "bottom" else box["top"]
            for i in range(widths[c]):
                result = result + h

        if section == "top":
            result = result + box["top_right"]
        if section == "bottom":
            result = result + box["bottom_right"]
        if section == "mid":
            result = result + box["mid_right"]
        if section == "header_sep":
            result = result + box["title_right"]
        return result

    proc _render_data_row(self, widths, items, row_type):
        let box = self.box_style
        let result = box["left"]
        let num_cols = len(widths)

        for c in range(num_cols):
            if c > 0:
                result = result + box["mid_left"] if row_type == "header" or row_type == "data" else box["mid_right"]

            let content = ""
            if row_type == "header" or row_type == "footer":
                if c < len(items):
                    let col = items[c]
                    content = col["header"] if row_type == "header" else col["footer"]
            else:
                if c < len(items):
                    content = str(items[c])

            let col_width = widths[c]
            let visible = rich.measure.measure_text(content)
            let padding = 1  # Default padding
            let inner_width = col_width - padding * 2
            if inner_width < 0:
                inner_width = 0

            # Truncate if needed
            if visible > inner_width:
                let truncated = ""
                let tw = 0
                let charset = content
                let ic = 0
                while ic < len(charset) and tw < inner_width:
                    let cw = rich.measure.measure_char(charset[ic])
                    if tw + cw <= inner_width:
                        truncated = truncated + charset[ic]
                        tw = tw + cw
                    ic = ic + 1
                content = truncated
                visible = tw

            # Pad
            let right_pad = inner_width - visible
            if right_pad < 0:
                right_pad = 0
            let pad_left = ""
            for i in range(padding):
                pad_left = pad_left + " "
            let pad_right = ""
            for i in range(padding + right_pad):
                pad_right = pad_right + " "

            result = result + pad_left + content + pad_right

        result = result + box["right"]
        return result

    # __rich__ protocol for console rendering
    proc __rich__(self, console):
        return self.render(console)

    # __str__
    proc __str__(self):
        return self.render(nil)

    # Add multiple rows
    proc add_rows(self, rows_list):
        for i in range(len(rows_list)):
            self.add_row(rows_list[i])
        return self

# Create a table quickly
proc create_table(title, box, style, show_header, show_lines, safe_box):
    return Table(title, nil, box, style, show_header, false, true, show_lines, nil, false, nil, nil, nil, nil, nil, nil, nil, safe_box)
