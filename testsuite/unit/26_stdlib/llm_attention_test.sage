gc_disable()
# EXPECT: 4
# EXPECT: 4
# EXPECT: true

import llm.attention

# Create a simple attention test
# 2 tokens, 2-dim head
let q = [1, 0, 0, 1]
let k = [1, 0, 0, 1]
let v = [1, 0, 0, 1]
let result = attention.scaled_dot_product(q, k, v, 2, 2, true)
print len(result)

# Causal mask
let mask = attention.causal_mask(2)
print len(mask)

# KV cache
let cache = attention.create_kv_cache(2, 2, 4)
attention.cache_append(cache, 0, [1, 2], [3, 4])
print len(attention.cache_get_keys(cache, 0)) == 2
