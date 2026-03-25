gc_disable()

# timer.sage — Programmable Interval Timer (PIT) driver
# Configures PIT channel 0 for periodic interrupts.

# ----- PIT constants -----
let PIT_FREQ = 1193182
let PIT_CHANNEL0 = 64
let PIT_CMD = 67

# ----- Timer state -----
let tick_count = 0
let timer_freq = 0
let ms_per_tick = 0
let timer_handler = nil
let timer_ready = false

proc init(frequency_hz):
    if frequency_hz < 1:
        frequency_hz = 1
    end
    timer_freq = frequency_hz
    # Calculate the PIT divisor
    let divisor = PIT_FREQ / frequency_hz

    # In a real kernel we would:
    #   outb(PIT_CMD, 0x36)        — channel 0, lo/hi, rate generator
    #   outb(PIT_CHANNEL0, divisor & 0xFF)
    #   outb(PIT_CHANNEL0, (divisor >> 8) & 0xFF)

    ms_per_tick = 1000 / frequency_hz
    tick_count = 0
    timer_handler = nil
    timer_ready = true
end

proc tick():
    # Called by the IRQ0 handler on each timer interrupt.
    tick_count = tick_count + 1
    if timer_handler != nil:
        timer_handler()
    end
end

proc get_ticks():
    return tick_count
end

proc get_uptime_ms():
    return tick_count * ms_per_tick
end

proc get_uptime_s():
    return get_uptime_ms() / 1000
end

proc sleep_ms(ms):
    if timer_ready == false:
        return
    end
    let target = get_uptime_ms() + ms
    while get_uptime_ms() < target:
        # busy-wait
        let dummy = 0
    end
end

proc sleep_s(s):
    sleep_ms(s * 1000)
end

proc set_handler(callback):
    timer_handler = callback
end

proc get_frequency():
    return timer_freq
end

proc reset():
    tick_count = 0
end

proc stats():
    let s = {}
    s["ticks"] = tick_count
    s["frequency_hz"] = timer_freq
    s["ms_per_tick"] = ms_per_tick
    s["uptime_ms"] = get_uptime_ms()
    s["uptime_s"] = get_uptime_s()
    return s
end
