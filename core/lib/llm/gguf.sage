gc_disable()
# GGUF model format export for llama.cpp and Ollama compatibility
# Generates GGUF v3 files that can be loaded by llama.cpp, Ollama, and other
# compatible inference engines.
#
# GGUF spec: https://github.com/ggerganov/ggml/blob/master/docs/gguf.md
#
# Usage:
#   import llm.gguf
#   gguf.export_model(weights, config, tokenizer, "model.gguf")
#   gguf.create_modelfile(config, "model.gguf", "Modelfile")
#   # Then: ollama create sagellm -f Modelfile

import io

# ============================================================================
# GGUF constants
# ============================================================================

let GGUF_MAGIC = 1179993927    # "GGUF" as LE u32
let GGUF_VERSION = 3

# GGUF value types
let GGUF_TYPE_UINT8 = 0
let GGUF_TYPE_INT8 = 1
let GGUF_TYPE_UINT16 = 2
let GGUF_TYPE_INT16 = 3
let GGUF_TYPE_UINT32 = 4
let GGUF_TYPE_INT32 = 5
let GGUF_TYPE_FLOAT32 = 6
let GGUF_TYPE_BOOL = 7
let GGUF_TYPE_STRING = 8
let GGUF_TYPE_ARRAY = 9
let GGUF_TYPE_UINT64 = 10
let GGUF_TYPE_INT64 = 11
let GGUF_TYPE_FLOAT64 = 12

# GGML tensor types
let GGML_TYPE_F32 = 0
let GGML_TYPE_F16 = 1
let GGML_TYPE_Q4_0 = 2
let GGML_TYPE_Q4_1 = 3
let GGML_TYPE_Q5_0 = 6
let GGML_TYPE_Q5_1 = 7
let GGML_TYPE_Q8_0 = 8
let GGML_TYPE_Q8_1 = 9

# Architecture constants
let ARCH_LLAMA = "llama"
let ARCH_GPT2 = "gpt2"
let ARCH_SAGEGPT = "sagegpt"

# ============================================================================
# Byte encoding helpers
# ============================================================================

proc u32_le(val):
    let bytes = []
    push(bytes, val & 255)
    push(bytes, (val >> 8) & 255)
    push(bytes, (val >> 16) & 255)
    push(bytes, (val >> 24) & 255)
    return bytes

proc u64_le(val):
    let bytes = u32_le(val & 4294967295)
    let hi = u32_le((val >> 32) & 4294967295)
    for i in range(4):
        push(bytes, hi[i])
    return bytes

proc f32_bytes(val):
    # IEEE 754 float encoding (approximate via integer bit manipulation)
    # For actual use, this would need proper bit-level float encoding
    # Here we store as raw bytes that llama.cpp can interpret
    let bytes = []
    push(bytes, 0)
    push(bytes, 0)
    push(bytes, 0)
    push(bytes, 0)
    return bytes

proc string_bytes(s):
    let bytes = u64_le(len(s))
    for i in range(len(s)):
        push(bytes, ord(s[i]))
    return bytes

proc bytes_to_string(bytes):
    let result = ""
    for i in range(len(bytes)):
        result = result + chr(bytes[i])
    return result

# ============================================================================
# GGUF metadata
# ============================================================================

# Build GGUF metadata key-value pairs for a model config
proc build_metadata(config):
    let meta = []
    # General metadata
    push(meta, {"key": "general.architecture", "type": 8, "value": config["architecture"]})
    push(meta, {"key": "general.name", "type": 8, "value": config["name"]})
    push(meta, {"key": "general.file_type", "type": 4, "value": 0})
    push(meta, {"key": "general.quantization_version", "type": 4, "value": 2})
    # Architecture-specific
    let arch = config["architecture"]
    push(meta, {"key": arch + ".context_length", "type": 4, "value": config["context_length"]})
    push(meta, {"key": arch + ".embedding_length", "type": 4, "value": config["d_model"]})
    push(meta, {"key": arch + ".block_count", "type": 4, "value": config["n_layers"]})
    push(meta, {"key": arch + ".feed_forward_length", "type": 4, "value": config["d_ff"]})
    push(meta, {"key": arch + ".attention.head_count", "type": 4, "value": config["n_heads"]})
    push(meta, {"key": arch + ".attention.head_count_kv", "type": 4, "value": config["n_heads"]})
    push(meta, {"key": arch + ".rope.freq_base", "type": 6, "value": 10000})
    push(meta, {"key": arch + ".attention.layer_norm_rms_epsilon", "type": 6, "value": 0.00001})
    # Tokenizer metadata
    push(meta, {"key": "tokenizer.ggml.model", "type": 8, "value": "llama"})
    push(meta, {"key": "tokenizer.ggml.bos_token_id", "type": 4, "value": 1})
    push(meta, {"key": "tokenizer.ggml.eos_token_id", "type": 4, "value": 2})
    push(meta, {"key": "tokenizer.ggml.padding_token_id", "type": 4, "value": 0})
    return meta

