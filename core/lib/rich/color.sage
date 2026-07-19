gc_disable()
# ANSI color system for terminal output
# Supports 3-bit, 4-bit, 8-bit (256-color), and 24-bit truecolor

# Color type constants
let COLOR_TYPE_STANDARD = 1
let COLOR_TYPE_256 = 2
let COLOR_TYPE_TRUECOLOR = 3

# Standard ANSI color numbers
let ANSI_BLACK = 0
let ANSI_RED = 1
let ANSI_GREEN = 2
let ANSI_YELLOW = 3
let ANSI_BLUE = 4
let ANSI_MAGENTA = 5
let ANSI_CYAN = 6
let ANSI_WHITE = 7
let ANSI_BRIGHT_BLACK = 8
let ANSI_BRIGHT_RED = 9
let ANSI_BRIGHT_GREEN = 10
let ANSI_BRIGHT_YELLOW = 11
let ANSI_BRIGHT_BLUE = 12
let ANSI_BRIGHT_MAGENTA = 13
let ANSI_BRIGHT_CYAN = 14
let ANSI_BRIGHT_WHITE = 15

let ANSI_DEFAULT = -1

# Named color map (lowercase -> number or tuple)
proc create_named_colors():
    let colors = {}
    # Standard 16 ANSI colors
    colors["black"] = ANSI_BLACK
    colors["red"] = ANSI_RED
    colors["green"] = ANSI_GREEN
    colors["yellow"] = ANSI_YELLOW
    colors["blue"] = ANSI_BLUE
    colors["magenta"] = ANSI_MAGENTA
    colors["cyan"] = ANSI_CYAN
    colors["white"] = ANSI_WHITE
    colors["bright_black"] = ANSI_BRIGHT_BLACK
    colors["bright_red"] = ANSI_BRIGHT_RED
    colors["bright_green"] = ANSI_BRIGHT_GREEN
    colors["bright_yellow"] = ANSI_BRIGHT_YELLOW
    colors["bright_blue"] = ANSI_BRIGHT_BLUE
    colors["bright_magenta"] = ANSI_BRIGHT_MAGENTA
    colors["bright_cyan"] = ANSI_BRIGHT_CYAN
    colors["bright_white"] = ANSI_BRIGHT_WHITE
    # Grey aliases
    colors["grey0"] = 0
    colors["grey3"] = 232
    colors["grey7"] = 233
    colors["grey11"] = 234
    colors["grey15"] = 235
    colors["grey19"] = 236
    colors["grey23"] = 237
    colors["grey27"] = 238
    colors["grey30"] = 239
    colors["grey35"] = 240
    colors["grey39"] = 241
    colors["grey42"] = 242
    colors["grey46"] = 243
    colors["grey50"] = 244
    colors["grey54"] = 245
    colors["grey58"] = 246
    colors["grey62"] = 247
    colors["grey66"] = 248
    colors["grey70"] = 249
    colors["grey74"] = 250
    colors["grey78"] = 251
    colors["grey82"] = 252
    colors["grey85"] = 253
    colors["grey89"] = 254
    colors["grey93"] = 255
    # Common named X11 colors (RGB tuples)
    colors["indian_red"] = [205, 92, 92]
    colors["light_coral"] = [240, 128, 128]
    colors["salmon"] = [250, 128, 114]
    colors["dark_salmon"] = [233, 150, 122]
    colors["light_salmon"] = [255, 160, 122]
    colors["crimson"] = [220, 20, 60]
    colors["fire_brick"] = [178, 34, 34]
    colors["dark_red"] = [139, 0, 0]
    colors["pink"] = [255, 192, 203]
    colors["light_pink"] = [255, 182, 193]
    colors["hot_pink"] = [255, 105, 180]
    colors["deep_pink"] = [255, 20, 147]
    colors["medium_violet_red"] = [199, 21, 133]
    colors["pale_violet_red"] = [219, 112, 147]
    colors["coral"] = [255, 127, 80]
    colors["tomato"] = [255, 99, 71]
    colors["orange_red"] = [255, 69, 0]
    colors["dark_orange"] = [255, 140, 0]
    colors["orange"] = [255, 165, 0]
    colors["gold"] = [255, 215, 0]
    colors["light_yellow"] = [255, 255, 224]
    colors["lemon_chiffon"] = [255, 250, 205]
    colors["light_goldenrod_yellow"] = [250, 250, 210]
    colors["papaya_whip"] = [255, 239, 213]
    colors["moccasin"] = [255, 228, 181]
    colors["peach_puff"] = [255, 218, 185]
    colors["pale_goldenrod"] = [238, 232, 170]
    colors["khaki"] = [240, 230, 140]
    colors["dark_khaki"] = [189, 183, 107]
    colors["lavender"] = [230, 230, 250]
    colors["thistle"] = [216, 191, 216]
    colors["plum"] = [221, 160, 221]
    colors["violet"] = [238, 130, 238]
    colors["orchid"] = [218, 112, 214]
    colors["medium_orchid"] = [186, 85, 211]
    colors["medium_purple"] = [147, 112, 219]
    colors["blue_violet"] = [138, 43, 226]
    colors["dark_violet"] = [148, 0, 211]
    colors["dark_orchid"] = [153, 50, 204]
    colors["dark_magenta"] = [139, 0, 139]
    colors["purple"] = [128, 0, 128]
    colors["indigo"] = [75, 0, 130]
    colors["slate_blue"] = [106, 90, 205]
    colors["dark_slate_blue"] = [72, 61, 139]
    colors["medium_slate_blue"] = [123, 104, 238]
    colors["green_yellow"] = [173, 255, 47]
    colors["chartreuse"] = [127, 255, 0]
    colors["lawn_green"] = [124, 252, 0]
    colors["lime"] = [0, 255, 0]
    colors["lime_green"] = [50, 205, 50]
    colors["pale_green"] = [152, 251, 152]
    colors["light_green"] = [144, 238, 144]
    colors["medium_spring_green"] = [0, 250, 154]
    colors["spring_green"] = [0, 255, 127]
    colors["medium_sea_green"] = [60, 179, 113]
    colors["sea_green"] = [46, 139, 87]
    colors["forest_green"] = [34, 139, 34]
    colors["dark_green"] = [0, 100, 0]
    colors["yellow_green"] = [154, 205, 50]
    colors["olive_drab"] = [107, 142, 35]
    colors["olive"] = [128, 128, 0]
    colors["dark_olive_green"] = [85, 107, 47]
    colors["medium_aquamarine"] = [102, 205, 170]
    colors["dark_sea_green"] = [143, 188, 143]
    colors["light_sea_green"] = [32, 178, 170]
    colors["dark_cyan"] = [0, 139, 139]
    colors["teal"] = [0, 128, 128]
    colors["aqua"] = [0, 255, 255]
    colors["aquamarine"] = [127, 255, 212]
    colors["pale_turquoise"] = [175, 238, 238]
    colors["turquoise"] = [64, 224, 208]
    colors["medium_turquoise"] = [72, 209, 204]
    colors["dark_turquoise"] = [0, 206, 209]
    colors["cadet_blue"] = [95, 158, 160]
    colors["steel_blue"] = [70, 130, 180]
    colors["light_steel_blue"] = [176, 196, 222]
    colors["powder_blue"] = [176, 224, 230]
    colors["light_blue"] = [173, 216, 230]
    colors["sky_blue"] = [135, 206, 235]
    colors["light_sky_blue"] = [135, 206, 250]
    colors["deep_sky_blue"] = [0, 191, 255]
    colors["dodger_blue"] = [30, 144, 255]
    colors["cornflower_blue"] = [100, 149, 237]
    colors["royal_blue"] = [65, 105, 225]
    colors["medium_blue"] = [0, 0, 205]
    colors["dark_blue"] = [0, 0, 139]
    colors["navy"] = [0, 0, 128]
    colors["midnight_blue"] = [25, 25, 112]
    colors["cornsilk"] = [255, 248, 220]
    colors["blanched_almond"] = [255, 235, 205]
    colors["bisque"] = [255, 228, 196]
    colors["navajo_white"] = [255, 222, 173]
    colors["wheat"] = [245, 222, 179]
    colors["burly_wood"] = [222, 184, 135]
    colors["tan"] = [210, 180, 140]
    colors["rosy_brown"] = [188, 143, 143]
    colors["sandy_brown"] = [244, 164, 96]
    colors["goldenrod"] = [218, 165, 32]
    colors["dark_goldenrod"] = [184, 134, 11]
    colors["peru"] = [205, 133, 63]
    colors["chocolate"] = [210, 105, 30]
    colors["saddle_brown"] = [139, 69, 19]
    colors["sienna"] = [160, 82, 45]
    colors["brown"] = [165, 42, 42]
    colors["maroon"] = [128, 0, 0]
    colors["white_smoke"] = [245, 245, 245]
    colors["snow"] = [255, 250, 250]
    colors["honeydew"] = [240, 255, 240]
    colors["mint_cream"] = [245, 255, 250]
    colors["azure"] = [240, 255, 255]
    colors["alice_blue"] = [240, 248, 255]
    colors["ghost_white"] = [248, 248, 255]
    colors["lavender_blush"] = [255, 240, 245]
    colors["misty_rose"] = [255, 228, 225]
    colors["seashell"] = [255, 245, 238]
    colors["old_lace"] = [253, 245, 230]
    colors["floral_white"] = [255, 250, 240]
    colors["ivory"] = [255, 255, 240]
    colors["antique_white"] = [250, 235, 215]
    colors["linen"] = [250, 240, 230]
    colors["beige"] = [245, 245, 220]
    colors["gainsboro"] = [220, 220, 220]
    colors["light_grey"] = [211, 211, 211]
    colors["silver"] = [192, 192, 192]
    colors["dark_grey"] = [169, 169, 169]
    colors["grey"] = [128, 128, 128]
    colors["dim_grey"] = [105, 105, 105]
    colors["light_slate_grey"] = [119, 136, 153]
    colors["slate_grey"] = [112, 128, 144]
    colors["dark_slate_grey"] = [47, 79, 79]
    colors["color0"] = ANSI_BLACK
    colors["color1"] = ANSI_RED
    colors["color2"] = ANSI_GREEN
    colors["color3"] = ANSI_YELLOW
    colors["color4"] = ANSI_BLUE
    colors["color5"] = ANSI_MAGENTA
    colors["color6"] = ANSI_CYAN
    colors["color7"] = ANSI_WHITE
    colors["color8"] = ANSI_BRIGHT_BLACK
    colors["color9"] = ANSI_BRIGHT_RED
    colors["color10"] = ANSI_BRIGHT_GREEN
    colors["color11"] = ANSI_BRIGHT_YELLOW
    colors["color12"] = ANSI_BRIGHT_BLUE
    colors["color13"] = ANSI_BRIGHT_MAGENTA
    colors["color14"] = ANSI_BRIGHT_CYAN
    colors["color15"] = ANSI_BRIGHT_WHITE
    return colors

