gc_disable()
# EXPECT: 0x00ff
# EXPECT: 1.5 MB
# EXPECT: Hello, World!
# EXPECT: 1, 2, 3
# EXPECT: 42.50%

import std.fmt

print fmt.to_hex(255, 4)
print fmt.format_bytes(1572864)
print fmt.template("Hello, {name}!", {"name": "World"})
print fmt.join([1, 2, 3], ", ")
print fmt.format_pct(0.425, 2)
