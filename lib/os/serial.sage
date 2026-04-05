# Serial/UART port driver for x86 bare-metal debugging
# Provides port I/O abstractions for COM1-COM4 debug output
# Used in kernel and bootloader development for early console output

# Standard x86 COM port base addresses
let COM1 = 1016
let COM2 = 760
let COM3 = 1000
let COM4 = 744

# UART register offsets from base
let REG_DATA = 0
let REG_INT_ENABLE = 1
let REG_FIFO_CTRL = 2
let REG_LINE_CTRL = 3
let REG_MODEM_CTRL = 4
let REG_LINE_STATUS = 5
let REG_MODEM_STATUS = 6
let REG_SCRATCH = 7

# Divisor latch registers (when DLAB=1)
let REG_DIVISOR_LO = 0
let REG_DIVISOR_HI = 1

# Line status register bits
let LSR_DATA_READY = 1
let LSR_OVERRUN_ERROR = 2
let LSR_PARITY_ERROR = 4
let LSR_FRAMING_ERROR = 8
let LSR_BREAK_INDICATOR = 16
let LSR_TX_HOLDING_EMPTY = 32
let LSR_TX_EMPTY = 64
let LSR_FIFO_ERROR = 128

# Line control register bits
let LCR_5_BITS = 0
let LCR_6_BITS = 1
let LCR_7_BITS = 2
let LCR_8_BITS = 3
let LCR_1_STOP = 0
let LCR_2_STOP = 4
let LCR_NO_PARITY = 0
let LCR_ODD_PARITY = 8
let LCR_EVEN_PARITY = 24
let LCR_DLAB = 128

# Modem control register bits
let MCR_DTR = 1
let MCR_RTS = 2
let MCR_OUT1 = 4
let MCR_OUT2 = 8
let MCR_LOOPBACK = 16

# Common baud rate divisors (115200 / baud)
let BAUD_115200 = 1
let BAUD_57600 = 2
let BAUD_38400 = 3
let BAUD_19200 = 6
let BAUD_9600 = 12
let BAUD_4800 = 24
let BAUD_2400 = 48
let BAUD_1200 = 96

proc baud_divisor(baud):
    return (115200 / baud) | 0
end

# Build a serial port configuration descriptor
proc create_config(base_port, baud, data_bits, stop_bits, parity):
    let cfg = {}
    cfg["base"] = base_port
    cfg["divisor"] = baud_divisor(baud)
    cfg["baud"] = baud
    cfg["data_bits"] = data_bits
    cfg["stop_bits"] = stop_bits
    cfg["parity"] = parity
    # Build LCR value
    let lcr = 0
    if data_bits == 5:
        lcr = 0
    end
    if data_bits == 6:
        lcr = 1
    end
    if data_bits == 7:
        lcr = 2
    end
    if data_bits == 8:
        lcr = 3
    end
    if stop_bits == 2:
        lcr = lcr + 4
    end
    if parity == 1:
        lcr = lcr + 8
    end
    if parity == 2:
        lcr = lcr + 24
    end
    cfg["lcr"] = lcr
    return cfg
end

# Default config: COM1, 115200 baud, 8N1
proc default_config():
    return create_config(1016, 115200, 8, 1, 0)
end

# Generate the initialization sequence as a list of {port, value} pairs
# This is useful for codegen backends that emit port I/O instructions
proc init_sequence(cfg):
    let base = cfg["base"]
    let seq = []
    # Disable interrupts
    let s1 = {}
    s1["port"] = base + 1
    s1["value"] = 0
    push(seq, s1)
    # Enable DLAB
    let s2 = {}
    s2["port"] = base + 3
    s2["value"] = 128
    push(seq, s2)
    # Set divisor low byte
    let s3 = {}
    s3["port"] = base + 0
    s3["value"] = cfg["divisor"] & 255
    push(seq, s3)
    # Set divisor high byte
    let s4 = {}
    s4["port"] = base + 1
    s4["value"] = (cfg["divisor"] >> 8) & 255
    push(seq, s4)
    # Set line control (clears DLAB)
    let s5 = {}
    s5["port"] = base + 3
    s5["value"] = cfg["lcr"]
    push(seq, s5)
    # Enable FIFO, clear, 14-byte threshold
    let s6 = {}
    s6["port"] = base + 2
    s6["value"] = 199
    push(seq, s6)
    # Set modem control: DTR + RTS + OUT2
    let s7 = {}
    s7["port"] = base + 4
    s7["value"] = 11
    push(seq, s7)
    return seq
end

