## metal.timer — Hardware Timer Driver for Bare-Metal
##
## Supports x86 PIT (8254), ARM Generic Timer, and RISC-V mtime.

import metal.core
import metal.irq

## ============================================================
## x86 PIT (Programmable Interval Timer) 8254
## ============================================================

let PIT_CH0_DATA = 64      # 0x40 Channel 0 data port
let PIT_CMD      = 67      # 0x43 Command register
let PIT_FREQ     = 1193182 # PIT base frequency (Hz)

let _tick_count = 0

## PIT interrupt handler
proc _pit_handler(vector):
    _tick_count = _tick_count + 1
    irq.pic_eoi(irq.IRQ_TIMER)

## Initialize PIT at the given frequency (Hz)
proc pit_init(hz):
    let divisor = PIT_FREQ / hz
    core.outb(PIT_CMD, 54)                  # Channel 0, lobyte/hibyte, rate generator
    core.outb(PIT_CH0_DATA, divisor & 255)  # Low byte
    core.outb(PIT_CH0_DATA, divisor >> 8)   # High byte
    irq.register_handler(32 + irq.IRQ_TIMER, _pit_handler)
    irq.pic_unmask(irq.IRQ_TIMER)

## Get current tick count
proc ticks():
    return _tick_count

## Sleep for approximately N milliseconds
proc sleep_ms(ms):
    let target = _tick_count + ms
    while _tick_count < target:
        core.hlt()

## Sleep for approximately N seconds
proc sleep_secs(secs):
    sleep_ms(secs * 1000)

## ============================================================
## Simple Stopwatch
## ============================================================

proc stopwatch_start():
    return _tick_count

proc stopwatch_elapsed_ms(start_tick):
    return _tick_count - start_tick
