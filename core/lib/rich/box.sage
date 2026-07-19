gc_disable()
# Box drawing characters and border styles for panels/tables

# Box drawing character sets using Unicode
proc create_box_sets():
    let boxes = {}

    # ASCII box (uses only ASCII characters)
    let ascii_box = {}
    ascii_box["top_left"] = "+"
    ascii_box["top"] = "-"
    ascii_box["top_right"] = "+"
    ascii_box["right"] = "|"
    ascii_box["bottom_right"] = "+"
    ascii_box["bottom"] = "-"
    ascii_box["bottom_left"] = "+"
    ascii_box["left"] = "|"
    ascii_box["mid_top"] = "+"
    ascii_box["mid_bottom"] = "+"
    ascii_box["mid_left"] = "+"
    ascii_box["mid_right"] = "+"
    ascii_box["mid"] = "+"
    ascii_box["title_left"] = "+"
    ascii_box["title_right"] = "+"
    boxes["ascii"] = ascii_box

    # Single line box
    let single_box = {}
    single_box["top_left"] = "┌"
    single_box["top"] = "─"
    single_box["top_right"] = "┐"
    single_box["right"] = "│"
    single_box["bottom_right"] = "┘"
    single_box["bottom"] = "─"
    single_box["bottom_left"] = "└"
    single_box["left"] = "│"
    single_box["mid_top"] = "┬"
    single_box["mid_bottom"] = "┴"
    single_box["mid_left"] = "├"
    single_box["mid_right"] = "┤"
    single_box["mid"] = "┼"
    single_box["title_left"] = "├"
    single_box["title_right"] = "┤"
    boxes["single"] = single_box
    boxes["square"] = single_box

    # Double line box
    let double_box = {}
    double_box["top_left"] = "╔"
    double_box["top"] = "═"
    double_box["top_right"] = "╗"
    double_box["right"] = "║"
    double_box["bottom_right"] = "╝"
    double_box["bottom"] = "═"
    double_box["bottom_left"] = "╚"
    double_box["left"] = "║"
    double_box["mid_top"] = "╦"
    double_box["mid_bottom"] = "╩"
    double_box["mid_left"] = "╠"
    double_box["mid_right"] = "╣"
    double_box["mid"] = "╬"
    double_box["title_left"] = "╠"
    double_box["title_right"] = "╣"
    boxes["double"] = double_box

    # Rounded box
    let round_box = {}
    round_box["top_left"] = "╭"
    round_box["top"] = "─"
    round_box["top_right"] = "╮"
    round_box["right"] = "│"
    round_box["bottom_right"] = "╰"
    round_box["bottom"] = "─"
    round_box["bottom_left"] = "╯"
    round_box["left"] = "│"
    round_box["mid_top"] = "┬"
    round_box["mid_bottom"] = "┴"
    round_box["mid_left"] = "├"
    round_box["mid_right"] = "┤"
    round_box["mid"] = "┼"
    round_box["title_left"] = "├"
    round_box["title_right"] = "┤"
    boxes["round"] = round_box
    boxes["rounded"] = round_box

    # Heavy box
    let heavy_box = {}
    heavy_box["top_left"] = "┓"
    heavy_box["top"] = "━"
    heavy_box["top_right"] = "┏"
    heavy_box["right"] = "┃"
    heavy_box["bottom_right"] = "┗"
    heavy_box["bottom"] = "━"
    heavy_box["bottom_left"] = "┛"
    heavy_box["left"] = "┃"
    heavy_box["mid_top"] = "┋"
    heavy_box["mid_bottom"] = "┊"
    heavy_box["mid_left"] = "┢"
    heavy_box["mid_right"] = "┣"
    heavy_box["mid"] = "╋"
    heavy_box["title_left"] = "┢"
    heavy_box["title_right"] = "┣"
    boxes["heavy"] = heavy_box

    # Double-single mixed (top/bottom double, sides single)
    let double_single = {}
    double_single["top_left"] = "╔"
    double_single["top"] = "═"
    double_single["top_right"] = "╗"
    double_single["right"] = "│"
    double_single["bottom_right"] = "╝"
    double_single["bottom"] = "═"
    double_single["bottom_left"] = "╚"
    double_single["left"] = "│"
    double_single["mid_top"] = "╦"
    double_single["mid_bottom"] = "╩"
    double_single["mid_left"] = "╠"
    double_single["mid_right"] = "╣"
    double_single["mid"] = "╬"
    boxes["double_single"] = double_single

    # Minimal box (just horizontal lines, minimal vertical)
    let minimal_box = {}
    minimal_box["top_left"] = " "
    minimal_box["top"] = " "
    minimal_box["top_right"] = " "
    minimal_box["right"] = " "
    minimal_box["bottom_right"] = " "
    minimal_box["bottom"] = "─"
    minimal_box["bottom_left"] = " "
    minimal_box["left"] = " "
    minimal_box["mid_top"] = " "
    minimal_box["mid_bottom"] = " "
    minimal_box["mid_left"] = " "
    minimal_box["mid_right"] = " "
    minimal_box["mid"] = " "
    boxes["minimal"] = minimal_box

    # Simple box (top/bottom lines only, no vertical)
    let simple_box = {}
    simple_box["top_left"] = " "
    simple_box["top"] = "─"
    simple_box["top_right"] = " "
    simple_box["right"] = " "
    simple_box["bottom_right"] = " "
    simple_box["bottom"] = "─"
    simple_box["bottom_left"] = " "
    simple_box["left"] = " "
    simple_box["mid_top"] = " "
    simple_box["mid_bottom"] = " "
    simple_box["mid_left"] = " "
    simple_box["mid_right"] = " "
    simple_box["mid"] = " "
    boxes["simple"] = simple_box
    boxes["horizontals"] = simple_box

    # Simple-heavy (heavy horizontal, light vertical)
    let simple_heavy_box = {}
    simple_heavy_box["top_left"] = " "
    simple_heavy_box["top"] = "━"
    simple_heavy_box["top_right"] = " "
    simple_heavy_box["right"] = "│"
    simple_heavy_box["bottom_right"] = " "
    simple_heavy_box["bottom"] = "━"
    simple_heavy_box["bottom_left"] = " "
    simple_heavy_box["left"] = "│"
    simple_heavy_box["mid_top"] = " "
    simple_heavy_box["mid_bottom"] = " "
    simple_heavy_box["mid_left"] = " "
    simple_heavy_box["mid_right"] = " "
    simple_heavy_box["mid"] = " "
    boxes["simple_heavy"] = simple_heavy_box

    # Markdown-style box (uses pipe and dash)
    let markdown_box = {}
    markdown_box["top_left"] = ""
    markdown_box["top"] = ""
    markdown_box["top_right"] = ""
    markdown_box["right"] = "|"
    markdown_box["bottom_right"] = ""
    markdown_box["bottom"] = ""
    markdown_box["bottom_left"] = ""
    markdown_box["left"] = "|"
    markdown_box["mid_top"] = ""
    markdown_box["mid_bottom"] = ""
    markdown_box["mid_left"] = ""
    markdown_box["mid_right"] = ""
    markdown_box["mid"] = ""
    boxes["markdown"] = markdown_box

    return boxes

let BOX_SETS = create_box_sets()

proc get_box(name):
    if name == nil:
        return BOX_SETS["single"]
    let lname = lower(name)
    if dict_has(BOX_SETS, lname):
        return BOX_SETS[lname]
    return BOX_SETS["single"]

proc map_box():
    return ["ascii", "single", "square", "double", "round", "rounded", "heavy",
            "double_single", "minimal", "simple", "horizontals", "simple_heavy", "markdown"]

# Box class for custom border definitions
class Box:
    proc init(self, name):
        self.name = name
        self._box = get_box(name)

    proc get_edge(self, edge_name):
        return self._box[edge_name]