# Generate a loopback test sequence
proc loopback_test_sequence(cfg):
    let base = cfg["base"]
    let seq = []
    # Set loopback mode
    let s1 = {}
    s1["port"] = base + 4
    s1["value"] = 30
    push(seq, s1)
    # Write test byte
    let s2 = {}
    s2["port"] = base + 0
    s2["value"] = 174
    push(seq, s2)
    # Expected: read back 174 from data port
    let s3 = {}
    s3["port"] = base + 0
    s3["value"] = 174
    s3["action"] = "read_expect"
    push(seq, s3)
    # Restore normal mode
    let s4 = {}
    s4["port"] = base + 4
    s4["value"] = 15
    push(seq, s4)
    return seq
end

# Encode a string as a list of byte values for transmission
proc encode_string(text):
    let bytes = []
    for i in range(len(text)):
        push(bytes, ord(text[i]))
    end
    return bytes
end

# Encode a string with newline (CR+LF)
proc encode_line(text):
    let bytes = encode_string(text)
    push(bytes, 13)
    push(bytes, 10)
    return bytes
end

# Generate write sequence for a string
proc write_string_sequence(cfg, text):
    let base = cfg["base"]
    let bytes = encode_string(text)
    let seq = []
    for i in range(len(bytes)):
        # Wait for TX empty (read LSR, check bit 5)
        let wait = {}
        wait["port"] = base + 5
        wait["action"] = "wait_bit"
        wait["bit"] = 5
        push(seq, wait)
        # Write byte
        let wr = {}
        wr["port"] = base + 0
        wr["value"] = bytes[i]
        push(seq, wr)
    end
    return seq
end

# Format a hex byte string
proc hex_byte(b):
    let hi = (b >> 4) & 15
    let lo = b & 15
    let digits = "0123456789abcdef"
    return digits[hi] + digits[lo]
end

# Format number as hex string
proc to_hex(value, width):
    let result = ""
    let remaining = width
    while remaining > 0:
        let byte_val = value & 255
        result = hex_byte(byte_val) + result
        value = value >> 8
        remaining = remaining - 1
    end
    return "0x" + result
end

# Format a debug log line with timestamp placeholder
proc format_debug(tag, message):
    return "[" + tag + "] " + message
end

# Common port name lookup
proc port_name(base):
    if base == 1016:
        return "COM1"
    end
    if base == 760:
        return "COM2"
    end
    if base == 1000:
        return "COM3"
    end
    if base == 744:
        return "COM4"
    end
    return "COM?"
end

# ================================================================
# aarch64 PL011 UART support
# ================================================================
# PL011 is the standard ARM UART (used by QEMU virt, Raspberry Pi, etc.)
# All registers are memory-mapped at base_addr + offset.

let PL011_DR   = 0
let PL011_FR   = 24
let PL011_IBRD = 36
let PL011_FBRD = 40
let PL011_LCRH = 44
let PL011_CR   = 48

proc pl011_config(base_addr, baud):
    let cfg = {}
    cfg["type"] = "pl011"
    cfg["base"] = base_addr
    cfg["baud"] = baud
    # PL011 uses a reference clock; 48 MHz is common (RPi, QEMU)
    let ref_clock = 48000000
    cfg["ref_clock"] = ref_clock
    # Integer baud rate divisor: IBRD = ref_clock / (16 * baud)
    cfg["ibrd"] = ref_clock / (16 * baud)
    # Fractional baud rate divisor: FBRD = ((remainder * 64) + 0.5)
    let remainder = ref_clock - (cfg["ibrd"] * 16 * baud)
    cfg["fbrd"] = ((remainder * 64 * 2) / (16 * baud) + 1) / 2
    # Line control: 8-bit word length (bits 5-6 = 0b11), FIFO enable (bit 4)
    cfg["lcrh"] = 112
    # Control register: UART enable (bit 0), TX enable (bit 8), RX enable (bit 9)
    cfg["cr"] = 769
    cfg["dr_addr"] = base_addr + PL011_DR
    cfg["fr_addr"] = base_addr + PL011_FR
    cfg["ibrd_addr"] = base_addr + PL011_IBRD
    cfg["fbrd_addr"] = base_addr + PL011_FBRD
    cfg["lcrh_addr"] = base_addr + PL011_LCRH
    cfg["cr_addr"] = base_addr + PL011_CR
    return cfg
end

