gc_disable()
# EXPECT: 8
# EXPECT: 4
# EXPECT: true
# EXPECT: true

import llm.lora

# Create adapter
let adapter = lora.create_adapter(64, 64, 8, 16)
print adapter["rank"]

# Forward pass (1 token, 64-dim)
let x = []
for i in range(64):
    push(x, 0.1)
let delta = lora.lora_forward(adapter, x, 1)
print len(delta) / 16

# Trainable params
print adapter["trainable_params"] > 0

# Default targets
let targets = lora.default_targets()
print len(targets) == 2
