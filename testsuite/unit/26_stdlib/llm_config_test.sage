gc_disable()
# EXPECT: sage-tiny
# EXPECT: 2
# EXPECT: 64
# EXPECT: gpt2
# EXPECT: 12
# EXPECT: true
# EXPECT: true

import llm.config

let tiny = config.tiny()
print tiny["name"]
print tiny["n_layers"]
print tiny["d_model"]

let gpt = config.gpt2()
print gpt["name"]
print gpt["n_heads"]

# Param count
let count = config.param_count(tiny)
print count > 0

# Summary
let s = config.summary(tiny)
print len(s) > 0
