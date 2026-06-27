gc_disable()
import rich.style
import rich.text
import rich.measure

# Padding component - add spacing around content

class Padding:
    proc init(self, renderable, top, right, bottom, left, pad, expand, style):
        if pad != nil:
            if type(pad) == "number":
                top = pad
                right = pad
                bottom = pad
                left = pad
            if type(pad) == "array":
                if len(pad) >= 1:
                    top = pad[0]
                if len(pad) >= 2:
                    right = pad[1]
                if len(pad) >= 3:
                    bottom = pad[2]
                if len(pad) >= 4:
                    left = pad[3]
        self.renderable = renderable
        self.top = top if top != nil else 0
        self.right = right if right != nil else 0
        self.bottom = bottom if bottom != nil else 0
        self.left = left if left != nil else 0
        self.expand = expand if expand != nil else true
        self.style = style if style != nil else nil

    proc render(self, console):
        let content = self._render_content(self.renderable)
        let lines = split(content, chr(10))

        let result_lines = []

        # Top padding
        for i in range(self.top):
            push(result_lines, "")

        # Content with left/right padding
        let left_pad = ""
        for i in range(self.left):
            left_pad = left_pad + " "
        let right_pad = ""
        for i in range(self.right):
            right_pad = right_pad + " "

        for i in range(len(lines)):
            push(result_lines, left_pad + lines[i] + right_pad)

        # Bottom padding
        for i in range(self.bottom):
            push(result_lines, "")

        let result = ""
        for i in range(len(result_lines)):
            if i > 0:
                result = result + chr(10)
            result = result + result_lines[i]
        return result

    proc _render_content(self, obj):
        if obj == nil:
            return ""
        if type(obj) == "string":
            return obj
        if type(obj) == "number":
            return str(obj)
        if type(obj) == "instance":
            if dict_has(obj, "render"):
                return obj.render()
            if dict_has(obj, "__rich__"):
                return obj.__rich__(nil)
        return str(obj)

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

# Create padding
proc create_padding(renderable, pad, top, right, bottom, left):
    return Padding(renderable, top, right, bottom, left, pad, true, nil)
