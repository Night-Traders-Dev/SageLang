gc_disable()
# Export SageLLM model for Ollama and llama.cpp
# Usage: sage models/export_ollama.sage
#
# Generates:
#   - model.gguf (GGUF metadata + weight stubs)
#   - Modelfile (Ollama config)
#   - convert.sh (llama.cpp conversion + quantization script)

import io
import llm.config
import llm.gguf

print "============================================"
print "  SageLLM -> Ollama/llama.cpp Export"
print "============================================"
print ""

# Select model size
print "Select model to export:"
print "  1) SageGPT-Nano (64d, 2L, ~50K params)"
print "  2) SageGPT-Small (512d, 8L, ~50M params)"
print "  3) SageGPT-Medium (1024d, 16L, ~200M params)"
print "  4) GPT-2 (768d, 12L, ~124M params)"
print "  5) Llama-7B compatible (4096d, 32L)"
print ""
let choice = input("Choice [1-5]: ")

let cfg = nil
if choice == "1":
    cfg = config.tiny()
if choice == "2":
    cfg = config.agent_small()
if choice == "3":
    cfg = config.agent_medium()
if choice == "4":
    cfg = config.gpt2()
if choice == "5":
    cfg = config.llama_7b()

if cfg == nil:
    cfg = config.tiny()

print ""
print "Model: " + cfg["name"]
print "Parameters: ~" + config.param_count_str(cfg)
print ""

# Convert to GGUF-compatible config
let gcfg = gguf.sage_to_gguf_config(cfg)

# Create output directory
let out_dir = "models/export"
io.writefile(out_dir + "/.keep", "")

# 1. Generate GGUF metadata
print "[1/4] Generating GGUF metadata..."
let gguf_path = out_dir + "/" + cfg["name"] + ".gguf"
gguf.export_metadata(gcfg, gguf_path)
print "  -> " + gguf_path

# 2. Generate Modelfile for Ollama
print "[2/4] Generating Ollama Modelfile..."
let modelfile_path = out_dir + "/Modelfile"
gguf.create_modelfile(gcfg, cfg["name"] + ".gguf", modelfile_path)
print "  -> " + modelfile_path

# 3. Generate conversion script
print "[3/4] Generating conversion script..."
let script = gguf.create_conversion_script(gcfg, gguf_path, gguf_path)
io.writefile(out_dir + "/convert.sh", script)
print "  -> " + out_dir + "/convert.sh"

# 4. Show quantization options
print "[4/4] Quantization options:"
let qtypes = gguf.quant_types()
for i in range(len(qtypes)):
    let qt = qtypes[i]
    let size = gguf.estimate_size(gcfg, qt["bits"])
    let size_str = ""
    if size >= 1073741824:
        size_str = str((size / 1073741824 * 10) | 0) + " GB"
    if size >= 1048576 and size < 1073741824:
        size_str = str((size / 1048576) | 0) + " MB"
    if size < 1048576:
        size_str = str((size / 1024) | 0) + " KB"
    print "  " + qt["name"] + ": " + size_str + " - " + qt["desc"]

# Summary
print ""
print gguf.export_summary(gcfg, gguf_path)

print "Next steps:"
print "  1. Train your model: sage models/train_full.sage"
print "  2. Export weights to GGUF format (requires weight serialization)"
print "  3. Quantize: bash " + out_dir + "/convert.sh Q4_K_M"
print "  4. Load into Ollama: cd " + out_dir + " && ollama create " + cfg["name"] + " -f Modelfile"
print "  5. Run: ollama run " + cfg["name"]
print ""
print "For llama.cpp direct:"
print "  llama-cli -m " + gguf_path + " -p " + chr(34) + "Write a Sage function" + chr(34)
print "  llama-server -m " + gguf_path + " --port 8080"
