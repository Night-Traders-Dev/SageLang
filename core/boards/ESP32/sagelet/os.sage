## SageOS — the userspace half of Sagelet, for the classic ESP32.
##
## Pure SageLang: everything below the `import hw` line is ordinary Sage. The
## only thing coming from C is the memory-mapped I/O the emitter's `hw.*`
## hook provides (uart/gpio/timer), because `mem_read`/`mem_write` are
## deliberately confined to `mem_alloc` regions and cannot reach MMIO.
##
## Image layout this expects:
##   0x001000  SageBoot  (second-stage bootloader, boot.sage)
##   0x008000  partition table
##   0x010000  SageOS   (this file)  <- entry from the linker script
##
## Build:  bash core/boards/ESP32/sagelet/build.sh
## Flash:  bash core/boards/ESP32/sagelet/flash.sh [port]

import hw
import esp32

# --------------------------------------------------------------- identity

let OS_NAME = "SageletOS"
let OS_VERSION = "0.1.0"
let BANNER = "SageletOS for ESP32"

# The onboard LED on a DevKit is GPIO2.
let LED_PIN = 2

# ------------------------------------------------------------- utilities

proc put(text):
    hw.uart_puts(text)

proc putln(text):
    hw.uart_puts(text)
    hw.uart_puts("\n")

proc put_num(value):
    # Render integers by hand: no printf formatting on the target, and this
    # keeps the number of distinct HAL calls small.
    if value < 0:
        hw.uart_puts("-")
        value = 0 - value
    if value == 0:
        hw.uart_puts("0")
        return
    var digits = ""
    while value > 0:
        let d = value - ((value / 10) * 10)
        digits = chr(48 + d) + digits
        value = value / 10
    hw.uart_puts(digits)

proc pad_num(value, width):
    var out = ""
    var v = value
    while v > 0:
        out = chr(48 + (v - (v / 10) * 10)) + out
        v = v / 10
    while len(out) < width:
        out = " " + out
    return out

proc trim(line):
    var s = line
    while len(s) > 0:
        let c = s[0]
        if c == " " or c == "\t" or c == "\r" or c == "\n":
            s = s[1:len(s)]
        else:
            break
    while len(s) > 0:
        let c = s[len(s) - 1]
        if c == " " or c == "\t" or c == "\r" or c == "\n":
            s = s[0:len(s) - 1]
        else:
            break
    return s

# Split on spaces into a list, dropping empties.
proc split_ws(line):
    var out = []
    let parts = line.split(" ")
    for p in parts:
        if p != "":
            push(out, p)
    return out

# ------------------------------------------------------------- hardware

proc led_init():
    hw.gpio_init(LED_PIN)
    hw.gpio_set_dir(LED_PIN, 1)
    hw.gpio_put(LED_PIN, 0)

proc led_write(value):
    hw.gpio_put(LED_PIN, value)

# Blink `times` times, `on_ms` on / `off_ms` off. Returns total duration.
proc blink(times, on_ms, off_ms):
    var i = 0
    var total = 0
    while i < times:
        led_write(1)
        hw.delay_ms(on_ms)
        total = total + on_ms
        led_write(0)
        hw.delay_ms(off_ms)
        total = total + off_ms
        i = i + 1
    return total

# --------------------------------------------------------------- commands

proc cmd_help():
    putln("")
    putln("SageletOS commands")
    putln("  help              this text")
    putln("  blink [n] [on] [off]   blink LED n times (default 3, 200ms, 200ms)")
    putln("  led on|off|read   drive or sample the LED directly")
    putln("  uptime            milliseconds since boot")
    putln("  clock             CPU clock in Hz")
    putln("  temp              raw on-chip temperature sensor reading")
    putln("  board             chip description")
    putln("  bootinfo          bootloader that handed us control")
    putln("  ver               OS version")
    putln("  clear             clear the screen (many newlines)")
    putln("  reset             reset the chip (RTC watchdog)")
    putln("")

proc cmd_uptime():
    let ms = hw.uptime_ms()
    put("uptime ")
    put_num(ms)
    putln(" ms")
    put("        ")
    put_num(ms / 1000)
    put(".")
    put_num((ms / 100) - ((ms / 1000) * 10))
    put_num((ms / 10) - ((ms / 100) * 10))
    putln(" s")

proc cmd_board():
    putln(esp32.describe())

