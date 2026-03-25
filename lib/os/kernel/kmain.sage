gc_disable()

# kmain.sage — Kernel entry point for SageOS
# Initializes all subsystems and provides panic/halt primitives.

import console
import keyboard
import timer
import syscall
import pmm
import vmm

let KERNEL_NAME = "SageOS"
let KERNEL_VERSION = "0.1.0"

proc kernel_version()
    return KERNEL_NAME + " " + KERNEL_VERSION
end

proc create_kernel(name, version)
    let cfg = {}
    cfg["name"] = name
    cfg["version"] = version
    cfg["console_ready"] = false
    cfg["memory_ready"] = false
    cfg["interrupts_ready"] = false
    cfg["keyboard_ready"] = false
    cfg["timer_ready"] = false
    cfg["syscalls_ready"] = false
    cfg["vmm_ready"] = false
    return cfg
end

proc panic(msg)
    let nl = chr(10)
    let line = "==============================="
    console.set_color(console.WHITE, console.RED)
    console.print_line("")
    console.print_line(line)
    console.print_line("  KERNEL PANIC")
    console.print_line(line)
    console.print_line("")
    console.print_line("  " + msg)
    console.print_line("")
    console.print_line(line)
    halt()
end

proc halt()
    # In a real kernel this would be a HLT instruction loop.
    # Here we simulate it by spinning forever.
    let running = true
    while running
        # busy wait — CPU halted
        let dummy = 0
    end
end

proc init_console(boot_info)
    console.init_vga()
    console.set_color(console.LIGHT_GREEN, console.BLACK)
    console.clear_screen(console.BLACK)
    console.print_line(kernel_version() + " booting...")
    console.print_line("")
    if boot_info != nil
        if dict_has(boot_info, "framebuffer")
            let fb = boot_info["framebuffer"]
            console.init_framebuffer(fb["addr"], fb["width"], fb["height"], fb["pitch"], fb["bpp"])
        end
    end
    return true
end

proc init_memory(boot_info)
    let mem_map = nil
    if boot_info != nil
        if dict_has(boot_info, "memory_map")
            mem_map = boot_info["memory_map"]
        end
    end
    if mem_map == nil
        mem_map = []
    end
    pmm.init(mem_map)
    vmm.init()
    let total_mb = pmm.total_memory() / 1048576
    console.print_line("  Memory: " + str(total_mb) + " MB total")
    return true
end

proc init_interrupts()
    syscall.init()
    console.print_line("  Interrupts: IDT installed")
    return true
end

proc init_keyboard()
    keyboard.init()
    console.print_line("  Keyboard: PS/2 driver ready")
    return true
end

proc init_timer(freq_hz)
    timer.init(freq_hz)
    console.print_line("  Timer: PIT at " + str(freq_hz) + " Hz")
    return true
end

proc kmain(boot_info)
    let kernel = create_kernel(KERNEL_NAME, KERNEL_VERSION)

    # Phase 1: Console (needed for all output)
    kernel["console_ready"] = init_console(boot_info)

    console.print_line("[1/6] Console initialized")

    # Phase 2: Physical + Virtual memory
    kernel["memory_ready"] = init_memory(boot_info)
    kernel["vmm_ready"] = true
    console.print_line("[2/6] Memory manager initialized")

    # Phase 3: Interrupts / syscall table
    kernel["interrupts_ready"] = init_interrupts()
    kernel["syscalls_ready"] = true
    console.print_line("[3/6] Interrupts initialized")

    # Phase 4: Keyboard
    kernel["keyboard_ready"] = init_keyboard()
    console.print_line("[4/6] Keyboard initialized")

    # Phase 5: Timer
    kernel["timer_ready"] = init_timer(100)
    console.print_line("[5/6] Timer initialized")

    # Phase 6: Ready
    console.print_line("[6/6] All subsystems ready")
    console.print_line("")
    console.set_color(console.WHITE, console.BLACK)
    console.print_line(kernel_version() + " is running.")
    console.print_line("")

    return kernel
end
