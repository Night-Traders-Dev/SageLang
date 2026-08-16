gc_disable()
import rich.style
import rich.text
import rich.measure

# Markdown rendering (simplified subset)

class Markdown:
    proc init(self, markup, code_theme, hyperlinks):
        self.markup = markup
        self.code_theme = "monokai"
        if code_theme != nil:
            self.code_theme = code_theme
        self.hyperlinks = true
        if hyperlinks != nil:
            self.hyperlinks = hyperlinks

    proc render(self, console):
        let lines = split(self.markup, chr(10))
        let result_lines = []
        let in_code_block = false
        let code_lang = ""

        for i in range(len(lines)):
            let line = lines[i]
            let lns = strip(line)

            # Code blocks
            if startswith(lns, "```"):
                if in_code_block:
                    in_code_block = false
                    push(result_lines, "")
                    continue
                else:
                    in_code_block = true
                    code_lang = strip(slice(line, 3, len(line)))
                    continue

            if in_code_block:
                push(result_lines, "  " + line)
                continue

            # Headers
            if self._count_leading(lns, "#") > 0:
                let level = self._count_leading(lns, "#")
                if level > 0 and len(lns) > level and lns[level] == " ":
                    let text = slice(lns, level + 1, len(lns))
                    let style_str = "markdown.h" + str(level)
                    let rendered = rich.style.render_styled(text, rich.style.parse_style("bold"))
                    push(result_lines, rendered)
                    push(result_lines, "")
                    continue

            # Horizontal rules
            if lns == "---" or lns == "***" or lns == "___":
                let width = 80
                if console != nil and console.width != nil:
                    width = console.width
                let hr = string_repeat("─", width)
                push(result_lines, rich.style.render_styled(hr, rich.style.parse_style("dim")))
                continue

            # Unordered lists
            if startswith(lns, "- ") or startswith(lns, "* ") or startswith(lns, "+ "):
                let text = slice(lns, 2, len(lns))
                push(result_lines, "  " + rich.style.render_styled("•", rich.style.parse_style("cyan")) + " " + text)
                continue

            # Ordered lists
            if self._is_ordered_list(lns):
                let dot_idx = indexof(lns, ".")
                if dot_idx >= 0:
                    let num_part = slice(lns, 0, dot_idx)
                    let text = slice(lns, dot_idx + 2, len(lns))
                    push(result_lines, "  " + num_part + ". " + text)
                continue

            # Blockquotes
            if startswith(lns, "> "):
                let text = slice(lns, 2, len(lns))
                let rendered = rich.style.render_styled("│" + " ", rich.style.parse_style("dim")) + rich.style.render_styled(text, rich.style.parse_style("dim"))
                push(result_lines, rendered)
                continue

            # Bold / Italic / Code in inline text
            let processed = self._process_inline(line)
            push(result_lines, processed)

        return join(result_lines, chr(10))

    proc _count_leading(self, s, ch):
        let count = 0
        let len_s = len(s)
        while count < len_s and s[count] == ch:
            count = count + 1
        return count

    proc _is_ordered_list(self, s):
        let i = 0
        let len_s = len(s)
        while i < len_s:
            if s[i] >= "0" and s[i] <= "9":
                i = i + 1
            else:
                if s[i] == "." and i + 1 < len_s and s[i + 1] == " ":
                    return true
                return false
        return false

    proc _find_char(self, s, ch):
        return indexof(s, ch)

    proc _process_inline(self, text):
        # Optimization: Use array-push and join("") with native slice() and indexof()
        let res_parts = []
        let last_pos = 0
        let i = 0
        let len_text = len(text)

        while i < len_text:
            if text[i] == "*" and i + 1 < len_text and text[i + 1] == "*":
                let end_pos = self._find_next(text, "**", i + 2)
                if end_pos >= 0:
                    if i > last_pos:
                        push(res_parts, slice(text, last_pos, i))
                    let inner = slice(text, i + 2, end_pos)
                    push(res_parts, rich.style.render_styled(inner, rich.style.parse_style("bold")))
                    i = end_pos + 2
                    last_pos = i
                    continue
            # Italic *text*
            if text[i] == "*":
                let end_pos = self._find_next(text, "*", i + 1)
                if end_pos >= 0:
                    if i > last_pos:
                        push(res_parts, slice(text, last_pos, i))
                    let inner = slice(text, i + 1, end_pos)
                    push(res_parts, rich.style.render_styled(inner, rich.style.parse_style("italic")))
                    i = end_pos + 1
                    last_pos = i
                    continue
            # Inline code `text`
            if text[i] == "`":
                let end_pos = self._find_next(text, "`", i + 1)
                if end_pos >= 0:
                    if i > last_pos:
                        push(res_parts, slice(text, last_pos, i))
                    let inner = slice(text, i + 1, end_pos)
                    push(res_parts, rich.style.render_styled(inner, rich.style.parse_style("on bright_black")))
                    i = end_pos + 1
                    last_pos = i
                    continue
            # Links [text](url)
            if text[i] == "[":
                let close_bracket = self._find_next(text, "]", i + 1)
                if close_bracket >= 0 and close_bracket + 1 < len_text and text[close_bracket + 1] == "(":
                    let close_paren = self._find_next(text, ")", close_bracket + 2)
                    if close_paren >= 0:
                        if i > last_pos:
                            push(res_parts, slice(text, last_pos, i))
                        let link_text = slice(text, i + 1, close_bracket)
                        let link_url = slice(text, close_bracket + 2, close_paren)
                        push(res_parts, rich.style.render_styled(link_text, rich.style.parse_style("underline blue")))
                        i = close_paren + 1
                        last_pos = i
                        continue
            i = i + 1

        if last_pos == 0:
            return text
        if last_pos < len_text:
            push(res_parts, slice(text, last_pos, len_text))
        return join(res_parts, "")

    proc _find_next(self, text, substr, start):
        if start >= len(text):
            return -1
        let sub_str = slice(text, start, len(text))
        let idx = indexof(sub_str, substr)
        if idx >= 0:
            return start + idx
        return -1

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

# Parse markdown
proc parse_markdown(markup):
    return Markdown(markup, nil, true)