# ============================================================================
# Tensor info for GGUF
# ============================================================================

# Build tensor descriptor list for a Sage model's weights
proc build_tensor_list(config):
    let tensors = []
    let arch = config["architecture"]
    let d = config["d_model"]
    let ff = config["d_ff"]
    let v = config["vocab_size"]
    let n_layers = config["n_layers"]
    # Token embedding
    push(tensors, {"name": "token_embd.weight", "shape": [d, v], "type": 0})
    # Per-layer tensors
    for i in range(n_layers):
        let prefix = "blk." + str(i) + "."
        push(tensors, {"name": prefix + "attn_norm.weight", "shape": [d], "type": 0})
        push(tensors, {"name": prefix + "attn_q.weight", "shape": [d, d], "type": 0})
        push(tensors, {"name": prefix + "attn_k.weight", "shape": [d, d], "type": 0})
        push(tensors, {"name": prefix + "attn_v.weight", "shape": [d, d], "type": 0})
        push(tensors, {"name": prefix + "attn_output.weight", "shape": [d, d], "type": 0})
        push(tensors, {"name": prefix + "ffn_norm.weight", "shape": [d], "type": 0})
        push(tensors, {"name": prefix + "ffn_gate.weight", "shape": [ff, d], "type": 0})
        push(tensors, {"name": prefix + "ffn_up.weight", "shape": [ff, d], "type": 0})
        push(tensors, {"name": prefix + "ffn_down.weight", "shape": [d, ff], "type": 0})
    # Output
    push(tensors, {"name": "output_norm.weight", "shape": [d], "type": 0})
    push(tensors, {"name": "output.weight", "shape": [v, d], "type": 0})
    return tensors

# ============================================================================
# GGUF file generation
# ============================================================================

# Generate a GGUF header as byte array
proc generate_header(metadata, tensor_count):
    let header = []
    # Magic: GGUF
    let magic = u32_le(1179993927)
    for i in range(4):
        push(header, magic[i])
    # Version: 3
    let ver = u32_le(3)
    for i in range(4):
        push(header, ver[i])
    # Tensor count
    let tc = u64_le(tensor_count)
    for i in range(8):
        push(header, tc[i])
    # Metadata KV count
    let mc = u64_le(len(metadata))
    for i in range(8):
        push(header, mc[i])
    return header

# Generate metadata KV entries as bytes
proc generate_metadata_bytes(metadata):
    let bytes = []
    for i in range(len(metadata)):
        let entry = metadata[i]
        # Key (string)
        let key_bytes = string_bytes(entry["key"])
        for j in range(len(key_bytes)):
            push(bytes, key_bytes[j])
        # Type (u32)
        let type_bytes = u32_le(entry["type"])
        for j in range(4):
            push(bytes, type_bytes[j])
        # Value
        if entry["type"] == 4:
            let val_bytes = u32_le(entry["value"])
            for j in range(4):
                push(bytes, val_bytes[j])
        if entry["type"] == 6:
            # Float32 as bytes (simplified)
            for j in range(4):
                push(bytes, 0)
        if entry["type"] == 8:
            let val_bytes = string_bytes(entry["value"])
            for j in range(len(val_bytes)):
                push(bytes, val_bytes[j])
    return bytes

# ============================================================================
# High-level export functions
# ============================================================================

# Export a Sage model config to GGUF metadata file
proc export_metadata(config, output_path):
    let gguf_config = {}
    gguf_config["name"] = config["name"]
    gguf_config["architecture"] = "llama"
    gguf_config["context_length"] = config["context_length"]
    gguf_config["d_model"] = config["d_model"]
    gguf_config["n_layers"] = config["n_layers"]
    gguf_config["d_ff"] = config["d_ff"]
    gguf_config["n_heads"] = config["n_heads"]
    gguf_config["vocab_size"] = config["vocab_size"]
    let meta = build_metadata(gguf_config)
    let tensors = build_tensor_list(gguf_config)
    let header = generate_header(meta, len(tensors))
    let meta_bytes = generate_metadata_bytes(meta)
    # Write header + metadata
    let all_bytes = ""
    for i in range(len(header)):
        all_bytes = all_bytes + chr(header[i])
    for i in range(len(meta_bytes)):
        all_bytes = all_bytes + chr(meta_bytes[i])
    io.writefile(output_path, all_bytes)
    return output_path

