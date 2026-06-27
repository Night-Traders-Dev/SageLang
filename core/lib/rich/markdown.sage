gc_disable()
import rich.style
import rich.text
import rich.measure

# Markdown rendering (simplified subset)

class Markdown:
    proc init(self, markup, code_theme, hyperlinks):
        self.markup = markup
        self.code_theme = code_theme if code_theme != nil else "monokai"
        self.hyperlinks = hyperlinks if hyperlinks != nil else true

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
                    code_lang = ""
                    let remain = ""
                    for j in range(len(line) - 3):
                        remain = remain + line[3 + j]
                    code_lang = strip(remain)
                    continue

            if in_code_block:
                push(result_lines, "  " + line)
                continue

            # Headers
            if self._count_leading(lns, "#") > 0:
                let level = self._count_leading(lns, "#")
                if level > 0 and len(lns) > level and lns[level] == " ":
                    let text = ""
                    for j in range(len(lns) - level - 1):
                        text = text + lns[level + 1 + j]
                    let style_str = "markdown.h" + str(level)
                    let rendered = rich.style.render_styled(text, rich.style.parse_style("bold"))
                    push(result_lines, rendered)
                    push(result_lines, "")
                    continue

            # Horizontal rules
            if lns == "---" or lns == "***" or lns == "___":
                let hr = ""
                let width = 80 if console == nil else console.width
                for j in range(width):
                    hr = hr + chr(9472)
                push(result_lines, rich.style.render_styled(hr, rich.style.parse_style("dim")))
                continue

            # Unordered lists
            if startswith(lns, "- ") or startswith(lns, "* ") or startswith(lns, "+ "):
                let text = ""
                for j in range(len(lns) - 2):
                    text = text + lns[2 + j]
                push(result_lines, "  " + rich.style.render_styled(chr(8226), rich.style.parse_style("cyan")) + " " + text)
                continue

            # Ordered lists
            if self._is_ordered_list(lns):
                let dot_idx = self._find_char(lns, ".")
                if dot_idx >= 0:
                    let num_part = ""
                    for j in range(dot_idx):
                        num_part = num_part + lns[j]
                    let text = ""
                    for j in range(len(lns) - dot_idx - 2):
                        text = text + lns[dot_idx + 2 + j]
                    push(result_lines, "  " + num_part + ". " + text)
                continue

            # Blockquotes
            if startswith(lns, "> "):
                let text = ""
                for j in range(len(lns) - 2):
                    text = text + lns[2 + j]
                let rendered = rich.style.render_styled(chr(9474) + " ", rich.style.parse_style("dim")) + rich.style.render_styled(text, rich.style.parse_style("dim"))
                push(result_lines, rendered)
                continue

            # Bold / Italic / Code in inline text
            let processed = self._process_inline(line)
            push(result_lines, processed)

        let result = ""
        for i in range(len(result_lines)):
            if i > 0:
                result = result + chr(10)
            result = result + result_lines[i]
        return result

    proc _count_leading(self, s, ch):
        let count = 0
        while count < len(s) and s[count] == ch:
            count = count + 1
        return count

    proc _is_ordered_list(self, s):
        let i = 0
        while i < len(s):
            if s[i] >= "0" and s[i] <= "9":
                i = i + 1
            else:
                if s[i] == "." and i + 1 < len(s) and s[i + 1] == " ":
                    return true
                return false
        return false

    proc _find_char(self, s, ch):
        for i in range(len(s)):
            if s[i] == ch:
                return i
        return -1

    proc _process_inline(self, text):
        # Handle bold **text**
        let result = ""
        let i = 0
        while i < len(text):
            if text[i] == "*" and i + 1 < len(text) and text[i + 1] == "*":
                let end_pos = self._find_next(text, "**", i + 2)
                if end_pos >= 0:
                    let inner = ""
                    for j in range(end_pos - i - 2):
                        inner = inner + text[i + 2 + j]
                    result = result + rich.style.render_styled(inner, rich.style.parse_style("bold"))
                    i = end_pos + 2
                    continue
            # Italic *text*
            if text[i] == "*":
                let end_pos = self._find_next(text, "*", i + 1)
                if end_pos >= 0:
                    let inner = ""
                    for j in range(end_pos - i - 1):
                        inner = inner + text[i + 1 + j]
                    result = result + rich.style.render_styled(inner, rich.style.parse_style("italic"))
                    i = end_pos + 1
                    continue
            # Inline code `text`
            if text[i] == "`":
                let end_pos = self._find_next(text, "`", i + 1)
                if end_pos >= 0:
                    let inner = ""
                    for j in range(end_pos - i - 1):
                        inner = inner + text[i + 1 + j]
                    result = result + rich.style.render_styled(inner, rich.style.parse_style("on bright_black"))
                    i = end_pos + 1
                    continue
            # Links [text](url)
            if text[i] == "[":
                let close_bracket = self._find_next(text, "]", i + 1)
                if close_bracket >= 0 and close_bracket + 1 < len(text) and text[close_bracket + 1] == "(":
                    let close_paren = self._find_next(text, ")", close_bracket + 2)
                    if close_paren >= 0:
                        let link_text = ""
                        for j in range(close_bracket - i - 1):
                            link_text = link_text + text[i + 1 + j]
                        let link_url = ""
                        for j in range(close_paren - close_bracket - 2):
                            link_url = link_url + text[close_bracket + 2 + j]
                        result = result + rich.style.render_styled(link_text, rich.style.parse_style("underline blue"))
                        i = close_paren + 1
                        continue
            result = result + text[i]
            i = i + 1
        return result

    proc _find_next(self, text, substr, start):
        let slen = len(substr)
        for i in range(len(text) - slen - start + 1):
            let match = true
            for j in range(slen):
                if text[start + i + j] != substr[j]:
                    match = false
            if match:
                return start + i
        return -1

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

# Parse markdown
proc parse_markdown(markup):
    return Markdown(markup, nil, true)
