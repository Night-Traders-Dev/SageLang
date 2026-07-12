import metal.core
import metal.vga
import assert

print "Testing MMIO persistence..."
core.mmio_write32(0x1234, 0xCAFEBABE)
assert.assert_equal(0xCAFEBABE, core.mmio_read32(0x1234), "MMIO read32 should match write32")

core.mmio_write8(0x5555, 0x42)
assert.assert_equal(0x42, core.mmio_read8(0x5555), "MMIO read8 should match write8")

print "Testing Port I/O persistence..."
core.outb(0x80, 0x99)
assert.assert_equal(0x99, core.inb(0x80), "Port inb should match outb")

core.outl(0xCF8, 0x80000000)
assert.assert_equal(0x80000000, core.inl(0xCF8), "Port inl should match outl")

print "Testing cpu_id simulation..."
core.mmio_write32(3489660928, 0) # Core 0
assert.assert_equal(0, core.cpu_id(), "cpu_id should return 0")
core.mmio_write32(3489660928, 1) # Core 1
assert.assert_equal(1, core.cpu_id(), "cpu_id should return 1")

print "Testing VGA rendering logic..."
vga.clear(vga.BLACK)
# Verify a cell was cleared (0xB8000 is 753664)
assert.assert_equal(32, core.mmio_read8(753664), "VGA cell should be space (0x20)")
assert.assert_equal(0, core.mmio_read8(753665), "VGA cell attr should be black (0)")

vga.puts(0, 0, "HI", (vga.WHITE << 4) | vga.BLACK)
assert.assert_equal(ord("H"), core.mmio_read8(753664), "VGA char should be H")
assert.assert_equal(0xF0, core.mmio_read8(753665), "VGA attr should be 0xF0")

print "Testing progress bar logic..."
vga.draw_progress_bar(0, 1, 10, 50, 0x0F)
# [====    ] -> 10 chars. 10-2=8 slots. 50% of 8 is 4.
# Index 0: [, 1-4: =, 5-8: space, 9: ]
let bar_pos = 753664 + (1 * 80 * 2)
assert.assert_equal(ord("["), core.mmio_read8(bar_pos), "Bar should start with [")
assert.assert_equal(ord("="), core.mmio_read8(bar_pos + 2), "Bar should have =")
assert.assert_equal(ord(" "), core.mmio_read8(bar_pos + 10), "Bar should have space")
assert.assert_equal(ord("]"), core.mmio_read8(bar_pos + 18), "Bar should end with ]")

print "All Forge metal tests passed!"
