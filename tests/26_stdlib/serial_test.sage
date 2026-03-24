gc_disable()
# EXPECT: COM1
# EXPECT: 115200
# EXPECT: 3
# EXPECT: 7
# EXPECT: 72
# EXPECT: 0x0a
# EXPECT: [KERN] booting

import os.serial

let cfg = serial.default_config()
print serial.port_name(cfg["base"])
print cfg["baud"]
print cfg["lcr"]

let seq = serial.init_sequence(cfg)
print len(seq)

let bytes = serial.encode_string("Hello")
print bytes[0]

print serial.to_hex(10, 1)
print serial.format_debug("KERN", "booting")
