## metal.serial — UART Serial Port Driver for Bare-Metal
##
## Supports NS16550A (x86 COM ports) and PL011 (ARM/AArch64).
## Used for debug output, logging, and simple terminal I/O.

import metal.core

## ============================================================
## NS16550A UART (x86 COM1-COM4)
## ============================================================
let COM1 = 1016 # 0x3F8
let COM2 = 760 # 0x2F8
let COM3 = 1000 # 0x3E8
let COM4 = 744 # 0x2E8

## UART register offsets
let UART_DATA = 0 # Data register (R/W)
let UART_IER = 1 # Interrupt Enable
let UART_FCR = 2 # FIFO Control
let UART_LCR = 3 # Line Control
let UART_MCR = 4 # Modem Control
let UART_LSR = 5 # Line Status
let UART_MSR = 6 # Modem Status

## Initialize a COM port at the given baud rate.
proc uart_init(port, baud):
    uart_init_ext(port, baud, 8, 1, 0)

## Initialize a COM port with extended settings (baud, data bits, stop bits, parity).
## Parity: 0=None, 1=Odd, 2=Even.

proc uart_init_ext(port, baud, data_bits, stop_bits, parity):
    if not baud_rate_valid(baud):
        core.panic("Unsupported UART baud rate: " + str(baud))
    let divisor = 115200 / baud
    core.outb(port + UART_IER, 0) # Disable interrupts
    core.outb(port + UART_LCR, 128) # Enable DLAB
    core.outb(port + UART_DATA, divisor & 255) # Divisor low byte
    core.outb(port + UART_IER, divisor >> 8) # Divisor high byte

    # Build LCR value
    let lcr = data_bits - 5 # 5=0, 6=1, 7=2, 8=3
    if stop_bits == 2:
        lcr = lcr | 4
    end
    if parity == 1: # Odd
        lcr = lcr | 8
    elif parity == 2: # Even
        lcr = lcr | 24
    end
    core.outb(port + UART_LCR, lcr)
    core.outb(port + UART_FCR, 199) # Enable FIFO, clear, 14-byte threshold
    core.outb(port + UART_MCR, 11) # IRQs enabled, RTS/DSR set

## Check if transmit buffer is empty.
proc uart_tx_ready(port):
    return (core.inb(port + UART_LSR) & 32) != 0

## Check if the transmit shift register is completely empty.
## Bit 6 (TEMT) is set if both the THR and the Shift Register are empty.

proc uart_tx_empty(port):
    return (core.inb(port + UART_LSR) & 64) != 0

## Check if receive data is available.
proc uart_rx_ready(port):
    return (core.inb(port + UART_LSR) & 1) != 0

## Send a single byte.
proc uart_send(port, byte):
    while not uart_tx_ready(port):
        core.io_wait()
    core.outb(port + UART_DATA, byte)

## Receive a single byte (blocking).
proc uart_recv(port):
    while not uart_rx_ready(port):
        core.io_wait()
    return core.inb(port + UART_DATA)

## Send a string.
proc uart_puts(port, s):
    let i = 0
    while i < len(s):
        uart_send(port, ord(s[i]))
        if s[i] == chr(10):
            uart_send(port, 13)
        i = i + 1

## Receive a single byte with timeout (returns nil on timeout).
proc uart_read_timeout(port, timeout_ms):
    let elapsed_ms = 0
    while not uart_rx_ready(port):
        if elapsed_ms >= timeout_ms:
            return nil
        core.delay_ms(1)
        elapsed_ms = elapsed_ms + 1
    return core.inb(port + UART_DATA)

## Read a line (until \n or \r) from the UART with echo and backspace support.
proc uart_readline(port):
    let line_str = ""
    while true:
        let byte_val = uart_recv(port)
        if byte_val == 10 or byte_val == 13:
            uart_send(port, 10)
            uart_send(port, 13)
            break
        if byte_val == 8 or byte_val == 127:
            if len(line_str) > 0:
                # Echo backspace, space, backspace to clear character on terminal
                uart_send(port, 8)
                uart_send(port, 32)
                uart_send(port, 8)
                line_str = slice(line_str, 0, len(line_str) - 1)
        else:
            let char_val = chr(byte_val)
            line_str = line_str + char_val
            uart_send(port, byte_val)
    return line_str

## Flush the receive buffer.
proc uart_flush_rx(port):
    while uart_rx_ready(port):
        core.inb(port + UART_DATA)

## ============================================================
## PL011 UART (ARM/AArch64)
## ============================================================
## PL011 register offsets
let PL011_DR = 0 # Data register
let PL011_FR = 24 # Flag register (0x18)
let PL011_IBRD = 36 # Integer baud rate divisor (0x24)
let PL011_FBRD = 40 # Fractional baud rate divisor (0x28)
let PL011_LCRH = 44 # Line control (0x2C)
let PL011_CR = 48 # Control register (0x30)
let PL011_IMSC = 56 # Interrupt mask (0x38)