let NAMED_COLORS = create_named_colors()

# Create a color object
proc Color(type, number, triplet):
    let color = {}
    color["type"] = type
    color["number"] = number
    color["triplet"] = triplet
    return color

proc is_color(color):
    if type(color) != "instance":
        return false
    let ctype = color["type"]
    return ctype == 1 or ctype == 2 or ctype == 3

# Parse a color from string name, hex string, or number
proc parse_color(name):
    if name == nil or name == "default":
        return nil
    if type(name) == "instance":
        return name
    if type(name) == "array":
        if len(name) == 3:
            return Color(COLOR_TYPE_TRUECOLOR, 0, name)
        return nil
    if type(name) != "string":
        return nil
    let sname = lower(name)
    # Named color
    if dict_has(NAMED_COLORS, sname):
        let val = NAMED_COLORS[sname]
        if type(val) == "number":
            if val >= 0 and val <= 15:
                return Color(COLOR_TYPE_STANDARD, val, nil)
            return Color(COLOR_TYPE_256, val, nil)
        if type(val) == "array" and len(val) == 3:
            return Color(COLOR_TYPE_TRUECOLOR, 0, val)
    # Hex string: #RGB, #RRGGBB
    if startswith(sname, "#"):
        let hex = ""
        for i in range(len(name) - 1):
            hex = hex + name[i + 1]
        if len(hex) == 3:
            let r = hex_to_int(hex[0] + hex[0])
            let g = hex_to_int(hex[1] + hex[1])
            let b = hex_to_int(hex[2] + hex[2])
            return Color(COLOR_TYPE_TRUECOLOR, 0, [r, g, b])
        if len(hex) == 6:
            let r = hex_to_int(hex[0:2])
            let g = hex_to_int(hex[2:4])
            let b = hex_to_int(hex[4:6])
            return Color(COLOR_TYPE_TRUECOLOR, 0, [r, g, b])
    # rgb(r,g,b) string
    if startswith(sname, "rgb(") and endswith(sname, ")"):
        let inner = ""
        let start = 4
        let endIdx = len(sname) - 1
        while start < endIdx:
            inner = inner + sname[start]
            start = start + 1
        let parts = split(inner, ",")
        if len(parts) == 3:
            let r = tonumber(strip(parts[0]))
            let g = tonumber(strip(parts[1]))
            let b = tonumber(strip(parts[2]))
            return Color(COLOR_TYPE_TRUECOLOR, 0, [r, g, b])
    # Integer 0-255
    let num = tonumber(name)
    if num == nil:
        return nil
    return Color(COLOR_TYPE_256, num, nil)

