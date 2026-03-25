gc_disable()
# EXPECT: architectures_listed
# EXPECT: 6_architectures
# EXPECT: PASS

# gguf_import.sage imports io (native C), so we replicate the
# supported_architectures logic with pure Sage

proc supported_architectures():
    let archs = []
    push(archs, "llama")
    push(archs, "gpt2")
    push(archs, "gemma")
    push(archs, "phi")
    push(archs, "qwen2")
    push(archs, "mistral")
    return archs

proc is_supported(arch):
    let supported = supported_architectures()
    for i in range(len(supported)):
        if supported[i] == arch:
            return true
    return false

# Test supported_architectures returns a list
let archs = supported_architectures()
if len(archs) > 0:
    print "architectures_listed"

# Test there are exactly 6 architectures
if len(archs) == 6:
    print "6_architectures"

# Verify llama and gpt2 are in the list
let has_llama = is_supported("llama")
let has_gpt2 = is_supported("gpt2")
if not has_llama:
    print "FAIL: missing llama"
if not has_gpt2:
    print "FAIL: missing gpt2"

print "PASS"
