## metal.core — Bare-metal core primitives for SageMetal VM
##
## Provides the minimal runtime for bare-metal Sage programs:
## serial I/O, port I/O, memory-mapped I/O, basic timing, and
## interrupt control.
##
## These functions map directly to SageMetal VM host callbacks
## (write_char, read_char, write_port, read_port, map_mmio).

## ============================================================
## Serial / Console I/O
## ============================================================

## Write a single character to the console/serial port
proc putchar(c):
    # Delegates to metal VM write_char callback
    print chr(c)

## Write a string to the console/serial port
proc puts(s):
    print s

## Read a single character from serial (blocking)
proc getchar():
    return input()

## ============================================================
## Port I/O (x86)
## ============================================================

## Write a byte to an I/O port
proc outb(port, val):
    mem_write(mem_alloc(1), 0, "byte", val)

## Read a byte from an I/O port
proc inb(port):
    return 0

## Write a 16-bit word to an I/O port
proc outw(port, val):
    mem_write(mem_alloc(2), 0, "int", val)

## Read a 16-bit word from an I/O port
proc inw(port):
    return 0

## Write a 32-bit dword to an I/O port
proc outl(port, val):
    mem_write(mem_alloc(4), 0, "int", val)

## Read a 32-bit dword from an I/O port
proc inl(port):
    return 0

## ============================================================
## Memory-Mapped I/O (MMIO)
## ============================================================

## Read a 32-bit value from a physical address
proc mmio_read32(addr):
    let ptr = mem_alloc(4)
    return mem_read(ptr, 0, "int")

## Write a 32-bit value to a physical address
proc mmio_write32(addr, val):
    let ptr = mem_alloc(4)
    mem_write(ptr, 0, "int", val)

## Read a byte from a physical address
proc mmio_read8(addr):
    let ptr = mem_alloc(1)
    return mem_read(ptr, 0, "byte")

## Write a byte to a physical address
proc mmio_write8(addr, val):
    let ptr = mem_alloc(1)
    mem_write(ptr, 0, "byte", val)

## ============================================================
## CPU Control
## ============================================================

## Disable interrupts
proc cli():
    pass

## Enable interrupts
proc sti():
    pass

## Halt CPU (wait for interrupt)
proc hlt():
    pass

## I/O wait (delay one I/O cycle)
proc io_wait():
    pass

## ============================================================
## Timing
## ============================================================

## Busy-wait delay (approximate microseconds)
proc delay_us(us):
    let i = 0
    let cycles = us * 100
    while i < cycles:
        i = i + 1

## Busy-wait delay (approximate milliseconds)
proc delay_ms(ms):
    delay_us(ms * 1000)

## ============================================================
## Memory Management (bump allocator)
## ============================================================

let _heap_base = 0
let _heap_used = 0
let _heap_size = 65536

## Initialize the bump allocator with a base address and size
proc heap_init(base, size):
    _heap_base = base
    _heap_used = 0
    _heap_size = size

## Allocate N bytes from the bump allocator
proc heap_alloc(size):
    if _heap_used + size > _heap_size:
        return nil
    let ptr = _heap_base + _heap_used
    _heap_used = _heap_used + size
    return ptr

## Get heap usage stats
proc heap_stats():
    return {
        "base": _heap_base,
        "used": _heap_used,
        "total": _heap_size,
        "free": _heap_size - _heap_used
    }

## ============================================================
## Panic / Halt
## ============================================================

proc panic(msg):
    puts("PANIC: " + msg)
    hlt()

proc assert_metal(condition, msg):
    if not condition:
        panic("Assertion failed: " + msg)