proc hex_to_int(hexstr):
    let result = 0
    for i in range(len(hexstr)):
        let c = lower(hexstr[i])
        let val = 0
        if ord(c) >= 48 and ord(c) <= 57:
            val = ord(c) - 48
        if ord(c) >= 97 and ord(c) <= 102:
            val = ord(c) - 87
        result = result * 16 + val
    return result

# Generate ANSI escape sequence for a color (foreground)
proc color_ansi_escape(color, background):
    if color == nil:
        return ""
    let ctype = color["type"]
    let prefix = "38"
    if background:
        prefix = "48"
    if ctype == COLOR_TYPE_STANDARD:
        let num = color["number"]
        if num >= 8:
            # Bright colors: 90-97 (fg) or 100-107 (bg)
            if background:
                return chr(27) + "[" + str(num - 8 + 100) + "m"
            else:
                return chr(27) + "[" + str(num - 8 + 90) + "m"
        else:
            # Standard colors: 30-37 (fg) or 40-47 (bg)
            if background:
                return chr(27) + "[" + str(num + 40) + "m"
            else:
                return chr(27) + "[" + str(num + 30) + "m"
    if ctype == COLOR_TYPE_256:
        let num = color["number"]
        return chr(27) + "[" + prefix + ";5;" + str(num) + "m"
    if ctype == COLOR_TYPE_TRUECOLOR:
        let t = color["triplet"]
        return chr(27) + "[" + prefix + ";2;" + str(t[0]) + ";" + str(t[1]) + ";" + str(t[2]) + "m"
    return ""

