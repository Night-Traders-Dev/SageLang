## metal.irq — Interrupt Request Management for Bare-Metal
##
## Provides interrupt vector registration, PIC/APIC control,
## and exception handling for x86-64, aarch64, and rv64.

import metal.core

## ============================================================
## x86 PIC (Programmable Interrupt Controller) 8259A
## ============================================================

let PIC1_CMD  = 32      # 0x20 Master PIC command
let PIC1_DATA = 33      # 0x21 Master PIC data
let PIC2_CMD  = 160     # 0xA0 Slave PIC command
let PIC2_DATA = 161     # 0xA1 Slave PIC data

## ICW (Initialization Command Words)
let ICW1_INIT = 17      # 0x11
let ICW4_8086 = 1       # 0x01

## Remap PIC IRQs to avoid CPU exception conflicts
## Maps IRQ 0-7 to vectors offset1..offset1+7
## Maps IRQ 8-15 to vectors offset2..offset2+7
proc pic_remap(offset1, offset2):
    core.outb(PIC1_CMD, ICW1_INIT)
    core.io_wait()
    core.outb(PIC2_CMD, ICW1_INIT)
    core.io_wait()
    core.outb(PIC1_DATA, offset1)
    core.io_wait()
    core.outb(PIC2_DATA, offset2)
    core.io_wait()
    core.outb(PIC1_DATA, 4)
    core.io_wait()
    core.outb(PIC2_DATA, 2)
    core.io_wait()
    core.outb(PIC1_DATA, ICW4_8086)
    core.io_wait()
    core.outb(PIC2_DATA, ICW4_8086)
    core.io_wait()

## Send End-Of-Interrupt to PIC
proc pic_eoi(irq):
    if irq >= 8:
        core.outb(PIC2_CMD, 32)
    core.outb(PIC1_CMD, 32)

## Mask (disable) a specific IRQ line
proc pic_mask(irq):
    if irq < 8:
        let mask = core.inb(PIC1_DATA)
        core.outb(PIC1_DATA, mask | (1 << irq))
    else:
        let mask = core.inb(PIC2_DATA)
        core.outb(PIC2_DATA, mask | (1 << (irq - 8)))

## Unmask (enable) a specific IRQ line
proc pic_unmask(irq):
    if irq < 8:
        let mask = core.inb(PIC1_DATA)
        core.outb(PIC1_DATA, mask & (255 - (1 << irq)))
    else:
        let mask = core.inb(PIC2_DATA)
        core.outb(PIC2_DATA, mask & (255 - (1 << (irq - 8))))

## ============================================================
## Interrupt Vector Table (software-managed)
## ============================================================

let _handlers = {}

## Register an interrupt handler
proc register_handler(vector, handler):
    _handlers[str(vector)] = handler

## Dispatch an interrupt (called from ISR stub)
proc dispatch(vector):
    let key = str(vector)
    if dict_has(_handlers, key):
        let handler = _handlers[key]
        handler(vector)
    else:
        core.puts("Unhandled interrupt: " + str(vector))

## ============================================================
## Common x86 Exception Vectors
## ============================================================

let EXCEPTION_DIVIDE_ERROR     = 0
let EXCEPTION_DEBUG            = 1
let EXCEPTION_NMI              = 2
let EXCEPTION_BREAKPOINT       = 3
let EXCEPTION_OVERFLOW         = 4
let EXCEPTION_BOUND_RANGE      = 5
let EXCEPTION_INVALID_OPCODE   = 6
let EXCEPTION_DEVICE_NOT_AVAIL = 7
let EXCEPTION_DOUBLE_FAULT     = 8
let EXCEPTION_INVALID_TSS      = 10
let EXCEPTION_SEGMENT_NOT_PRES = 11
let EXCEPTION_STACK_FAULT      = 12
let EXCEPTION_GENERAL_PROTECT  = 13
let EXCEPTION_PAGE_FAULT       = 14

## Common IRQ numbers (after PIC remap to 32+)
let IRQ_TIMER    = 0
let IRQ_KEYBOARD = 1
let IRQ_CASCADE  = 2
let IRQ_COM2     = 3
let IRQ_COM1     = 4
let IRQ_FLOPPY   = 6
let IRQ_RTC      = 8
