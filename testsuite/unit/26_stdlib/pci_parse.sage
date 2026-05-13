gc_disable()
# EXPECT: true
# EXPECT: Intel
# EXPECT: Network
# EXPECT: true
# EXPECT: true
# EXPECT: false
# EXPECT: memory
# EXPECT: 4026531840
# EXPECT: 2

import os.pci

proc mk_bytes(n):
    let bs = []
    for i in range(n):
        push(bs, 0)
    return bs

proc set_u16(bs, off, v):
    bs[off] = v & 255
    bs[off + 1] = (v >> 8) & 255

proc set_u32(bs, off, v):
    bs[off] = v & 255
    bs[off + 1] = (v >> 8) & 255
    bs[off + 2] = (v >> 16) & 255
    bs[off + 3] = (v >> 24) & 255

let bs = mk_bytes(256)

# Intel vendor (0x8086 = 32902)
set_u16(bs, 0, 32902)
# Device ID
set_u16(bs, 2, 4096)
# Command: IO + Memory + Bus Master
set_u16(bs, 4, 7)
# Status: capabilities list
set_u16(bs, 6, 16)
# Class: Network (2), Subclass: Ethernet (0)
bs[10] = 0
bs[11] = 2
# Header type 0
bs[14] = 0
# BAR0: memory mapped at 0xF0000000
set_u32(bs, 16, 4026531840)
# Interrupt line
bs[60] = 10
# Interrupt pin
bs[61] = 1

let cfg = pci.parse_config(bs)
print cfg["present"]
print cfg["vendor_name"]
print cfg["class_name"]
print cfg["bus_master"]
print cfg["memory_enabled"]
print cfg["multifunction"]

let bar = pci.decode_bar(cfg["bar0"])
print bar["type"]
print bar["address"]

# BDF test
let addr = pci.bdf(0, 2, 0)
print addr["device"]
