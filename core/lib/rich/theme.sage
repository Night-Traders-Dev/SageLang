gc_disable()
import rich.color

# Theme system - named style collections for consistent terminal theming

# Create a theme with a name and style definitions
proc Theme(name, styles):
    let theme = {}
    theme["name"] = name
    theme["styles"] = {}
    if styles != nil:
        theme["styles"] = styles
    return theme

# Get a style by name from the theme
proc get_theme_style(theme, name):
    if theme == nil:
        return nil
    if dict_has(theme["styles"], name):
        return theme["styles"][name]
    return nil

# Register a style in the theme
proc set_theme_style(theme, name, style):
    theme["styles"][name] = style
    return theme

# --- Built-in themes ---

proc create_default_theme():
    let styles = {}
    styles["warning"] = "bold yellow"
    styles["error"] = "bold red"
    styles["info"] = "bold blue"
    styles["success"] = "bold green"
    styles["debug"] = "dim"
    styles["trace"] = "dim"
    styles["repr.string"] = "green"
    styles["repr.number"] = "cyan"
    styles["repr.bool_true"] = "bold green"
    styles["repr.bool_false"] = "bold red"
    styles["repr.none"] = "dim italic"
    styles["repr.url"] = "underline blue"
    styles["repr.path"] = "underline"
    styles["repr.filename"] = "bright_magenta"
    styles["repr.call"] = "bright_blue"
    styles["repr.attrib_name"] = "yellow"
    styles["repr.attrib_value"] = "green"
    styles["repr.heading"] = "bold"
    styles["repr.tag"] = "bright_cyan"
    styles["bar.back"] = bright_black_style()
    styles["bar.complete"] = green_style()
    styles["bar.finished"] = bright_green_style()
    styles["bar.pulse"] = bright_blue_style()
    styles["bar.error"] = red_style()
    styles["progress.percentage"] = cyan_style()
    styles["progress.elapsed"] = dim_style()
    styles["progress.remaining"] = dim_style()
    styles["progress.data.speed"] = yellow_style()
    styles["table.header"] = "bold white"
    styles["table.border"] = blue_style()
    styles["table.row"] = ""
    styles["table.footer"] = "bold"
    styles["table.caption"] = "italic dim"
    styles["tree.line"] = dim_style()
    styles["tree.guide"] = dim_style()
    styles["tree.branch"] = bright_blue_style()
    styles["markdown.h1"] = "bold bright_cyan"
    styles["markdown.h2"] = "bold bright_blue"
    styles["markdown.h3"] = "bold cyan"
    styles["markdown.h4"] = "bold blue"
    styles["markdown.code"] = "on bright_black cyan"
    styles["markdown.block_code"] = "on bright_black"
    styles["markdown.link"] = "underline blue"
    styles["markdown.em"] = "italic"
    styles["markdown.strong"] = "bold"
    styles["markdown.item"] = cyan_style()
    styles["markdown.hr"] = dim_style()
    styles["markdown.quote"] = dim_style()
    styles["json.key"] = bright_cyan_style()
    styles["json.string"] = green_style()
    styles["json.number"] = cyan_style()
    styles["json.bool_true"] = bright_green_style()
    styles["json.bool_false"] = bright_red_style()
    styles["json.null"] = dim_style()
    styles["json.bracket"] = white_style()
    return Theme("default", styles)

proc create_light_theme():
    let theme = create_default_theme()
    theme["name"] = "light"
    let styles = theme["styles"]
    styles["repr.string"] = "dark_green"
    styles["repr.number"] = "dark_cyan"
    styles["table.border"] = "blue"
    styles["markdown.code"] = "on bright_black"
    return theme

proc create_noir_theme():
    let theme = create_default_theme()
    theme["name"] = "noir"
    return theme

# Helper functions to create style strings

proc white_style():
    return "white"

proc black_style():
    return "black"

proc dim_style():
    return "dim"

proc bold_style():
    return "bold"

proc cyan_style():
    return "cyan"

proc bright_cyan_style():
    return "bright_cyan"

proc blue_style():
    return "blue"

proc bright_blue_style():
    return "bright_blue"

proc green_style():
    return "green"

proc bright_green_style():
    return "bright_green"

proc yellow_style():
    return "yellow"

proc bright_yellow_style():
    return "bright_yellow"

proc red_style():
    return "red"

proc bright_red_style():
    return "bright_red"

proc magenta_style():
    return "magenta"

proc bright_magenta_style():
    return "bright_magenta"

proc bright_black_style():
    return "bright_black"

# Create a theme with name
proc create_theme(name):
    if name == "default" or name == "dark":
        return create_default_theme()
    if name == "light":
        return create_light_theme()
    if name == "noir":
        return create_noir_theme()
    return create_default_theme()
