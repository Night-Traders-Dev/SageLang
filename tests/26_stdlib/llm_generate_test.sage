gc_disable()
# EXPECT: 1
# EXPECT: true
# EXPECT: true
# EXPECT: true

import llm.generate

# Greedy selection
let logits = [0.1, 0.9, 0.3]
print generate.greedy(logits)

# Softmax sums to ~1
let probs = generate.softmax(logits)
let s = 0
for i in range(len(probs)):
    s = s + probs[i]
let diff = s - 1.0
if diff < 0:
    diff = 0 - diff
print diff < 0.001

# Temperature
let hot = generate.apply_temperature(logits, 2.0)
print len(hot) == 3

# Gen config
let cfg = generate.create_gen_config()
print cfg["max_new_tokens"] == 100