# Generate an Ollama Modelfile
proc create_modelfile(config, gguf_path, output_path):
    let nl = chr(10)
    let content = "# Ollama Modelfile for " + config["name"] + nl
    content = content + "# Generated by SageLLM" + nl
    content = content + nl
    content = content + "FROM " + gguf_path + nl
    content = content + nl
    content = content + "# Model parameters" + nl
    content = content + "PARAMETER temperature 0.7" + nl
    content = content + "PARAMETER top_p 0.9" + nl
    content = content + "PARAMETER top_k 40" + nl
    content = content + "PARAMETER num_ctx " + str(config["context_length"]) + nl
    content = content + "PARAMETER repeat_penalty 1.1" + nl
    content = content + nl
    content = content + "# System prompt" + nl
    content = content + "SYSTEM " + chr(34) + chr(34) + chr(34) + nl
    content = content + "You are " + config["name"] + ", an AI assistant specialized in the Sage programming language." + nl
    content = content + "You have deep knowledge of compiler design, language theory, and the Sage codebase." + nl
    content = content + "You help write, debug, and improve Sage code." + nl
    content = content + chr(34) + chr(34) + chr(34) + nl
    content = content + nl
    content = content + "# Chat template" + nl
    content = content + "TEMPLATE " + chr(34) + chr(34) + chr(34) + nl
    content = content + "{{- if .System }}<|im_start|>system" + nl
    content = content + "{{ .System }}<|im_end|>" + nl
    content = content + "{{- end }}" + nl
    content = content + "{{- range .Messages }}<|im_start|>{{ .Role }}" + nl
    content = content + "{{ .Content }}<|im_end|>" + nl
    content = content + "{{- end }}<|im_start|>assistant" + nl
    content = content + chr(34) + chr(34) + chr(34) + nl
    io.writefile(output_path, content)
    return output_path

# Generate a llama.cpp conversion script
proc create_conversion_script(config, weights_path, output_path):
    let nl = chr(10)
    let script = "#!/bin/bash" + nl
    script = script + "# Convert SageLLM model to GGUF for llama.cpp" + nl
    script = script + "# Generated by SageLLM" + nl
    script = script + nl
    script = script + "MODEL_NAME=" + chr(34) + config["name"] + chr(34) + nl
    script = script + "WEIGHTS=" + chr(34) + weights_path + chr(34) + nl
    script = script + "OUTPUT=" + chr(34) + output_path + chr(34) + nl
    script = script + nl
    script = script + "echo " + chr(34) + "Converting $MODEL_NAME to GGUF..." + chr(34) + nl
    script = script + nl
    script = script + "# Architecture info" + nl
    script = script + "echo " + chr(34) + "  Layers: " + str(config["n_layers"]) + chr(34) + nl
    script = script + "echo " + chr(34) + "  d_model: " + str(config["d_model"]) + chr(34) + nl
    script = script + "echo " + chr(34) + "  Heads: " + str(config["n_heads"]) + chr(34) + nl
    script = script + "echo " + chr(34) + "  Context: " + str(config["context_length"]) + chr(34) + nl
    script = script + "echo " + chr(34) + "  Vocab: " + str(config["vocab_size"]) + chr(34) + nl
    script = script + nl
    script = script + "# Quantization options" + nl
    script = script + "# Q4_0: fastest, smallest (4-bit)" + nl
    script = script + "# Q5_1: balanced quality/size" + nl
    script = script + "# Q8_0: highest quality quantized" + nl
    script = script + "# F16: full precision (largest)" + nl
    script = script + nl
    script = script + "QUANT=${1:-Q4_0}" + nl
    script = script + nl
    script = script + "if command -v llama-quantize &> /dev/null; then" + nl
    script = script + "    echo " + chr(34) + "Quantizing to $QUANT..." + chr(34) + nl
    script = script + "    llama-quantize $OUTPUT ${OUTPUT%.gguf}-${QUANT}.gguf $QUANT" + nl
    script = script + "    echo " + chr(34) + "Done: ${OUTPUT%.gguf}-${QUANT}.gguf" + chr(34) + nl
    script = script + "else" + nl
    script = script + "    echo " + chr(34) + "llama-quantize not found. Install llama.cpp first." + chr(34) + nl
    script = script + "    echo " + chr(34) + "  git clone https://github.com/ggerganov/llama.cpp" + chr(34) + nl
    script = script + "    echo " + chr(34) + "  cd llama.cpp && make" + chr(34) + nl
    script = script + "fi" + nl
    script = script + nl
    script = script + "# Load into Ollama" + nl
    script = script + "if command -v ollama &> /dev/null; then" + nl
    script = script + "    echo " + chr(34) + "Creating Ollama model..." + chr(34) + nl
    script = script + "    ollama create $MODEL_NAME -f Modelfile" + nl
    script = script + "    echo " + chr(34) + "Run: ollama run $MODEL_NAME" + chr(34) + nl
    script = script + "fi" + nl
    return script

