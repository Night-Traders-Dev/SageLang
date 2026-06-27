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
    single_box["top_left"] = chr(9484)
    single_box["top"] = chr(9472)
    single_box["top_right"] = chr(9488)
    single_box["right"] = chr(9474)
    single_box["bottom_right"] = chr(9496)
    single_box["bottom"] = chr(9472)
    single_box["bottom_left"] = chr(9492)
    single_box["left"] = chr(9474)
    single_box["mid_top"] = chr(9516)
    single_box["mid_bottom"] = chr(9524)
    single_box["mid_left"] = chr(9500)
    single_box["mid_right"] = chr(9508)
    single_box["mid"] = chr(9532)
    single_box["title_left"] = chr(9500)
    single_box["title_right"] = chr(9508)
    boxes["single"] = single_box
    boxes["square"] = single_box

    # Double line box
    let double_box = {}
    double_box["top_left"] = chr(9556)
    double_box["top"] = chr(9552)
    double_box["top_right"] = chr(9559)
    double_box["right"] = chr(9553)
    double_box["bottom_right"] = chr(9565)
    double_box["bottom"] = chr(9552)
    double_box["bottom_left"] = chr(9562)
    double_box["left"] = chr(9553)
    double_box["mid_top"] = chr(9574)
    double_box["mid_bottom"] = chr(9577)
    double_box["mid_left"] = chr(9568)
    double_box["mid_right"] = chr(9571)
    double_box["mid"] = chr(9580)
    double_box["title_left"] = chr(9568)
    double_box["title_right"] = chr(9571)
    boxes["double"] = double_box

    # Rounded box
    let round_box = {}
    round_box["top_left"] = chr(9581)
    round_box["top"] = chr(9472)
    round_box["top_right"] = chr(9582)
    round_box["right"] = chr(9474)
    round_box["bottom_right"] = chr(9584)
    round_box["bottom"] = chr(9472)
    round_box["bottom_left"] = chr(9583)
    round_box["left"] = chr(9474)
    round_box["mid_top"] = chr(9516)
    round_box["mid_bottom"] = chr(9524)
    round_box["mid_left"] = chr(9500)
    round_box["mid_right"] = chr(9508)
    round_box["mid"] = chr(9532)
    round_box["title_left"] = chr(9500)
    round_box["title_right"] = chr(9508)
    boxes["round"] = round_box
    boxes["rounded"] = round_box

    # Heavy box
    let heavy_box = {}
    heavy_box["top_left"] = chr(9491)
    heavy_box["top"] = chr(9473)
    heavy_box["top_right"] = chr(9487)
    heavy_box["right"] = chr(9475)
    heavy_box["bottom_right"] = chr(9495)
    heavy_box["bottom"] = chr(9473)
    heavy_box["bottom_left"] = chr(9499)
    heavy_box["left"] = chr(9475)
    heavy_box["mid_top"] = chr(9483)
    heavy_box["mid_bottom"] = chr(9482)
    heavy_box["mid_left"] = chr(9506)
    heavy_box["mid_right"] = chr(9507)
    heavy_box["mid"] = chr(9547)
    heavy_box["title_left"] = chr(9506)
    heavy_box["title_right"] = chr(9507)
    boxes["heavy"] = heavy_box

    # Double-single mixed (top/bottom double, sides single)
    let double_single = {}
    double_single["top_left"] = chr(9556)
    double_single["top"] = chr(9552)
    double_single["top_right"] = chr(9559)
    double_single["right"] = chr(9474)
    double_single["bottom_right"] = chr(9565)
    double_single["bottom"] = chr(9552)
    double_single["bottom_left"] = chr(9562)
    double_single["left"] = chr(9474)
    double_single["mid_top"] = chr(9574)
    double_single["mid_bottom"] = chr(9577)
    double_single["mid_left"] = chr(9568)
    double_single["mid_right"] = chr(9571)
    double_single["mid"] = chr(9580)
    boxes["double_single"] = double_single

    # Minimal box (just horizontal lines, minimal vertical)
    let minimal_box = {}
    minimal_box["top_left"] = " "
    minimal_box["top"] = " "
    minimal_box["top_right"] = " "
    minimal_box["right"] = " "
    minimal_box["bottom_right"] = " "
    minimal_box["bottom"] = chr(9472)
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
    simple_box["top"] = chr(9472)
    simple_box["top_right"] = " "
    simple_box["right"] = " "
    simple_box["bottom_right"] = " "
    simple_box["bottom"] = chr(9472)
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
    simple_heavy_box["top"] = chr(9473)
    simple_heavy_box["top_right"] = " "
    simple_heavy_box["right"] = chr(9474)
    simple_heavy_box["bottom_right"] = " "
    simple_heavy_box["bottom"] = chr(9473)
    simple_heavy_box["bottom_left"] = " "
    simple_heavy_box["left"] = chr(9474)
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
