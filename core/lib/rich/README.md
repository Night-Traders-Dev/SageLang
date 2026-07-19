# sagelang-lib-rich

A pure Sage port of Python's `rich` library — beautiful terminal formatting for Sage applications.

## Features

- **Console** — Terminal output with automatic styling and terminal detection
- **Colors** — Full ANSI color support: 3-bit, 8-bit (256 colors), and 24-bit truecolor. 140+ named colors
- **Styles** — Bold, italic, underline, dim, blink, reverse, strikethrough
- **Text** — Rich text with styled spans and segments
- **Panel** — Content surrounded by beautiful borders (7 box styles)
- **Table** — Feature-rich tables with headers, footers, borders, column alignment
- **Tree** — Hierarchical tree rendering
- **Columns** — Side-by-side column layout
- **Layout** — Flexible split-pane layout engine
- **Rule** — Horizontal rule dividers with optional title
- **Progress** — Animated progress bars with spinners
- **Status** — Status indicator with spinner animation
- **Markdown** — Simple markdown rendering (headers, lists, code, bold/italic)
- **Emoji** — 200+ named emojis with `:name:` substitution
- **Spinner** — 12 animated spinner styles
- **Padding** — Flexible content padding
- **Theme** — Built-in dark/light themes
- **Prompt** — Styled interactive prompts
- **Traceback** — Beautiful exception formatting

## Installation

Add as a submodule to your Sage project:

```bash
git submodule add https://github.com/Night-Traders-Dev/sagelang-lib-rich core/lib/rich
```

## Quick Start

```sage
import rich

# Print styled text
rich.print_styled("Hello, World!", "bold green")

# Create a panel
let panel = rich.Panel("Hello from Sage!", "My Panel")
rich.print(panel)

# Create a table
let table = rich.Table("Fruits")
table.add_column("Name")
table.add_column("Color")
table.add_column("Count")
table.add_row(["Apple", "Red", 42])
table.add_row(["Banana", "Yellow", 17])
table.add_row(["Grape", "Purple", 93])
rich.print(table)

# Create a tree
let tree = rich.Tree("Root")
let child = tree.add("Branch A")
child.add("Leaf 1")
child.add("Leaf 2")
let child2 = tree.add("Branch B")
child2.add("Leaf 3")
rich.print(tree)

# Print markdown
rich.print_markdown("# Hello\n\nThis is **bold** and this is *italic*.\n\n- Item 1\n- Item 2")

# Use emoji
rich.print(rich.emoji("rocket") + " Launching!")
```

## Console

```sage
import rich
let console = rich.Console()

console.print("Hello, World!")
console.print(rich.Panel("Important message", "Warning"))

# Rule with title
console.rule("Section 1", "cyan")
console.print("Content here...")
console.rule("Section 2")
```

## Color & Style

```sage
import rich

# Parse HTML-style hex colors
let c = rich.parse_color("#ff0000")

# Named colors (140+)
let blue = rich.parse_color("dodger_blue")

# RGB
let purple = rich.rgb_color(128, 0, 255)

# Style objects
let style = rich.parse_style("bold red on blue")
rich.print(rich.render_styled("Styled text", style))
```

## Box Styles

```sage
# Available box styles:
# ascii, single (default), double, round, heavy, double_single, minimal, simple

import rich
let panel = rich.Panel("Content", "Title", nil, "double")
rich.print(panel)
```

## Progress Bar

```sage
import rich
let bar = rich.ProgressBar(100, 40)
bar.advance(25)
rich.print(bar)
bar.advance(25)
rich.print(bar)
```

## Live Display

```sage
import rich
let console = rich.Console()
let live = rich.Live("Loading...", console)
live.start(nil)
# ... do work ...
live.update("Done!")
live.stop()
```

## Styled Prompt

```sage
import rich

# Build a multi-part styled prompt for interactive shells
let prompt = rich.render_prompt([
    ["SageSMP", "bold bright_cyan"],
    [" → ", "bold bright_magenta"],
])
let line = input(prompt)
```

Parts are `[text, style_string]` pairs. Plain strings are also accepted (rendered unstyled).

## Changelog

- **v1.2.0**: Fixed duplicate emoji entries (`dizzy`→`dizzy_face`, `mouse`→`mouse_peripheral`, removed duplicate `lavender_blush` in color map). Fixed `merge_styles` boolean override logic (could not unset bold/italic via merge). Added missing `not` style negation for dim, underline, blink, reverse, strike. Improved `detect_terminal_size()` to actually query the terminal via `stty size` instead of always returning 80x24.
- **v1.1.0**: Fixed bright color ANSI escape codes (colors 8-15 now correctly map to codes 90-97 for foreground and 100-107 for background). Added `render_prompt()` for building styled interactive prompts.

## License

MIT — Same as SageLang

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)