proc pl011_init_sequence(base_addr, baud):
    let cfg = pl011_config(base_addr, baud)
    let seq = []
    # Step 1: Disable UART (CR = 0)
    let s1 = {}
    s1["addr"] = cfg["cr_addr"]
    s1["value"] = 0
    push(seq, s1)
    # Step 2: Set integer baud rate divisor
    let s2 = {}
    s2["addr"] = cfg["ibrd_addr"]
    s2["value"] = cfg["ibrd"]
    push(seq, s2)
    # Step 3: Set fractional baud rate divisor
    let s3 = {}
    s3["addr"] = cfg["fbrd_addr"]
    s3["value"] = cfg["fbrd"]
    push(seq, s3)
    # Step 4: Set line control (8N1, FIFO enabled)
    let s4 = {}
    s4["addr"] = cfg["lcrh_addr"]
    s4["value"] = cfg["lcrh"]
    push(seq, s4)
    # Step 5: Enable UART, TX, and RX
    let s5 = {}
    s5["addr"] = cfg["cr_addr"]
    s5["value"] = cfg["cr"]
    push(seq, s5)
    return seq
end

# ================================================================
# riscv64 16550-compatible UART (MMIO)
# ================================================================
# RISC-V platforms typically use a 16550-compatible UART
# mapped to MMIO addresses rather than x86 I/O ports.
# The register layout is the same as the x86 16550, but
# accessed via memory-mapped reads/writes.

proc riscv64_uart_config(base_addr, baud):
    let cfg = {}
    cfg["type"] = "ns16550_mmio"
    cfg["base"] = base_addr
    cfg["baud"] = baud
    # RISC-V UART reference clock varies; 1.8432 MHz is standard 16550
    let ref_clock = 1843200
    cfg["ref_clock"] = ref_clock
    cfg["divisor"] = ref_clock / (16 * baud)
    # Register addresses (same offsets as x86 16550, but MMIO)
    cfg["data_addr"] = base_addr + 0
    cfg["ier_addr"] = base_addr + 1
    cfg["fcr_addr"] = base_addr + 2
    cfg["lcr_addr"] = base_addr + 3
    cfg["mcr_addr"] = base_addr + 4
    cfg["lsr_addr"] = base_addr + 5
    cfg["dll_addr"] = base_addr + 0
    cfg["dlm_addr"] = base_addr + 1
    # 8N1 config
    cfg["lcr"] = 3
    return cfg
end

proc riscv64_uart_init_sequence(base_addr, baud):
    let cfg = riscv64_uart_config(base_addr, baud)
    let seq = []
    # Step 1: Disable interrupts
    let s1 = {}
    s1["addr"] = cfg["ier_addr"]
    s1["value"] = 0
    push(seq, s1)
    # Step 2: Enable DLAB (set bit 7 of LCR)
    let s2 = {}
    s2["addr"] = cfg["lcr_addr"]
    s2["value"] = 128
    push(seq, s2)
    # Step 3: Set divisor low byte
    let s3 = {}
    s3["addr"] = cfg["dll_addr"]
    s3["value"] = cfg["divisor"] & 255
    push(seq, s3)
    # Step 4: Set divisor high byte
    let s4 = {}
    s4["addr"] = cfg["dlm_addr"]
    s4["value"] = (cfg["divisor"] >> 8) & 255
    push(seq, s4)
    # Step 5: Set line control (8N1, clear DLAB)
    let s5 = {}
    s5["addr"] = cfg["lcr_addr"]
    s5["value"] = cfg["lcr"]
    push(seq, s5)
    # Step 6: Enable FIFO, clear, 14-byte threshold
    let s6 = {}
    s6["addr"] = cfg["fcr_addr"]
    s6["value"] = 199
    push(seq, s6)
    # Step 7: Set modem control: DTR + RTS + OUT2
    let s7 = {}
    s7["addr"] = cfg["mcr_addr"]
    s7["value"] = 11
    push(seq, s7)
    return seq
end

# ================================================================
# Assembly emission helpers
# ================================================================

let NL = chr(10)
let TAB = chr(9)

@inline
proc _asm(inst, ops):
    if ops == "":
        return TAB + inst + NL
    end
    return TAB + inst + " " + ops + NL
end

@inline
proc _lbl(name):
    return name + ":" + NL
end

# ================================================================
# x86_64 serial assembly emission (port I/O)
# ================================================================