# Get RGB triplet for a color (approximate for non-truecolor)
proc color_get_triplet(color):
    if color == nil:
        return nil
    if color["type"] == COLOR_TYPE_TRUECOLOR:
        return color["triplet"]
    if color["type"] == COLOR_TYPE_256:
        return ansi256_to_rgb(color["number"])
    if color["type"] == COLOR_TYPE_STANDARD:
        return ansi_standard_to_rgb(color["number"])
    return nil

# Convert ANSI 256 color code to approximate RGB
proc ansi256_to_rgb(code):
    if code <= 15:
        return ansi_standard_to_rgb(code)
    if code >= 16 and code <= 231:
        let adjusted = code - 16
        let r = (adjusted / 36) | 0
        let g = ((adjusted - r * 36) / 6) | 0
        let b = adjusted - r * 36 - g * 6
        return [r * 51, g * 51, b * 51]
    # Grayscale 232-255
    let level = (code - 232) * 10 + 8
    return [level, level, level]

# Convert 16 standard ANSI colors to RGB
proc ansi_standard_to_rgb(code):
    let lut = [
        [0, 0, 0], [128, 0, 0], [0, 128, 0], [128, 128, 0],
        [0, 0, 128], [128, 0, 128], [0, 128, 128], [192, 192, 192],
        [128, 128, 128], [255, 0, 0], [0, 255, 0], [255, 255, 0],
        [0, 0, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255]
    ]
    if code >= 0 and code <= 15:
        return lut[code]
    return [0, 0, 0]