## PL011 flag bits
let PL011_FR_TXFF = 32 # TX FIFO full (bit 5)
let PL011_FR_RXFE = 16 # RX FIFO empty (bit 4)

## Check if PL011 transmit buffer is ready (not full).
proc pl011_tx_ready(base):
    return (core.mmio_read32(base + PL011_FR) & PL011_FR_TXFF) == 0

## Check if the PL011 transmitter is completely idle.
## Returns true if TX FIFO is empty (bit 7) and UART is not busy (bit 3).

proc pl011_tx_empty(base):
    let fr = core.mmio_read32(base + PL011_FR)
    return (fr & 128) != 0 and (fr & 8) == 0

## Check if PL011 receive data is available (not empty).
proc pl011_rx_ready(base):
    return (core.mmio_read32(base + PL011_FR) & PL011_FR_RXFE) == 0

## Initialize PL011 UART at the given base address.
proc pl011_init(base):
    pl011_init_ext(base, 115200, 1843200, 8, 1, 0)

## Send a single byte via PL011 at the given base address.
proc pl011_send(base, byte):
    while not pl011_tx_ready(base):
        pass
    core.mmio_write32(base + PL011_DR, byte)

## Receive a single byte via PL011 (blocking) at the given base address.
proc pl011_recv(base):
    while not pl011_rx_ready(base):
        pass
    return core.mmio_read32(base + PL011_DR) & 255

## Send a string via PL011 at the given base address.
proc pl011_puts(base, s):
    let j = 0
    while j < len(s):
        pl011_send(base, ord(s[j]))
        if s[j] == chr(10):
            pl011_send(base, 13)
        j = j + 1

## Initialize PL011 UART at a specific baud rate and reference clock.
proc pl011_init_at_baud(base, baud, ref_clock):
    pl011_init_ext(base, baud, ref_clock, 8, 1, 0)

## Initialize PL011 UART with extended settings.
proc pl011_init_ext(base, baud, ref_clock, data_bits, stop_bits, parity):
    if not baud_rate_valid(baud):
        core.panic("Unsupported PL011 baud rate: " + str(baud))
    core.mmio_write32(base + PL011_CR, 0) # Disable UART

    # Baud rate divisor = ref_clock / (16 * baud)
    # IBRD = integer part, FBRD = fractional part
    let baud_div = (ref_clock * 4) / baud
    let ibrd = baud_div / 64
    let fbrd = baud_div & 63
    core.mmio_write32(base + PL011_IBRD, ibrd)
    core.mmio_write32(base + PL011_FBRD, fbrd)

    # Line control (LCRH)
    let lcrh = 16 # FIFO enable (FEN)
    # WLEN: 5=0x00, 6=0x20, 7=0x40, 8=0x60
    lcrh = lcrh | ((data_bits - 5) << 5)
    if stop_bits == 2:
        lcrh = lcrh | 8 # STP2
    end
    if parity == 1: # Odd
        lcrh = lcrh | 2 # PEN=1, EPS=0
    elif parity == 2: # Even
        lcrh = lcrh | 6 # PEN=1, EPS=1
    end
    core.mmio_write32(base + PL011_LCRH, lcrh)
    core.mmio_write32(base + PL011_CR, 769) # Enable UART, TX, RX (0x301)

## Receive a single byte via PL011 with timeout (returns nil on timeout).
proc pl011_read_timeout(base, timeout_ms):
    let elapsed_ms_pl = 0
    while not pl011_rx_ready(base):
        if elapsed_ms_pl >= timeout_ms:
            return nil
        core.delay_ms(1)
        elapsed_ms_pl = elapsed_ms_pl + 1
    return core.mmio_read32(base + PL011_DR) & 255

## Read a line (until \n or \r) from the PL011 UART with echo and backspace support.
proc pl011_readline(base):
    let line_str_pl = ""
    while true:
        let byte_val_pl = pl011_recv(base)
        if byte_val_pl == 10 or byte_val_pl == 13:
            pl011_send(base, 10)
            pl011_send(base, 13)
            break
        if byte_val_pl == 8 or byte_val_pl == 127:
            if len(line_str_pl) > 0:
                pl011_send(base, 8)
                pl011_send(base, 32)
                pl011_send(base, 8)
                line_str_pl = slice(line_str_pl, 0, len(line_str_pl) - 1)
        else:
            let char_val_pl = chr(byte_val_pl)
            line_str_pl = line_str_pl + char_val_pl
            pl011_send(base, byte_val_pl)
    return line_str_pl

## Flush the PL011 receive buffer at the given base address.
proc pl011_flush_rx(base):
    while pl011_rx_ready(base):
        core.mmio_read32(base + PL011_DR)

## Check if a baud rate is valid/supported.
proc baud_rate_valid(baud):
    let valid_rates = [300, 600, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
    let idx = 0
    while idx < len(valid_rates):
        if baud == valid_rates[idx]:
            return true
        idx = idx + 1
    return false
