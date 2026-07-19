gc_disable()
import rich.style
import rich.text
import rich.measure

# Tree rendering component

class Tree:
    proc init(self, label, style, guide_style, highlight):
        self.label = label
        self.style = nil
        if style != nil:
            self.style = style
        self.guide_style = "dim"
        if guide_style != nil:
            self.guide_style = guide_style
        self.highlight = false
        if highlight != nil:
            self.highlight = highlight
        self.children = []
        self._expanded = true

    # Add a child tree node
    proc add(self, label, style):
        let child = Tree(label, style, self.guide_style, false)
        push(self.children, child)
        return child

    # Add text as a leaf
    proc add_text(self, text):
        let child = Tree(text, nil, self.guide_style, false)
        push(self.children, child)
        return child

    # Render the tree
    proc render(self, console):
        let result = self._render_tree("", "", true)
        return result

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

    proc _render_tree(self, prefix, indent, is_root):
        let guide = "│"  # |
        let branch = "├"  # |
        let last_branch = "└"  # |
        let horiz = "─"  # -
        let result = ""

        if is_root:
            let label_str = str(self.label)
            result = result + label_str
        else:
            let connector = branch
            if len(self.children) == 0:
                connector = last_branch
            result = result + indent + connector + horiz + horiz + " " + str(self.label)
            if len(self.children) > 0:
                indent = indent + guide + "   "
            else:
                indent = indent + "    "

        result = result + chr(10)

        for i in range(len(self.children)):
            let child = self.children[i]
            let child_result = child._render_subtree(indent, i == len(self.children) - 1)
            result = result + child_result

        return result

    proc _render_subtree(self, indent, is_last):
        let guide = "│"
        let branch = "├"
        let last_branch = "└"
        let horiz = "─"
        let result = ""

        let connector = branch
        if is_last:
            connector = last_branch
        result = result + indent + connector + horiz + horiz + " " + str(self.label) + chr(10)

        if is_last:
            indent = indent + "    "
        else:
            indent = indent + guide + "   "

        for i in range(len(self.children)):
            let child = self.children[i]
            let child_result = child._render_subtree(indent, i == len(self.children) - 1)
            result = result + child_result

        return result

# Create a tree from a label
proc create_tree(label, style):
    return Tree(label, style, nil, false)