# Get the perceived brightness of a color (0-255)
proc color_brightness(color):
    let rgb = color_get_triplet(color)
    if rgb == nil:
        return 0
    return (rgb[0] * 299 + rgb[1] * 587 + rgb[2] * 114) / 1000

# Pick best contrasting text color (black or white) for a background
proc contrast_text_color(bg_color):
    let brightness = color_brightness(bg_color)
    if brightness > 140:
        return Color(COLOR_TYPE_STANDARD, ANSI_BLACK, nil)
    return Color(COLOR_TYPE_STANDARD, ANSI_WHITE, nil)

# --- Pre-created common colors ---
proc default_color():
    return nil

proc black():
    return Color(COLOR_TYPE_STANDARD, ANSI_BLACK, nil)

proc red():
    return Color(COLOR_TYPE_STANDARD, ANSI_RED, nil)

proc green():
    return Color(COLOR_TYPE_STANDARD, ANSI_GREEN, nil)

proc yellow():
    return Color(COLOR_TYPE_STANDARD, ANSI_YELLOW, nil)

proc blue():
    return Color(COLOR_TYPE_STANDARD, ANSI_BLUE, nil)

proc magenta():
    return Color(COLOR_TYPE_STANDARD, ANSI_MAGENTA, nil)

proc cyan():
    return Color(COLOR_TYPE_STANDARD, ANSI_CYAN, nil)

proc white():
    return Color(COLOR_TYPE_STANDARD, ANSI_WHITE, nil)

proc bright_black():
    return Color(COLOR_TYPE_STANDARD, ANSI_BRIGHT_BLACK, nil)

proc bright_red():
    return Color(COLOR_TYPE_STANDARD, ANSI_BRIGHT_RED, nil)

proc bright_green():
    return Color(COLOR_TYPE_STANDARD, ANSI_BRIGHT_GREEN, nil)

proc bright_yellow():
    return Color(COLOR_TYPE_STANDARD, ANSI_BRIGHT_YELLOW, nil)

proc bright_blue():
    return Color(COLOR_TYPE_STANDARD, ANSI_BRIGHT_BLUE, nil)

proc bright_magenta():
    return Color(COLOR_TYPE_STANDARD, ANSI_BRIGHT_MAGENTA, nil)

proc bright_cyan():
    return Color(COLOR_TYPE_STANDARD, ANSI_BRIGHT_CYAN, nil)

proc rgb_color(r, g, b):
    return Color(COLOR_TYPE_TRUECOLOR, 0, [r, g, b])

proc color256(n):
    return Color(COLOR_TYPE_256, n, nil)

# ============================================================================
# Color blending and palette operations
# ============================================================================

# Blend two colors by ratio (0 = all a, 1 = all b)
proc blend_colors(a, b, ratio):
    let rgb_a = color_get_triplet(a)
    let rgb_b = color_get_triplet(b)
    if rgb_a == nil:
        return b
    if rgb_b == nil:
        return a
    let r = (rgb_a[0] * (1 - ratio) + rgb_b[0] * ratio) | 0
    let g = (rgb_a[1] * (1 - ratio) + rgb_b[1] * ratio) | 0
    let b = (rgb_a[2] * (1 - ratio) + rgb_b[2] * ratio) | 0
    return rgb_color(r, g, b)

# Lighten a color by a ratio
proc lighten(color, ratio):
    return blend_colors(color, white(), ratio)

# Darken a color by a ratio
proc darken(color, ratio):
    return blend_colors(color, black(), ratio)

# Convert a color to its string representation
proc color_to_string(color):
    if color == nil:
        return "default"
    if color["type"] == COLOR_TYPE_STANDARD:
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
                     "bright_black", "bright_red", "bright_green", "bright_yellow",
                     "bright_blue", "bright_magenta", "bright_cyan", "bright_white"]
        if color["number"] >= 0 and color["number"] <= 15:
            return names[color["number"]]
        return "color" + str(color["number"])
    if color["type"] == COLOR_TYPE_256:
        return "color(" + str(color["number"]) + ")"
    if color["type"] == COLOR_TYPE_TRUECOLOR:
        let t = color["triplet"]
        return "rgb(" + str(t[0]) + "," + str(t[1]) + "," + str(t[2]) + ")"
    return "unknown"
