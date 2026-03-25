gc_disable()
# EXPECT: llama
# EXPECT: true
# EXPECT: true
# EXPECT: true

import llm.gguf
import llm.config

let cfg = config.tiny()
let gcfg = gguf.sage_to_gguf_config(cfg)
print gcfg["architecture"]

# Build metadata
let meta = gguf.build_metadata(gcfg)
print len(meta) > 0

# Build tensor list
let tensors = gguf.build_tensor_list(gcfg)
print len(tensors) > 0

# Quantization types
let qtypes = gguf.quant_types()
print len(qtypes) == 8