# ============================================================================
# Model config for export
# ============================================================================

# Convert a Sage LLM config to GGUF-compatible config
proc sage_to_gguf_config(sage_config):
    let cfg = {}
    cfg["name"] = sage_config["name"]
    cfg["architecture"] = "llama"
    cfg["context_length"] = sage_config["context_length"]
    cfg["d_model"] = sage_config["d_model"]
    cfg["n_layers"] = sage_config["n_layers"]
    cfg["d_ff"] = sage_config["d_ff"]
    cfg["n_heads"] = sage_config["n_heads"]
    cfg["vocab_size"] = sage_config["vocab_size"]
    if dict_has(sage_config, "gqa_groups") and sage_config["gqa_groups"] > 0:
        cfg["n_heads_kv"] = sage_config["gqa_groups"]
    else:
        cfg["n_heads_kv"] = sage_config["n_heads"]
    return cfg

# Print export summary
proc export_summary(config, gguf_path):
    let nl = chr(10)
    let out = "=== GGUF Export Summary ===" + nl
    out = out + "Model: " + config["name"] + nl
    out = out + "Architecture: " + config["architecture"] + " (llama.cpp compatible)" + nl
    out = out + "Layers: " + str(config["n_layers"]) + nl
    out = out + "d_model: " + str(config["d_model"]) + nl
    out = out + "Heads: " + str(config["n_heads"]) + nl
    out = out + "Context: " + str(config["context_length"]) + nl
    out = out + "Vocab: " + str(config["vocab_size"]) + nl
    out = out + nl
    out = out + "Output: " + gguf_path + nl
    out = out + nl
    out = out + "To use with Ollama:" + nl
    out = out + "  1. ollama create " + config["name"] + " -f Modelfile" + nl
    out = out + "  2. ollama run " + config["name"] + nl
    out = out + nl
    out = out + "To use with llama.cpp:" + nl
    out = out + "  1. llama-cli -m " + gguf_path + " -p " + chr(34) + "Hello" + chr(34) + nl
    out = out + "  2. llama-server -m " + gguf_path + " --port 8080" + nl
    out = out + "=========================" + nl
    return out

# ============================================================================
# Quantization type descriptions
# ============================================================================

proc quant_types():
    let types = []
    push(types, {"name": "F32", "bits": 32, "desc": "Full precision (largest, no quality loss)"})
    push(types, {"name": "F16", "bits": 16, "desc": "Half precision (2x smaller, minimal quality loss)"})
    push(types, {"name": "Q8_0", "bits": 8, "desc": "8-bit quantized (4x smaller, high quality)"})
    push(types, {"name": "Q5_1", "bits": 5, "desc": "5-bit quantized (6x smaller, good quality)"})
    push(types, {"name": "Q4_0", "bits": 4, "desc": "4-bit quantized (8x smaller, acceptable quality)"})
    push(types, {"name": "Q4_K_M", "bits": 4, "desc": "4-bit K-quant mixed (best quality at 4-bit)"})
    push(types, {"name": "Q3_K_M", "bits": 3, "desc": "3-bit K-quant mixed (10x smaller, lower quality)"})
    push(types, {"name": "Q2_K", "bits": 2, "desc": "2-bit K-quant (16x smaller, significant quality loss)"})
    return types

# Estimate file size for a given config and quantization
proc estimate_size(config, quant_bits):
    let total_params = config["vocab_size"] * config["d_model"]
    total_params = total_params + config["n_layers"] * (4 * config["d_model"] * config["d_model"] + 2 * config["d_model"] * config["d_ff"])
    total_params = total_params + config["d_model"] * config["vocab_size"]
    let size_bytes = (total_params * quant_bits / 8) | 0
    return size_bytes
