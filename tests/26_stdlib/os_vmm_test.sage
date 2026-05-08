# EXPECT: page_nx_ok
# EXPECT: vmm_init_ok
# EXPECT: map_ok
# EXPECT: translate_ok
# EXPECT: unmap_ok
# EXPECT: multiarch_ok
# EXPECT: PASS
import os.kernel.vmm as vmm

# PAGE_NX must be exactly 2^63 = 9223372036854775808
if vmm.PAGE_NX == 9223372036854775808:
    print "page_nx_ok"
end

# vmm_init x86_64
let state = vmm.vmm_init("x86_64")
if state["arch"] == "x86_64":
    if dict_has(state, "entries"):
        print "vmm_init_ok"
    end
end

# map/translate/unmap
vmm.init()
vmm.map_page(8192, 4096, vmm.PAGE_PRESENT + vmm.PAGE_WRITABLE)
if vmm.is_mapped(8192) == true:
    let phys = vmm.get_physical(8192)
    if phys == 4096:
        print "map_ok"
    end
end

# Translate with page offset
let phys2 = vmm.get_physical(8192 + 100)
if phys2 == 4096 + 100:
    print "translate_ok"
end

# Unmap
vmm.unmap_page(8192)
if vmm.is_mapped(8192) == false:
    print "unmap_ok"
end

# Multi-arch init
let aarch64_state = vmm.vmm_init("aarch64")
let rv64_state = vmm.vmm_init("riscv64")
if aarch64_state["arch"] == "aarch64" and rv64_state["arch"] == "riscv64":
    print "multiarch_ok"
end

print "PASS"
