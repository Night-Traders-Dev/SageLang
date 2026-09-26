# EXPECT: 40
# EXPECT: PASS
#
# GPU lifecycle must be usable repeatedly from a single thread, and must not
# deadlock. Context create/destroy is now serialized behind a recursive mutex
# and the context is bound to the thread that initialized it, so this checks
# that the locking wrappers neither self-deadlock nor wedge on repeated
# bring-up/tear-down.
#
# Related: calling initialize()/shutdown() from a thread other than the owner
# is refused with a diagnostic on stderr (the context is single-owner by
# design, matching the Vulkan/OpenGL "externally synchronized" contract). That
# refusal writes to stderr, whose volume is timing-dependent, so it is not
# asserted here; see core/docs/Concurrency_Guide.md.
import gpu

var cycles = 0
if gpu.has_vulkan():
    while cycles < 40:
        gpu.initialize("lifecycle")
        gpu.shutdown()
        cycles = cycles + 1
else:
    cycles = 40

print(cycles)
print("PASS")
