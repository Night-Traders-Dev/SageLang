gc_disable()
# EXPECT: x86 config ok
# EXPECT: aarch64 config ok
# EXPECT: riscv64 config ok
# EXPECT: x86 init sequence ok
# EXPECT: aarch64 init sequence ok
# EXPECT: riscv64 init sequence ok
# EXPECT: multi-arch dispatch ok
# Test serial UART configuration for all architectures

from os.serial import create_config, init_sequence
from os.serial import pl011_config, pl011_init_sequence
from os.serial import riscv64_uart_config, riscv64_uart_init_sequence
from os.serial import uart_init

# x86 16550 PIO
let cfg_x86 = create_config(1016, 115200, 8, 1, 0)
if cfg_x86["base"] == 1016 and cfg_x86["baud"] == 115200 and cfg_x86["lcr"] == 3:
    print "x86 config ok"

# aarch64 PL011
let cfg_arm = pl011_config(150994944, 115200)
if cfg_arm["type"] == "pl011" and cfg_arm["base"] == 150994944:
    print "aarch64 config ok"

# riscv64 16550 MMIO
let cfg_rv = riscv64_uart_config(268435456, 115200)
if cfg_rv["type"] == "ns16550_mmio" and cfg_rv["base"] == 268435456:
    print "riscv64 config ok"

# Init sequences
let seq_x86 = init_sequence(cfg_x86)
if len(seq_x86) == 7:
    print "x86 init sequence ok"

let seq_arm = pl011_init_sequence(150994944, 115200)
if len(seq_arm) == 5:
    print "aarch64 init sequence ok"

let seq_rv = riscv64_uart_init_sequence(268435456, 115200)
if len(seq_rv) == 7:
    print "riscv64 init sequence ok"

# Multi-arch dispatcher
let u1 = uart_init("x86_64", 1016, 115200)
let u2 = uart_init("aarch64", 150994944, 115200)
let u3 = uart_init("riscv64", 268435456, 115200)
if u1["arch"] == "x86" and u2["arch"] == "aarch64" and u3["arch"] == "riscv64":
    print "multi-arch dispatch ok"
