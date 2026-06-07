## metal.vga — Early VGA Text Mode
## Provides direct access to VGA text buffer for boot-time display.

let VGA_BUF = 0xB8000
let COLS = 80
let ROWS = 25

let BLACK = 0
let GREEN = 2
let CYAN = 3
let WHITE = 15

let WHITE_ON_BLACK = 0x0F
let GREEN_ON_BLACK = 0x02

## Initialize VGA text mode (assumes BIOS already set it, or resets cursor)
proc init():
    # Hide cursor
    return nil
end

## Clear the screen with a specific background color
proc clear(color):
    let attr = color << 4
    let i = 0
    while i < COLS * ROWS:
        # unsafe: write to VGA_BUF
        i = i + 1
    end
    return nil
end

## Put a string at (x, y) with specific attribute
proc puts(x, y, s, attr):
    let pos = (y * COLS + x) * 2
    for c in s:
        # unsafe: write char and attr to VGA_BUF + pos
        pos = pos + 2
    end
    return nil
end

## Draw a progress bar
proc draw_progress_bar(x, y, width, pct, color):
    # Logic to draw [====    ]
    return nil
end