proc cmd_bootinfo():
    putln("entered via SageBoot v0.1.0 (second stage, 0x1000)")
    putln("  partition table @ 0x8000 -> app slot 0x10000")
    putln("  cpu   240 MHz, dual core (cpu1 parked)")
    putln("  flash 4 MB, io mode dio")

proc cmd_ver():
    put(OS_NAME)
    put(" ")
    putln(OS_VERSION)
    put("spec ")
    putln(esp32.spec_version())

proc cmd_temp():
    let t = hw.temp_c()
    put("tsens raw ")
    put_num(t)
    putln("")

proc cmd_led(args):
    if len(args) == 0:
        put("led read: ")
        put_num(hw.gpio_get(LED_PIN))
        putln("")
        return
    let what = args[0]
    if what == "on":
        led_write(1)
        putln("led on")
    elif what == "off":
        led_write(0)
        putln("led off")
    elif what == "read":
        put("led read: ")
        put_num(hw.gpio_get(LED_PIN))
        putln("")
    else:
        putln("usage: led on|off|read")

proc cmd_blink(args):
    var times = 3
    var on_ms = 200
    var off_ms = 200
    if len(args) >= 1:
        times = int(args[0])
    if len(args) >= 2:
        on_ms = int(args[1])
    if len(args) >= 3:
        off_ms = int(args[2])
    if times < 1:
        putln("blink: count must be >= 1")
        return
    if times > 100:
        times = 100
    put("blink x")
    put_num(times)
    put(" (on ")
    put_num(on_ms)
    put("ms, off ")
    put_num(off_ms)
    putln("ms)")
    let t0 = hw.uptime_ms()
    let total = blink(times, on_ms, off_ms)
    let t1 = hw.uptime_ms()
    put("blink done: ")
    put_num(t1 - t0)
    putln(" ms elapsed")

proc cmd_reset(_args):
    putln("resetting...")
    hw.delay_ms(50)
    hw.reset()

proc cmd_clear(_args):
    var i = 0
    while i < 24:
        putln("")
        i = i + 1

proc dispatch(line):
    let args = split_ws(line)
    if len(args) == 0:
        return
    let cmd = args[0]
    let rest = []
    var i = 1
    while i < len(args):
        push(rest, args[i])
        i = i + 1

    if cmd == "help" or cmd == "?":
        cmd_help()
    elif cmd == "blink":
        cmd_blink(rest)
    elif cmd == "led":
        cmd_led(rest)
    elif cmd == "uptime":
        cmd_uptime()
    elif cmd == "clock":
        put("clock ")
        put_num(hw.clock_hz())
        putln(" Hz")
    elif cmd == "temp":
        cmd_temp()
    elif cmd == "board":
        cmd_board()
    elif cmd == "bootinfo":
        cmd_bootinfo()
    elif cmd == "ver" or cmd == "version":
        cmd_ver()
    elif cmd == "clear":
        cmd_clear(rest)
    elif cmd == "reset":
        cmd_reset(rest)
    else:
        put("unknown command: ")
        putln(cmd)
        putln("try 'help'")

# ------------------------------------------------------------------- REPL

var line = ""
var running = true

proc read_line_blocking():
    var buf = ""
    while true:
        let c = hw.uart_getc()
        if c >= 0:
            if c == 13 or c == 10:
                # CR or LF ends the line; a CRLF pair simply arrives as two
                # reads and the leftover LF is discarded by the next prompt.
                return buf
            if c == 8 or c == 127:
                if len(buf) > 0:
                    buf = buf[0:len(buf) - 1]
                    hw.uart_puts("\b \b")
                continue
            if c >= 32 and c < 127:
                buf = buf + chr(c)
                hw.uart_putc(c)
        else:
            hw.delay_us(200)

proc repl():
    putln("")
    putln(BANNER)
    put("SageletOS ")
    put(OS_VERSION)
    putln(" ready.")
    putln("type 'help' for commands, 'blink' to blink the LED")
    put("")
    while running:
        put("sagelet> ")
        line = read_line_blocking()
        putln("")
        let cmdline = trim(line)
        if cmdline == "":
            continue
        dispatch(cmdline)

# -------------------------------------------------------------------- main

proc main():
    hw.uart_init(115200)
    led_init()
    repl()
    # The REPL never returns; if it does, park.
    while true:
        hw.delay_ms(1000)

main()