@inline
proc emit_serial_init_x86(base_port):
    let p = str(base_port)
    let a = ""
    a = a + _lbl("serial_init")
    a = a + _asm("movw", "$" + str(base_port + 1) + ", %dx")
    a = a + _asm("xorb", "%al, %al")
    a = a + _asm("outb", "%al, %dx")
    a = a + _asm("movw", "$" + str(base_port + 3) + ", %dx")
    a = a + _asm("movb", "$0x80, %al")
    a = a + _asm("outb", "%al, %dx")
    a = a + _asm("movw", "$" + str(base_port) + ", %dx")
    a = a + _asm("movb", "$0x01, %al")
    a = a + _asm("outb", "%al, %dx")
    a = a + _asm("movw", "$" + str(base_port + 1) + ", %dx")
    a = a + _asm("xorb", "%al, %al")
    a = a + _asm("outb", "%al, %dx")
    a = a + _asm("movw", "$" + str(base_port + 3) + ", %dx")
    a = a + _asm("movb", "$0x03, %al")
    a = a + _asm("outb", "%al, %dx")
    a = a + _asm("movw", "$" + str(base_port + 2) + ", %dx")
    a = a + _asm("movb", "$0xC7, %al")
    a = a + _asm("outb", "%al, %dx")
    a = a + _asm("movw", "$" + str(base_port + 4) + ", %dx")
    a = a + _asm("movb", "$0x0B, %al")
    a = a + _asm("outb", "%al, %dx")
    a = a + _asm("ret", "")
    return a
end

@inline
proc emit_serial_tx_x86(base_port):
    let a = ""
    a = a + _lbl(".Lwait_tx_x86")
    a = a + _asm("movw", "$" + str(base_port + 5) + ", %dx")
    a = a + _asm("inb", "%dx, %al")
    a = a + _asm("testb", "$0x20, %al")
    a = a + _asm("jz", ".Lwait_tx_x86")
    a = a + _asm("movw", "$" + str(base_port) + ", %dx")
    a = a + _asm("movb", "%dil, %al")
    a = a + _asm("outb", "%al, %dx")
    return a
end

@inline
proc emit_serial_putchar_x86(base_port):
    let a = ""
    a = a + _lbl("serial_putchar")
    a = a + _asm("pushq", "%rdx")
    a = a + _asm("pushq", "%rax")
    a = a + emit_serial_tx_x86(base_port)
    a = a + _asm("popq", "%rax")
    a = a + _asm("popq", "%rdx")
    a = a + _asm("ret", "")
    return a
end

@inline
proc emit_serial_puts_x86(base_port):
    let a = ""
    a = a + _lbl("serial_puts")
    a = a + _asm("pushq", "%rsi")
    a = a + _asm("pushq", "%rdi")
    a = a + _lbl(".Lputs_loop_x86")
    a = a + _asm("lodsb", "")
    a = a + _asm("testb", "%al, %al")
    a = a + _asm("jz", ".Lputs_done_x86")
    a = a + _asm("movb", "%al, %dil")
    a = a + _asm("call", "serial_putchar")
    a = a + _asm("jmp", ".Lputs_loop_x86")
    a = a + _lbl(".Lputs_done_x86")
    a = a + _asm("popq", "%rdi")
    a = a + _asm("popq", "%rsi")
    a = a + _asm("ret", "")
    return a
end

# ================================================================
# aarch64 serial assembly emission (PL011 MMIO)
# ================================================================

@inline
proc emit_serial_init_aarch64(base_addr):
    let base = "0x" + str(base_addr)
    let a = ""
    a = a + _lbl("serial_init")
    a = a + _asm("ldr", "x1, =" + base)
    a = a + _asm("str", "wzr, [x1, #48]")
    a = a + _asm("mov", "w2, #26")
    a = a + _asm("str", "w2, [x1, #36]")
    a = a + _asm("mov", "w2, #3")
    a = a + _asm("str", "w2, [x1, #40]")
    a = a + _asm("mov", "w2, #0x70")
    a = a + _asm("str", "w2, [x1, #44]")
    a = a + _asm("mov", "w2, #0x301")
    a = a + _asm("str", "w2, [x1, #48]")
    a = a + _asm("ret", "")
    return a
end

@inline
proc emit_serial_tx_aarch64(base_addr):
    let base = "0x" + str(base_addr)
    let a = ""
    a = a + _asm("ldr", "x1, =" + base)
    a = a + _lbl(".Lwait_tx_a64")
    a = a + _asm("ldr", "w2, [x1, #24]")
    a = a + _asm("tst", "w2, #0x20")
    a = a + _asm("b.ne", ".Lwait_tx_a64")
    a = a + _asm("str", "w0, [x1]")
    return a
end

@inline
proc emit_serial_putchar_aarch64(base_addr):
    let a = ""
    a = a + _lbl("serial_putchar")
    a = a + emit_serial_tx_aarch64(base_addr)
    a = a + _asm("ret", "")
    return a
end

