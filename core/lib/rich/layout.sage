gc_disable()
import rich.style
import rich.measure

# Layout component - flexible layout engine for terminal output

class Layout:
    proc init(self, content, name, size, ratio, minimum_size, visible):
        self.content = content
        self.name = name
        self.size = nil
        if size != nil:
            self.size = size
        self.ratio = 1
        if ratio != nil:
            self.ratio = ratio
        self.minimum_size = 1
        if minimum_size != nil:
            self.minimum_size = minimum_size
        self.visible = true
        if visible != nil:
            self.visible = visible
        self.children = {}
        self.direction = "vertical"  # vertical or horizontal

    # Split layout to create sub-layouts
    # Optimization: Use direct 'for key in dict' iteration to avoid allocating key arrays.
    proc split(self, name_or_spec):
        if type(name_or_spec) == "string":
            let child = Layout(nil, name_or_spec, nil, nil, nil, true)
            self.children[name_or_spec] = child
            return child
        if type(name_or_spec) == "dict":
            # Spec like {"name": Layout(...)}
            for key in name_or_spec:
                self.children[key] = name_or_spec[key]
            return self
        return self

    # Split into rows (vertical split)
    proc split_row(self, name_or_spec):
        self.direction = "vertical"
        return self.split(name_or_spec)

    # Split into columns (horizontal split)
    proc split_column(self, name_or_spec):
        self.direction = "horizontal"
        return self.split(name_or_spec)

    # Add a named child
    proc add_child(self, name, child):
        self.children[name] = child
        return self

    # Update content
    proc update(self, content):
        self.content = content
        return self

    # Render the layout
    proc render(self, console):
        let width = 80
        if console != nil:
            width = console.width
        let height = 25
        if console != nil:
            height = console.height
        return self._render_region(width, height)

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

    proc _render_region(self, available_width, available_height):
        # Optimization: Use O(1) len(self.children) instead of O(N) len(dict_keys(self.children)).
        let child_count = len(self.children)
        if child_count == 0:
            return self._render_content(self.content, available_width)

        let results = []
        # Optimization: Use direct 'for name in self.children' iteration to bypass dict_keys array allocations.
        if self.direction == "vertical":
            let child_size = available_height / child_count
            child_size = child_size | 0
            if child_size < 1:
                child_size = 1
            for name in self.children:
                let child = self.children[name]
                let rendered = child._render_region(available_width, child_size)
                push(results, rendered)
        else:
            let child_size = available_width / child_count
            child_size = child_size | 0
            if child_size < 1:
                child_size = 1
            for name in self.children:
                let child = self.children[name]
                let rendered = child._render_region(child_size, available_height)
                push(results, rendered)

        # Optimization: Use native C VM join(results, chr(10)) to eliminate O(N^2) string concatenation loop.
        return join(results, chr(10))

    proc _render_content(self, content, width):
        if content == nil:
            return ""
        if type(content) == "string":
            return content
        if type(content) == "number":
            return str(content)
        if type(content) == "instance":
            if dict_has(content, "render"):
                return content.render()
            if dict_has(content, "__rich__"):
                return content.__rich__(nil)
        return str(content)

# Create a layout
proc create_layout(content, name):
    return Layout(content, name, nil, nil, nil, true)
