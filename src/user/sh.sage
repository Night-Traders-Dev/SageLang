gc_disable()

# sh.sage — Minimal SageOS Shell
# Provides a terminal-based interface for user interaction.

import os.kernel.console as console
import os.kernel.keyboard as keyboard
import os.kernel.syscall as syscall

proc print_prompt():
    console.set_color(console.LIGHT_CYAN, console.BLACK)
    console.print_str("sage@os")
    console.set_color(console.WHITE, console.BLACK)
    console.print_str(":")
    console.set_color(console.LIGHT_BLUE, console.BLACK)
    console.print_str("~")
    console.set_color(console.WHITE, console.BLACK)
    console.print_str("$ ")
end

proc handle_command(cmd):
    if cmd == "":
        return
    end
    
    if cmd == "help":
        console.print_line("Available commands:")
        console.print_line("  help     - Show this help message")
        console.print_line("  ls       - List files (simulated)")
        console.print_line("  clear    - Clear the screen")
        console.print_line("  version  - Show SageOS version")
        console.print_line("  exit     - Exit the shell")
        return
    end
    
    if cmd == "ls":
        console.print_line("bin/  etc/  home/  kernel.bin")
        return
    end
    
    if cmd == "clear":
        console.clear_screen(console.BLACK)
        return
    end
    
    if cmd == "version":
        console.print_line("SageOS v0.1.0 (x86_64)")
        return
    end
    
    if cmd == "exit":
        console.print_line("Shutting down...")
        syscall.sys_exit(0)
        return
    end
    
    console.print_line("sh: command not found: " + cmd)
end

proc main():
    console.print_line("SageOS Shell v0.1.0")
    console.print_line("Type 'help' for available commands.")
    console.print_line("")
    
    let cmd_buffer = ""
    while true:
        print_prompt()
        
        # Read line from keyboard
        cmd_buffer = ""
        let reading = true
        while reading:
            let ch = keyboard.get_char()
            if ch != nil:
                if ch == chr(10): # Enter
                    console.newline()
                    reading = false
                else if ch == chr(8): # Backspace
                    if len(cmd_buffer) > 0:
                        # Simple backspace: move cursor back, print space, move back
                        let pos = console.get_cursor()
                        if pos["x"] > 0:
                            console.set_cursor(pos["x"] - 1, pos["y"])
                            console.print_str(" ")
                            console.set_cursor(pos["x"] - 1, pos["y"])
                            # Truncate cmd_buffer
                            let new_cmd = ""
                            for i in range(len(cmd_buffer) - 1):
                                new_cmd = new_cmd + cmd_buffer[i]
                            end
                            cmd_buffer = new_cmd
                        end
                    end
                else:
                    cmd_buffer = cmd_buffer + ch
                    console.print_str(ch)
                end
            end
            # Yield to other tasks if multi-tasking was enabled
            syscall.builtin_yield(nil)
        end
        
        handle_command(cmd_buffer)
    end
end
