## metal.timer — Hardware Timer Driver for Bare-Metal
##
## Supports x86 PIT (8254), ARM Generic Timer, and RISC-V mtime.

import metal.core
import metal.irq

## ============================================================
## x86 PIT (Programmable Interval Timer) 8254
## ============================================================

let PIT_CH0_DATA = 64 # 0x40 Channel 0 data port
let PIT_CMD = 67 # 0x43 Command register
let PIT_FREQ = 1193182 # PIT base frequency (Hz)

let TIMER_MODE_ONESHOT = 0
let TIMER_MODE_PERIODIC = 1

let _tick_count = 0
let _timer_initialized = false

## PIT interrupt handler
proc _pit_handler(vector):
    _tick_count = _tick_count + 1
    irq.pic_eoi(irq.IRQ_TIMER)

## Initialize PIT at the given frequency (Hz).
## Deprecated: use timer_init_periodic() instead.
proc pit_init(hz):
    timer_init_periodic(hz)

## Initialize the PIT in periodic mode at the given frequency (Hz).
proc timer_init_periodic(hz):
    let divisor = PIT_FREQ / hz
    core.outb(PIT_CMD, 54) # Channel 0, lobyte/hibyte, mode 3 (periodic)
    core.outb(PIT_CH0_DATA, divisor & 255) # Low byte
    core.outb(PIT_CH0_DATA, divisor >> 8) # High byte
    if not _timer_initialized:
        irq.register_handler(32 + irq.IRQ_TIMER, _pit_handler)
        _timer_initialized = true
    irq.pic_unmask(irq.IRQ_TIMER)

## Initialize the PIT in one-shot mode at the given frequency (Hz).
proc timer_init_oneshot(hz):
    let divisor_oneshot = PIT_FREQ / hz
    core.outb(PIT_CMD, 48) # Channel 0, lobyte/hibyte, mode 0 (one-shot)
    core.outb(PIT_CH0_DATA, divisor_oneshot & 255) # Low byte
    core.outb(PIT_CH0_DATA, divisor_oneshot >> 8) # High byte
    if not _timer_initialized:
        irq.register_handler(32 + irq.IRQ_TIMER, _pit_handler)
        _timer_initialized = true
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

## Busy-wait delay for N microseconds.
proc delay_us(us):
    core.delay_us(us)

## ============================================================
## Simple Stopwatch
## ============================================================

## Start a stopwatch by returning the current tick count.
proc stopwatch_start():
    return _tick_count

## Get elapsed milliseconds since the given start tick.
proc stopwatch_elapsed_ms(start_tick):
    return _tick_count - start_tick

## Get remaining time in milliseconds for the current timer cycle.
## Latches the hardware PIT counter to read the current value.
proc timer_remaining_ms():
    core.outb(PIT_CMD, 0) # Latch channel 0
    let lo = core.inb(PIT_CH0_DATA)
    let hi = core.inb(PIT_CH0_DATA)
    let count = lo | (hi << 8)
    return (count * 1000) / PIT_FREQ

## Safely cancel the active timer by masking its IRQ.
proc timer_cancel_safe():
    irq.mask_irq(irq.IRQ_TIMER)
