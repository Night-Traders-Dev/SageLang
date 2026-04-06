## metal.serial — UART Serial Port Driver for Bare-Metal
##
## Supports NS16550A (x86 COM ports) and PL011 (ARM/AArch64).
## Used for debug output, logging, and simple terminal I/O.

import metal.core

## ============================================================
## NS16550A UART (x86 COM1-COM4)
## ============================================================

let COM1 = 1016       # 0x3F8
let COM2 = 760        # 0x2F8
let COM3 = 1000       # 0x3E8
let COM4 = 744        # 0x2E8

## UART register offsets
let UART_DATA    = 0   # Data register (R/W)
let UART_IER     = 1   # Interrupt Enable
let UART_FCR     = 2   # FIFO Control
let UART_LCR     = 3   # Line Control
let UART_MCR     = 4   # Modem Control
let UART_LSR     = 5   # Line Status
let UART_MSR     = 6   # Modem Status

## Initialize a COM port at the given baud rate
proc uart_init(port, baud):
    let divisor = 115200 / baud
    core.outb(port + UART_IER, 0)           # Disable interrupts
    core.outb(port + UART_LCR, 128)         # Enable DLAB
    core.outb(port + UART_DATA, divisor & 255)  # Divisor low byte
    core.outb(port + UART_IER, divisor >> 8)    # Divisor high byte
    core.outb(port + UART_LCR, 3)           # 8N1
    core.outb(port + UART_FCR, 199)         # Enable FIFO, clear, 14-byte threshold
    core.outb(port + UART_MCR, 11)          # IRQs enabled, RTS/DSR set

## Check if transmit buffer is empty
proc uart_tx_ready(port):
    return core.inb(port + UART_LSR) & 32

## Check if receive data is available
proc uart_rx_ready(port):
    return core.inb(port + UART_LSR) & 1

## Send a single byte
proc uart_send(port, byte):
    while not uart_tx_ready(port):
        core.io_wait()
    core.outb(port + UART_DATA, byte)

## Receive a single byte (blocking)
proc uart_recv(port):
    while not uart_rx_ready(port):
        core.io_wait()
    return core.inb(port + UART_DATA)

## Send a string
proc uart_puts(port, s):
    let i = 0
    while i < len(s):
        uart_send(port, ord(s[i]))
        if s[i] == chr(10):
            uart_send(port, 13)
        i = i + 1

## ============================================================
## PL011 UART (ARM/AArch64)
## ============================================================

## PL011 register offsets
let PL011_DR     = 0      # Data register
let PL011_FR     = 24     # Flag register (0x18)
let PL011_IBRD   = 36     # Integer baud rate divisor (0x24)
let PL011_FBRD   = 40     # Fractional baud rate divisor (0x28)
let PL011_LCRH   = 44     # Line control (0x2C)
let PL011_CR     = 48     # Control register (0x30)
let PL011_IMSC   = 56     # Interrupt mask (0x38)

## PL011 flag bits
let PL011_FR_TXFF = 32    # TX FIFO full (bit 5)
let PL011_FR_RXFE = 16    # RX FIFO empty (bit 4)

proc pl011_init(base):
    core.mmio_write32(base + PL011_CR, 0)       # Disable UART
    core.mmio_write32(base + PL011_IBRD, 1)     # 115200 baud (for 1.8MHz clock)
    core.mmio_write32(base + PL011_FBRD, 40)
    core.mmio_write32(base + PL011_LCRH, 96)    # 8N1, FIFO enable (0x60)
    core.mmio_write32(base + PL011_CR, 769)     # Enable UART, TX, RX (0x301)

proc pl011_send(base, byte):
    while core.mmio_read32(base + PL011_FR) & PL011_FR_TXFF:
        pass
    core.mmio_write32(base + PL011_DR, byte)

proc pl011_recv(base):
    while core.mmio_read32(base + PL011_FR) & PL011_FR_RXFE:
        pass
    return core.mmio_read32(base + PL011_DR) & 255

proc pl011_puts(base, s):
    let i = 0
    while i < len(s):
        pl011_send(base, ord(s[i]))
        i = i + 1
