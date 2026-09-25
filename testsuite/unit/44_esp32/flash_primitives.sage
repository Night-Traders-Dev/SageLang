# The hw module is the documented "implementation defined per target" hook, and
# a second-stage bootloader needs three primitives from it that nothing else
# can provide: mem_read/mem_write are deliberately confined to mem_alloc
# regions by sage_mem_range_valid(), so memory-mapped flash is unreachable
# through them without weakening a memory-safety check.
#
# On a host build every hw.* native is a no-op stub, which is exactly what
# makes this testable off-target: the point here is that the emitter knows
# these three names, dispatches them, and that the emitted C is well formed and
# links -- not that a host can read flash.

# EXPECT: flash_read8
# EXPECT: flash_read32
# EXPECT: jump
# EXPECT: nil
# EXPECT: 0
# EXPECT: 0
# EXPECT: PASS

import hw

let a = hw.flash_read8(0x1000)
print("flash_read8")
let b = hw.flash_read32(0x1000)
print("flash_read32")
let c = hw.jump(0x40080000, 0x40081000)
print("jump")
print(c)
print(a)
print(b)
print("PASS")
