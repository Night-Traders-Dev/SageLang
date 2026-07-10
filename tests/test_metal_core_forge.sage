import metal.core as core
import assert

# Test MMIO 32-bit persistence
core.mmio_write32(4096, 3735928559)
assert.assert_equal(3735928559, core.mmio_read32(4096), "MMIO 32-bit read should match written value")

# Test MMIO 8-bit persistence
core.mmio_write8(8192, 66)
assert.assert_equal(66, core.mmio_read8(8192), "MMIO 8-bit read should match written value")

# Test default value
assert.assert_equal(0, core.mmio_read32(12288), "Unwritten MMIO should return 0")

# Test RP2040 cpu_id
# By default it should be 0 if unwritten
assert.assert_equal(0, core.cpu_id(), "Default cpu_id should be 0")

# Mock RP2040 CPUID register for Core 1
core.mmio_write32(3489660928, 1)
assert.assert_equal(1, core.cpu_id(), "cpu_id should return 1 when SIO CPUID register is 1")

print "Metal core smoke test passed!"
