## Tests for metal.vga primitives (clear, puts, draw_progress_bar)

import metal.core
import metal.vga
import assert

# 1. Test clear
vga.clear(vga.BLACK)
assert.assert_equal(32, core.mmio_read8(0xB8000), "VGA cell 0 char should be space")
assert.assert_equal(0, core.mmio_read8(0xB8001), "VGA cell 0 attr should be black")

# 2. Test puts
vga.puts(0, 0, "TEST", (vga.WHITE << 4) | vga.BLACK)
assert.assert_equal(ord("T"), core.mmio_read8(0xB8000), "VGA cell 0 char should be T")
assert.assert_equal(ord("E"), core.mmio_read8(0xB8002), "VGA cell 1 char should be E")
assert.assert_equal(ord("S"), core.mmio_read8(0xB8004), "VGA cell 2 char should be S")
assert.assert_equal(ord("T"), core.mmio_read8(0xB8006), "VGA cell 3 char should be T")
assert.assert_equal(0xF0, core.mmio_read8(0xB8001), "VGA attr should be 0xF0")

# 3. Test progress bar
vga.draw_progress_bar(0, 1, 10, 50, 0x0F)
let bar_addr = 0xB8000 + (1 * 80 * 2)
assert.assert_equal(ord("["), core.mmio_read8(bar_addr), "Progress bar start should be [")
assert.assert_equal(ord("="), core.mmio_read8(bar_addr + 2), "Progress bar slot 1 should be =")
assert.assert_equal(ord(" "), core.mmio_read8(bar_addr + 10), "Progress bar slot 5 should be space")
assert.assert_equal(ord("]"), core.mmio_read8(bar_addr + 18), "Progress bar end should be ]")

print("metal.vga tests passed successfully!")