@inline
proc emit_serial_puts_aarch64(base_addr):
    let a = ""
    a = a + _lbl("serial_puts")
    a = a + _asm("stp", "x29, x30, [sp, #-16]!")
    a = a + _asm("mov", "x19, x0")
    a = a + _lbl(".Lputs_loop_a64")
    a = a + _asm("ldrb", "w0, [x19], #1")
    a = a + _asm("cbz", "w0, .Lputs_done_a64")
    a = a + _asm("bl", "serial_putchar")
    a = a + _asm("b", ".Lputs_loop_a64")
    a = a + _lbl(".Lputs_done_a64")
    a = a + _asm("ldp", "x29, x30, [sp], #16")
    a = a + _asm("ret", "")
    return a
end

# ================================================================
# riscv64 serial assembly emission (16550 MMIO)
# ================================================================

@inline
proc emit_serial_init_riscv64(base_addr):
    let base = "0x" + str(base_addr)
    let a = ""
    a = a + _lbl("serial_init")
    a = a + _asm("li", "t0, " + base)
    a = a + _asm("sb", "zero, 1(t0)")
    a = a + _asm("li", "t1, 0x80")
    a = a + _asm("sb", "t1, 3(t0)")
    a = a + _asm("li", "t1, 1")
    a = a + _asm("sb", "t1, 0(t0)")
    a = a + _asm("sb", "zero, 1(t0)")
    a = a + _asm("li", "t1, 3")
    a = a + _asm("sb", "t1, 3(t0)")
    a = a + _asm("li", "t1, 0xC7")
    a = a + _asm("sb", "t1, 2(t0)")
    a = a + _asm("li", "t1, 0x0B")
    a = a + _asm("sb", "t1, 4(t0)")
    a = a + _asm("ret", "")
    return a
end

@inline
proc emit_serial_tx_riscv64(base_addr):
    let base = "0x" + str(base_addr)
    let a = ""
    a = a + _asm("li", "t0, " + base)
    a = a + _lbl(".Lwait_tx_rv64")
    a = a + _asm("lb", "t1, 5(t0)")
    a = a + _asm("andi", "t1, t1, 0x20")
    a = a + _asm("beqz", "t1, .Lwait_tx_rv64")
    a = a + _asm("sb", "a0, 0(t0)")
    return a
end

@inline
proc emit_serial_putchar_riscv64(base_addr):
    let a = ""
    a = a + _lbl("serial_putchar")
    a = a + emit_serial_tx_riscv64(base_addr)
    a = a + _asm("ret", "")
    return a
end

@inline
proc emit_serial_puts_riscv64(base_addr):
    let a = ""
    a = a + _lbl("serial_puts")
    a = a + _asm("addi", "sp, sp, -16")
    a = a + _asm("sd", "ra, 8(sp)")
    a = a + _asm("sd", "s0, 0(sp)")
    a = a + _asm("mv", "s0, a0")
    a = a + _lbl(".Lputs_loop_rv64")
    a = a + _asm("lb", "a0, 0(s0)")
    a = a + _asm("beqz", "a0, .Lputs_done_rv64")
    a = a + _asm("call", "serial_putchar")
    a = a + _asm("addi", "s0, s0, 1")
    a = a + _asm("j", ".Lputs_loop_rv64")
    a = a + _lbl(".Lputs_done_rv64")
    a = a + _asm("ld", "ra, 8(sp)")
    a = a + _asm("ld", "s0, 0(sp)")
    a = a + _asm("addi", "sp, sp, 16")
    a = a + _asm("ret", "")
    return a
end

# ================================================================
# Multi-architecture UART dispatcher
# ================================================================

proc uart_init(arch, base_addr, baud):
    if arch == "x86" or arch == "x86_64":
        let cfg = create_config(base_addr, baud, 8, 1, 0)
        let result = {}
        result["arch"] = "x86"
        result["type"] = "ns16550_pio"
        result["config"] = cfg
        result["init_sequence"] = init_sequence(cfg)
        return result
    end
    if arch == "aarch64":
        let result = {}
        result["arch"] = "aarch64"
        result["type"] = "pl011"
        result["config"] = pl011_config(base_addr, baud)
        result["init_sequence"] = pl011_init_sequence(base_addr, baud)
        return result
    end
    if arch == "riscv64":
        let result = {}
        result["arch"] = "riscv64"
        result["type"] = "ns16550_mmio"
        result["config"] = riscv64_uart_config(base_addr, baud)
        result["init_sequence"] = riscv64_uart_init_sequence(base_addr, baud)
        return result
    end
    return nil
end
