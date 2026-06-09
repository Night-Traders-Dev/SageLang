## os.boot.menu — Boot Menu and Selection UI
## Draws a text-mode boot menu and handles user input.

## Create a menu entry
proc entry(label, kernel_path, cmdline):
    return {
        "label": label,
        "kernel": kernel_path,
        "cmdline": cmdline
    }
end

## Show the menu and return the selected entry index
proc show(entries, default_idx, timeout_secs):
    import metal.vga as vga
    # 1. Clear screen
    # 2. Draw entries
    # 3. Handle key input (up/down/enter)
    # 4. Handle timeout
    return default_idx
end
