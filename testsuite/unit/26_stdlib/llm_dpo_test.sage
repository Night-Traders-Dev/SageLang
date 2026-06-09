gc_disable()
# EXPECT: true
# EXPECT: true
# EXPECT: 0.1

import llm.dpo

# DPO loss should be positive
let loss = dpo.simple_dpo_loss(-1.0, -2.0, 0.1)
print loss > 0

# Preference dataset
let ds = dpo.create_dataset()
dpo.add_pair(ds, "hello", "good response", "bad response")
print len(ds["pairs"]) == 1

# Config
let cfg = dpo.create_dpo_config()
print cfg["beta"]
