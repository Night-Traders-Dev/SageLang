## android.compose — Jetpack Compose-style declarative UI for Sage
##
## Provides a declarative component model that maps to Kotlin Compose code.
## When transpiled with --compile-android, these become actual Compose calls.
##
##   import android.compose
##
##   let counter = State(0)
##
##   proc CounterApp():
##       Column(padding: 16):
##           Text("Count: " + str(counter.get()), size: 32, bold: true)
##           Spacer(16)
##           Row(spacing: 8):
##               Button("-", proc(): counter.set(counter.get() - 1))
##               Button("+", proc(): counter.set(counter.get() + 1))

## ---- Reactive State ----

class State:
    proc init(self, initial):
        self.value = initial
        self.listeners = []

    proc get(self):
        return self.value

    proc set(self, new_value):
        self.value = new_value
        for listener in self.listeners:
            listener(new_value)
        return self

    proc observe(self, callback):
        push(self.listeners, callback)
        return self

    proc update(self, transform):
        self.value = transform(self.value)
        for listener in self.listeners:
            listener(self.value)
        return self

class ListState:
    proc init(self, items):
        self.items = items
        self.listeners = []

    proc get(self):
        return self.items

    proc add(self, item):
        push(self.items, item)
        return self

    proc remove(self, index):
        let new_items = []
        for i in range(len(self.items)):
            if i != index:
                push(new_items, self.items[i])
        self.items = new_items
        return self

    proc clear(self):
        self.items = []
        return self

## ---- Component Tree (builds a virtual UI tree) ----

class Component:
    proc init(self, type_name):
        self.type_name = type_name
        self.props = {}
        self.children = []

    proc prop(self, key, value):
        self.props[key] = value
        return self

    proc child(self, component):
        push(self.children, component)
        return self

    proc render(self):
        let result = "<" + self.type_name
        for key in dict_keys(self.props):
            result = result + " " + key + "=\"" + str(self.props[key]) + "\""
        if len(self.children) == 0:
            return result + " />"
        result = result + ">"
        for child in self.children:
            result = result + child.render()
        return result + "</" + self.type_name + ">"

## ---- Layout Composables ----

proc Column():
    return Component("Column")

proc Row():
    return Component("Row")

proc Box():
    return Component("Box")

proc LazyColumn():
    return Component("LazyColumn")

## ---- Widget Composables ----

proc Text(content):
    let c = Component("Text")
    c.prop("text", content)
    return c

proc Button(label, on_click):
    let c = Component("Button")
    c.prop("label", label)
    c.prop("onClick", on_click)
    return c

proc TextField(value, on_change):
    let c = Component("TextField")
    c.prop("value", value)
    c.prop("onChange", on_change)
    return c

proc Image(src):
    let c = Component("Image")
    c.prop("src", src)
    return c

proc Icon(name):
    let c = Component("Icon")
    c.prop("name", name)
    return c

proc Spacer(height):
    let c = Component("Spacer")
    c.prop("height", height)
    return c

proc Divider():
    return Component("Divider")

proc Card():
    return Component("Card")

proc Switch(checked, on_toggle):
    let c = Component("Switch")
    c.prop("checked", checked)
    c.prop("onToggle", on_toggle)
    return c

proc Slider(value, min_val, max_val, on_change):
    let c = Component("Slider")
    c.prop("value", value)
    c.prop("min", min_val)
    c.prop("max", max_val)
    c.prop("onChange", on_change)
    return c

proc CircularProgress():
    return Component("CircularProgress")

proc LinearProgress(progress):
    let c = Component("LinearProgress")
    c.prop("progress", progress)
    return c

## ---- Navigation ----

class NavController:
    proc init(self):
        self.stack = []
        self.current = nil

    proc navigate(self, route):
        if self.current != nil:
            push(self.stack, self.current)
        self.current = route
        return self

    proc pop(self):
        if len(self.stack) > 0:
            self.current = pop(self.stack)
        return self

    proc current_route(self):
        return self.current

## ---- Scaffold (top-level app structure) ----

proc Scaffold(title, content):
    let c = Component("Scaffold")
    c.prop("title", title)
    c.child(content)
    return c

proc TopBar(title):
    let c = Component("TopAppBar")
    c.prop("title", title)
    return c

proc BottomBar(items):
    let c = Component("BottomNavigation")
    c.prop("items", items)
    return c

proc FloatingButton(icon, on_click):
    let c = Component("FAB")
    c.prop("icon", icon)
    c.prop("onClick", on_click)
    return c
