# Test architecture detection
# EXPECT: x86_64

# REQUIRES-ARCH: x86_64
# asm_arch() reports the host machine, so the expected value is this host's.
print asm_arch()
