gc_disable()
import rich.style
import rich.measure

# Layout component - flexible layout engine for terminal output

class Layout:
    proc init(self, content, name, size, ratio, minimum_size, visible):
        self.content = content
        self.name = name
        self.size = size if size != nil else nil
        self.ratio = ratio if ratio != nil else 1
        self.minimum_size = minimum_size if minimum_size != nil else 1
        self.visible = visible if visible != nil else true
        self.children = {}
        self.direction = "vertical"  # vertical or horizontal

    # Split layout to create sub-layouts
    proc split(self, name_or_spec):
        if type(name_or_spec) == "string":
            let child = Layout(nil, name_or_spec, nil, nil, nil, true)
            self.children[name_or_spec] = child
            return child
        if type(name_or_spec) == "dict":
            # Spec like {"name": Layout(...)}
            let keys = dict_keys(name_or_spec)
            for i in range(len(keys)):
                self.children[keys[i]] = name_or_spec[keys[i]]
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
        let width = console.width if console != nil else 80
        let height = console.height if console != nil else 25
        return self._render_region(width, height)

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

    proc _render_region(self, available_width, available_height):
        let child_count = len(dict_keys(self.children))
        if child_count == 0:
            return self._render_content(self.content, available_width)

        let results = []
        if self.direction == "vertical":
            let child_size = available_height / child_count
            child_size = child_size | 0
            if child_size < 1:
                child_size = 1
            let keys = dict_keys(self.children)
            for i in range(len(keys)):
                let child = self.children[keys[i]]
                let rendered = child._render_region(available_width, child_size)
                push(results, rendered)
        else:
            let child_size = available_width / child_count
            child_size = child_size | 0
            if child_size < 1:
                child_size = 1
            let keys = dict_keys(self.children)
            for i in range(len(keys)):
                let child = self.children[keys[i]]
                let rendered = child._render_region(child_size, available_height)
                push(results, rendered)

        let result = ""
        for i in range(len(results)):
            if i > 0:
                result = result + chr(10)
            result = result + results[i]
        return result

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
