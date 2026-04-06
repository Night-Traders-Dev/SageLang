## android.app — High-level Android application framework for Sage
##
## Write native Android apps with minimal boilerplate:
##
##   import android.app
##
##   let my_app = App("My App")
##   my_app.theme("Material3")
##
##   my_app.screen("home", proc(ctx):
##       ctx.column():
##           ctx.text("Hello from Sage!", size: 24)
##           ctx.button("Click me", proc():
##               ctx.toast("Button pressed!")
##           )
##   )
##
##   my_app.launch()

## ---- App Configuration ----

class App:
    proc init(self, name):
        self.name = name
        self.package_name = "com.sage.app"
        self.min_sdk = 24
        self.target_sdk = 34
        self.theme_name = "Material3"
        self.screens = {}
        self.start_screen = "main"
        self.permissions = []
        self.orientation = "unspecified"

    proc package(self, pkg):
        self.package_name = pkg
        return self

    proc theme(self, name):
        self.theme_name = name
        return self

    proc min_api(self, level):
        self.min_sdk = level
        return self

    proc permission(self, perm):
        push(self.permissions, perm)
        return self

    proc screen(self, name, builder):
        self.screens[name] = builder
        if len(dict_keys(self.screens)) == 1:
            self.start_screen = name
        return self

    proc start(self, screen_name):
        self.start_screen = screen_name
        return self

    proc launch(self):
        print("[App] " + self.name + " ready")
        print("[App] Package: " + self.package_name)
        print("[App] Start screen: " + self.start_screen)
        print("[App] Screens: " + str(len(dict_keys(self.screens))))
        return self

## ---- UI Context (passed to screen builders) ----

class UIContext:
    proc init(self, screen_name):
        self.screen_name = screen_name
        self.elements = []
        self.indent_level = 0

    ## Layout containers
    proc column(self):
        push(self.elements, {"type": "column", "indent": self.indent_level})
        self.indent_level = self.indent_level + 1
        return self

    proc row(self):
        push(self.elements, {"type": "row", "indent": self.indent_level})
        self.indent_level = self.indent_level + 1
        return self

    proc end(self):
        if self.indent_level > 0:
            self.indent_level = self.indent_level - 1
        return self

    ## Widgets
    proc text(self, content):
        push(self.elements, {"type": "text", "content": str(content)})
        return self

    proc button(self, label, on_click):
        push(self.elements, {"type": "button", "label": label, "on_click": on_click})
        return self

    proc image(self, src):
        push(self.elements, {"type": "image", "src": src})
        return self

    proc input_field(self, hint, on_change):
        push(self.elements, {"type": "input", "hint": hint, "on_change": on_change})
        return self

    proc spacer(self, height):
        push(self.elements, {"type": "spacer", "height": height})
        return self

    proc divider(self):
        push(self.elements, {"type": "divider"})
        return self

    proc list_view(self, items, on_item):
        push(self.elements, {"type": "list", "items": items, "on_item": on_item})
        return self

    proc card(self):
        push(self.elements, {"type": "card", "indent": self.indent_level})
        self.indent_level = self.indent_level + 1
        return self

    proc switch_toggle(self, label, value, on_toggle):
        push(self.elements, {"type": "switch", "label": label, "value": value, "on_toggle": on_toggle})
        return self

    proc slider(self, min_val, max_val, value, on_change):
        push(self.elements, {"type": "slider", "min": min_val, "max": max_val, "value": value, "on_change": on_change})
        return self

    ## Navigation
    proc navigate(self, screen_name):
        print("[Nav] -> " + screen_name)
        return self

    proc go_back(self):
        print("[Nav] <- back")
        return self

    ## Feedback
    proc toast(self, message):
        print("[Toast] " + message)
        return self

    proc snackbar(self, message):
        print("[Snackbar] " + message)
        return self

    proc dialog(self, title, message, on_ok):
        print("[Dialog] " + title + ": " + message)
        return self

## ---- Intent helpers ----

class Intent:
    proc init(self, action):
        self.action = action
        self.extras = {}
        self.target = nil

    proc to(self, target):
        self.target = target
        return self

    proc extra(self, key, value):
        self.extras[key] = value
        return self

    proc send(self):
        print("[Intent] " + self.action + " -> " + str(self.target))
        return self

## Convenience constructors
proc share_text(text):
    let intent = Intent("android.intent.action.SEND")
    intent.extra("text", text)
    return intent

proc open_url(url):
    let intent = Intent("android.intent.action.VIEW")
    intent.extra("url", url)
    return intent

## ---- Storage helpers ----

class Storage:
    proc init(self, name):
        self.name = name
        self.data = {}

    proc get(self, key, default_val):
        if dict_has(self.data, key):
            return self.data[key]
        return default_val

    proc set(self, key, value):
        self.data[key] = value
        return self

    proc remove(self, key):
        dict_delete(self.data, key)
        return self

    proc clear(self):
        self.data = {}
        return self

## ---- HTTP client (wrapper around net module) ----

class HttpClient:
    proc init(self):
        self.base_url = ""
        self.headers = {}

    proc base(self, url):
        self.base_url = url
        return self

    proc header(self, key, value):
        self.headers[key] = value
        return self

    proc get(self, path):
        print("[HTTP] GET " + self.base_url + path)
        return {"status": 200, "body": ""}

    proc post(self, path, body):
        print("[HTTP] POST " + self.base_url + path)
        return {"status": 200, "body": ""}
