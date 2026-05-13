gc_disable()
# GGUF model format importer for loading Ollama/llama.cpp models into SageGPT
#
# GGUF (GGML Universal File) format specification (v3):
#   https://github.com/ggerganov/ggml/blob/master/docs/gguf.md
#
# File layout:
#   [Header]
#     - Magic number: 0x46475547 ("GGUF" in ASCII, little-endian u32 = 1179993927)
#     - Version: u32 (we support v2 and v3)
#     - Tensor count: u64 (v3) or u32 (v2)
#     - Metadata KV count: u64 (v3) or u32 (v2)
#   [Metadata KV pairs]
#     Each pair: key_string, value_type (u32), value_data
#     String format: length (u64), then UTF-8 bytes (no null terminator)
#     Value types: UINT8(0), INT8(1), UINT16(2), INT16(3), UINT32(4), INT32(5),
#                  FLOAT32(6), BOOL(7), STRING(8), ARRAY(9), UINT64(10),
#                  INT64(11), FLOAT64(12)
#   [Tensor Info entries]
#     Each: name_string, n_dims (u32), dims[n_dims] (u64 each),
#           type (u32), offset from tensor data start (u64)
#   [Alignment padding]
#     Pad to ALIGNMENT boundary (default 32 bytes)
#   [Tensor Data]
#     Raw tensor data, each tensor aligned to ALIGNMENT boundary
#
# Supported quantization formats:
#   Q4_0: 32 weights per block, 2+16 = 18 bytes per block
#         (16 bytes for 32 nibbles + 2 bytes f16 scale)
#   Q8_0: 32 weights per block, 2+32 = 34 bytes per block
#         (32 bytes for 32 int8 values + 2 bytes f16 scale)
#   F32:  Standard IEEE 754 float32
#   F16:  IEEE 754 float16
#
# Architecture metadata key mappings (GGUF v3):
#   All architectures use the pattern: {arch}.{property}
#
#   Common keys across architectures:
#     {arch}.context_length          -> context window size
#     {arch}.embedding_length        -> hidden dimension (d_model)
#     {arch}.block_count             -> number of transformer layers
#     {arch}.feed_forward_length     -> FFN intermediate dimension
#     {arch}.attention.head_count    -> number of attention heads
#     {arch}.attention.head_count_kv -> number of KV heads (GQA)
#     {arch}.attention.layer_norm_rms_epsilon -> RMSNorm epsilon
#     {arch}.rope.freq_base          -> RoPE theta base frequency
#     {arch}.vocab_size              -> vocabulary size
#
#   Architecture-specific notes:
#     llama:   SwiGLU FFN (gate_proj, up_proj, down_proj), RMSNorm, RoPE
#     mistral: Same as llama but with sliding_window attention
#     gpt2:    GELU FFN (fc, proj), LayerNorm, learned positional encoding
#     phi:     Partial rotation RoPE, parallel attention+FFN in some variants
#     gemma:   Similar to llama, different norm placement, vocab_size=256000
#     qwen2:   Similar to llama, often different vocab sizes and head counts
#
# Usage:
#   import llm.gguf_import
#   let data = gguf_import.import_gguf("path/to/model.gguf")
#   let config = data["config"]
#   let weights = data["weights"]
#   let model = gguf_import.convert_to_sagegpt(data)
#   print(gguf_import.summary(data))

import io

# ============================================================================
# GGUF constants
# ============================================================================

let GGUF_MAGIC = 1179993927      # 0x46475547 = "GGUF" little-endian
let GGUF_DEFAULT_ALIGNMENT = 32  # Default tensor data alignment in bytes

# GGUF metadata value types
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

# GGML tensor data types
let GGML_TYPE_F32 = 0
let GGML_TYPE_F16 = 1
let GGML_TYPE_Q4_0 = 2
let GGML_TYPE_Q4_1 = 3
let GGML_TYPE_Q5_0 = 6
let GGML_TYPE_Q5_1 = 7
let GGML_TYPE_Q8_0 = 8
let GGML_TYPE_Q8_1 = 9
let GGML_TYPE_I8 = 24
let GGML_TYPE_I16 = 25
let GGML_TYPE_I32 = 26

# Block sizes for quantized types (number of weights per block)
let Q4_0_BLOCK_SIZE = 32
let Q8_0_BLOCK_SIZE = 32

# Bytes per block for quantized types
# Q4_0: 2 (f16 scale) + 16 (32 nibbles packed into 16 bytes) = 18
let Q4_0_BYTES_PER_BLOCK = 18
# Q8_0: 2 (f16 scale) + 32 (32 int8 values) = 34
let Q8_0_BYTES_PER_BLOCK = 34

# ============================================================================
# Low-level byte reading utilities
# ============================================================================

# Read a little-endian uint32 from a byte array at the given offset.
# Returns {"value": uint32_value, "offset": new_offset}
proc read_uint32(bytes, offset):
    if offset + 4 > len(bytes):
        print("ERROR: read_uint32: offset " + str(offset) + " out of bounds (size=" + str(len(bytes)) + ")")
        let r = {}
        r["value"] = 0
        r["offset"] = offset
        return r
    let b0 = bytes[offset]
    let b1 = bytes[offset + 1]
    let b2 = bytes[offset + 2]
    let b3 = bytes[offset + 3]
    let val = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
    let r = {}
    r["value"] = val
    r["offset"] = offset + 4
    return r

# Read a little-endian uint64 from a byte array at the given offset.
# Note: Sage numbers are 64-bit floats, so values above 2^53 lose precision.
# For tensor counts and metadata counts this is fine.
# Returns {"value": uint64_value, "offset": new_offset}
proc read_uint64(bytes, offset):
    if offset + 8 > len(bytes):
        print("ERROR: read_uint64: offset " + str(offset) + " out of bounds (size=" + str(len(bytes)) + ")")
        let r = {}
        r["value"] = 0
        r["offset"] = offset
        return r
    let lo = bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536 + bytes[offset + 3] * 16777216
    let hi = bytes[offset + 4] + bytes[offset + 5] * 256 + bytes[offset + 6] * 65536 + bytes[offset + 7] * 16777216
    let val = lo + hi * 4294967296
    let r = {}
    r["value"] = val
    r["offset"] = offset + 8
    return r

# Read a little-endian uint16 from a byte array.
# Returns {"value": uint16_value, "offset": new_offset}
proc read_uint16(bytes, offset):
    if offset + 2 > len(bytes):
        let r = {}
        r["value"] = 0
        r["offset"] = offset
        return r
    let val = bytes[offset] + bytes[offset + 1] * 256
    let r = {}
    r["value"] = val
    r["offset"] = offset + 2
    return r

# Read a little-endian int8 (signed) from a byte array.
# Returns {"value": int8_value, "offset": new_offset}
proc read_int8(bytes, offset):
    if offset >= len(bytes):
        let r = {}
        r["value"] = 0
        r["offset"] = offset
        return r
    let val = bytes[offset]
    if val >= 128:
        val = val - 256
    let r = {}
    r["value"] = val
    r["offset"] = offset + 1
    return r

# Read a little-endian float32 from a byte array.
# Uses IEEE 754 bit manipulation to approximate the float value.
# IEEE 754 single: sign(1) | exponent(8) | mantissa(23)
# Returns {"value": float32_value, "offset": new_offset}
proc read_float32(bytes, offset):
    if offset + 4 > len(bytes):
        let r = {}
        r["value"] = 0.0
        r["offset"] = offset
        return r
    let b0 = bytes[offset]
    let b1 = bytes[offset + 1]
    let b2 = bytes[offset + 2]
    let b3 = bytes[offset + 3]
    let bits = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
    # Extract sign, exponent, mantissa
    let sign = 1
    if bits >= 2147483648:
        sign = -1
        bits = bits - 2147483648
    let exponent = (bits / 8388608) | 0
    let mantissa = bits - exponent * 8388608
    # Special cases
    if exponent == 0:
        if mantissa == 0:
            let r = {}
            r["value"] = 0.0 * sign
            r["offset"] = offset + 4
            return r
        # Denormalized: value = sign * 2^(-126) * (mantissa / 2^23)
        let r = {}
        r["value"] = sign * mantissa / 8388608 * 0.0000000000000000000000000000000000000117549435
        r["offset"] = offset + 4
        return r
    if exponent == 255:
        let r = {}
        # Infinity or NaN - return 0 as a safe fallback
        r["value"] = 0.0
        r["offset"] = offset + 4
        return r
    # Normalized: value = sign * 2^(exponent-127) * (1 + mantissa/2^23)
    let frac = 1.0 + mantissa / 8388608.0
    # Compute 2^(exponent-127) using repeated multiplication/division
    let exp_val = exponent - 127
    let power = 1.0
    if exp_val >= 0:
        let i = 0
        for _ in range(exp_val):
            power = power * 2
            i = i + 1
    else:
        let neg_exp = 0 - exp_val
        let i = 0
        for _ in range(neg_exp):
            power = power / 2
            i = i + 1
    let r = {}
    r["value"] = sign * frac * power
    r["offset"] = offset + 4
    return r

# Read a float16 value and convert to float64.
# IEEE 754 half: sign(1) | exponent(5) | mantissa(10)
# Used for Q4_0 and Q8_0 scale factors.
# Returns float64 value (not a dict, just the number)
proc read_float16_value(bytes, offset):
    if offset + 2 > len(bytes):
        return 0.0
    let bits = bytes[offset] + bytes[offset + 1] * 256
    let sign = 1
    if bits >= 32768:
        sign = -1
        bits = bits - 32768
    let exponent = (bits / 1024) | 0
    let mantissa = bits - exponent * 1024
    if exponent == 0:
        if mantissa == 0:
            return 0.0
        # Denormalized f16
        return sign * mantissa / 1024.0 * 0.000000059604645
    if exponent == 31:
        return 0.0
    let frac = 1.0 + mantissa / 1024.0
    let exp_val = exponent - 15
    let power = 1.0
    if exp_val >= 0:
        for _ in range(exp_val):
            power = power * 2
    else:
        let neg = 0 - exp_val
        for _ in range(neg):
            power = power / 2
    return sign * frac * power

# Read a length-prefixed UTF-8 string from a byte array.
# GGUF string format: length (u64), then that many UTF-8 bytes (no null terminator)
# Returns {"value": string, "offset": new_offset}
proc read_string(bytes, offset):
    let len_result = read_uint64(bytes, offset)
    let str_len = len_result["value"]
    let pos = len_result["offset"]
    if pos + str_len > len(bytes):
        print("ERROR: read_string: string length " + str(str_len) + " exceeds available data at offset " + str(offset))
        let r = {}
        r["value"] = ""
        r["offset"] = pos
        return r
    # Safety: reject absurdly long strings (> 1MB)
    if str_len > 1048576:
        print("ERROR: read_string: string length " + str(str_len) + " exceeds 1MB safety limit")
        let r = {}
        r["value"] = ""
        r["offset"] = pos + str_len
        return r
    let result = ""
    for i in range(str_len):
        result = result + chr(bytes[pos + i])
    let r = {}
    r["value"] = result
    r["offset"] = pos + str_len
    return r

# ============================================================================
# GGUF header parsing
# ============================================================================

# Parse the GGUF file header from a byte array.
# Validates the magic number and version, extracts tensor and metadata counts.
# Returns {"version": v, "tensor_count": tc, "metadata_count": mc, "offset": new_offset}
# or nil on error.
proc parse_header(bytes):
    if len(bytes) < 24:
        print("ERROR: parse_header: file too small (" + str(len(bytes)) + " bytes, need at least 24)")
        return nil
    # Read and validate magic number
    let magic_r = read_uint32(bytes, 0)
    let magic = magic_r["value"]
    if magic != GGUF_MAGIC:
        print("ERROR: parse_header: invalid magic number " + str(magic) + " (expected " + str(GGUF_MAGIC) + " = GGUF)")
        return nil
    # Read version
    let ver_r = read_uint32(bytes, 4)
    let version = ver_r["value"]
    if version < 2:
        print("ERROR: parse_header: unsupported GGUF version " + str(version) + " (need v2 or v3)")
        return nil
    if version > 3:
        print("WARNING: parse_header: GGUF version " + str(version) + " is newer than supported (v3), attempting anyway")
    # Read tensor count and metadata count
    # v3 uses u64, v2 uses u32 (but we read u64 for both since u32 fits in u64 layout)
    let tc_r = read_uint64(bytes, 8)
    let tensor_count = tc_r["value"]
    let mc_r = read_uint64(bytes, 16)
    let metadata_count = mc_r["value"]
    # Sanity checks
    if tensor_count > 100000:
        print("ERROR: parse_header: unreasonable tensor count " + str(tensor_count))
        return nil
    if metadata_count > 100000:
        print("ERROR: parse_header: unreasonable metadata count " + str(metadata_count))
        return nil
    let result = {}
    result["version"] = version
    result["tensor_count"] = tensor_count
    result["metadata_count"] = metadata_count
    result["offset"] = 24
    return result

# ============================================================================
# Metadata reading
# ============================================================================

# Read a single metadata value of the given type from bytes at offset.
# Returns {"value": parsed_value, "offset": new_offset}
proc read_metadata_value(bytes, offset, value_type):
    if value_type == GGUF_TYPE_UINT8:
        if offset >= len(bytes):
            let r = {}
            r["value"] = 0
            r["offset"] = offset
            return r
        let r = {}
        r["value"] = bytes[offset]
        r["offset"] = offset + 1
        return r
    if value_type == GGUF_TYPE_INT8:
        return read_int8(bytes, offset)
    if value_type == GGUF_TYPE_UINT16:
        return read_uint16(bytes, offset)
    if value_type == GGUF_TYPE_INT16:
        let raw = read_uint16(bytes, offset)
        let val = raw["value"]
        if val >= 32768:
            val = val - 65536
        let r = {}
        r["value"] = val
        r["offset"] = raw["offset"]
        return r
    if value_type == GGUF_TYPE_UINT32:
        return read_uint32(bytes, offset)
    if value_type == GGUF_TYPE_INT32:
        let raw = read_uint32(bytes, offset)
        let val = raw["value"]
        if val >= 2147483648:
            val = val - 4294967296
        let r = {}
        r["value"] = val
        r["offset"] = raw["offset"]
        return r
    if value_type == GGUF_TYPE_FLOAT32:
        return read_float32(bytes, offset)
    if value_type == GGUF_TYPE_BOOL:
        if offset >= len(bytes):
            let r = {}
            r["value"] = false
            r["offset"] = offset
            return r
        let r = {}
        r["value"] = bytes[offset] != 0
        r["offset"] = offset + 1
        return r
    if value_type == GGUF_TYPE_STRING:
        return read_string(bytes, offset)
    if value_type == GGUF_TYPE_ARRAY:
        # Array: element_type (u32), count (u64), then count elements
        let type_r = read_uint32(bytes, offset)
        let elem_type = type_r["value"]
        let count_r = read_uint64(bytes, type_r["offset"])
        let count = count_r["value"]
        let pos = count_r["offset"]
        # Safety: cap array reads at 10 million elements
        if count > 10000000:
            print("WARNING: read_metadata_value: array count " + str(count) + " capped at 10000000")
            count = 10000000
        let arr = []
        let idx = 0
        for _ in range(count):
            let elem = read_metadata_value(bytes, pos, elem_type)
            push(arr, elem["value"])
            pos = elem["offset"]
            idx = idx + 1
        let r = {}
        r["value"] = arr
        r["offset"] = pos
        return r
    if value_type == GGUF_TYPE_UINT64:
        return read_uint64(bytes, offset)
    if value_type == GGUF_TYPE_INT64:
        let raw = read_uint64(bytes, offset)
        # For simplicity, treat as unsigned (Sage floats can hold up to 2^53)
        let r = {}
        r["value"] = raw["value"]
        r["offset"] = raw["offset"]
        return r
    if value_type == GGUF_TYPE_FLOAT64:
        # Read 8 bytes - approximate via two float32 reads
        # This is a rough approximation since Sage has no native f64 bit access
        let lo_r = read_float32(bytes, offset)
        let r = {}
        r["value"] = lo_r["value"]
        r["offset"] = offset + 8
        return r
    # Unknown type - skip 0 bytes and return nil
    print("WARNING: read_metadata_value: unknown value type " + str(value_type))
    let r = {}
    r["value"] = nil
    r["offset"] = offset
    return r

# Read all metadata key-value pairs from the GGUF file.
# count: number of KV pairs to read (from header)
# Returns {"metadata": dict_of_key_to_value, "offset": new_offset}
proc read_metadata(bytes, offset, count):
    let metadata = {}
    let pos = offset
    for idx in range(count):
        # Read key (string)
        let key_r = read_string(bytes, pos)
        let key = key_r["value"]
        pos = key_r["offset"]
        # Read value type (u32)
        let type_r = read_uint32(bytes, pos)
        let value_type = type_r["value"]
        pos = type_r["offset"]
        # Read value
        let val_r = read_metadata_value(bytes, pos, value_type)
        metadata[key] = val_r["value"]
        pos = val_r["offset"]
    let r = {}
    r["metadata"] = metadata
    r["offset"] = pos
    return r

# ============================================================================
# Tensor info reading
# ============================================================================

# Read tensor info entries from the GGUF file.
# Each entry contains: name, dimensions, data type, and offset into tensor data.
# count: number of tensor info entries (from header)
# Returns {"tensors": list_of_tensor_info_dicts, "offset": new_offset}
proc read_tensor_info(bytes, offset, count):
    let tensors = []
    let pos = offset
    for idx in range(count):
        let info = {}
        # Tensor name (string)
        let name_r = read_string(bytes, pos)
        info["name"] = name_r["value"]
        pos = name_r["offset"]
        # Number of dimensions (u32)
        let ndims_r = read_uint32(bytes, pos)
        let ndims = ndims_r["value"]
        pos = ndims_r["offset"]
        # Dimension sizes (u64 each)
        let dims = []
        for d in range(ndims):
            let dim_r = read_uint64(bytes, pos)
            push(dims, dim_r["value"])
            pos = dim_r["offset"]
        info["dims"] = dims
        # Compute total element count
        let n_elements = 1
        for d in range(len(dims)):
            n_elements = n_elements * dims[d]
        info["n_elements"] = n_elements
        # Tensor data type (u32) - GGML type enum
        let type_r = read_uint32(bytes, pos)
        info["type"] = type_r["value"]
        pos = type_r["offset"]
        # Offset from start of tensor data section (u64)
        let off_r = read_uint64(bytes, pos)
        info["data_offset"] = off_r["value"]
        pos = off_r["offset"]
        push(tensors, info)
    let r = {}
    r["tensors"] = tensors
    r["offset"] = pos
    return r

# ============================================================================
# Quantization format name lookup
# ============================================================================

# Return human-readable name for a GGML tensor type
proc ggml_type_name(t):
    if t == 0:
        return "F32"
    if t == 1:
        return "F16"
    if t == 2:
        return "Q4_0"
    if t == 3:
        return "Q4_1"
    if t == 6:
        return "Q5_0"
    if t == 7:
        return "Q5_1"
    if t == 8:
        return "Q8_0"
    if t == 9:
        return "Q8_1"
    return "unknown(" + str(t) + ")"

# Return bytes per element for a GGML type (approximate, for size estimation)
proc ggml_type_size(t):
    if t == 0:
        return 4.0
    if t == 1:
        return 2.0
    if t == 2:
        return 0.5625
    if t == 3:
        return 0.625
    if t == 6:
        return 0.6875
    if t == 7:
        return 0.75
    if t == 8:
        return 1.0625
    if t == 9:
        return 1.125
    return 4.0

# ============================================================================
# Dequantization routines
# ============================================================================

# Dequantize Q4_0 format data to a float array.
#
# Q4_0 block layout (18 bytes per block of 32 weights):
#   - 2 bytes: float16 scale factor (delta)
#   - 16 bytes: 32 x 4-bit quantized weights packed as nibbles
#     Each byte holds two 4-bit values: low nibble = first weight, high nibble = second
#     Values are unsigned [0,15], centered at 8: actual = (nibble - 8) * delta
#
# data: byte array (raw block data)
# n: total number of weights to dequantize
# Returns: flat array of float values
proc dequantize_q4_0(data, n):
    let result = []
    let n_blocks = (n / Q4_0_BLOCK_SIZE) | 0
    if n_blocks * Q4_0_BLOCK_SIZE < n:
        n_blocks = n_blocks + 1
    let data_offset = 0
    for block_idx in range(n_blocks):
        # Read f16 scale (delta)
        let delta = read_float16_value(data, data_offset)
        data_offset = data_offset + 2
        # Read 16 bytes of packed nibbles (32 weights)
        let weights_in_block = Q4_0_BLOCK_SIZE
        let remaining = n - block_idx * Q4_0_BLOCK_SIZE
        if remaining < Q4_0_BLOCK_SIZE:
            weights_in_block = remaining
        for byte_idx in range(16):
            if data_offset >= len(data):
                # Pad remaining with zeros
                if len(result) < n:
                    push(result, 0.0)
                if len(result) < n:
                    push(result, 0.0)
                continue
            let packed = data[data_offset]
            data_offset = data_offset + 1
            # Low nibble: first weight
            let lo = packed & 15
            let w0 = (lo - 8) * delta
            # High nibble: second weight
            let hi = (packed >> 4) & 15
            let w1 = (hi - 8) * delta
            let w_idx = block_idx * Q4_0_BLOCK_SIZE + byte_idx * 2
            if w_idx < n:
                push(result, w0)
            if w_idx + 1 < n:
                push(result, w1)
    return result

# Dequantize Q8_0 format data to a float array.
#
# Q8_0 block layout (34 bytes per block of 32 weights):
#   - 2 bytes: float16 scale factor (delta)
#   - 32 bytes: 32 x int8 quantized weights
#     Values are signed [-128, 127]: actual = value * delta
#
# data: byte array (raw block data)
# n: total number of weights to dequantize
# Returns: flat array of float values
proc dequantize_q8_0(data, n):
    let result = []
    let n_blocks = (n / Q8_0_BLOCK_SIZE) | 0
    if n_blocks * Q8_0_BLOCK_SIZE < n:
        n_blocks = n_blocks + 1
    let data_offset = 0
    for block_idx in range(n_blocks):
        # Read f16 scale (delta)
        let delta = read_float16_value(data, data_offset)
        data_offset = data_offset + 2
        # Read 32 signed int8 weights
        let weights_in_block = Q8_0_BLOCK_SIZE
        let remaining = n - block_idx * Q8_0_BLOCK_SIZE
        if remaining < Q8_0_BLOCK_SIZE:
            weights_in_block = remaining
        for w in range(Q8_0_BLOCK_SIZE):
            if data_offset >= len(data):
                if block_idx * Q8_0_BLOCK_SIZE + w < n:
                    push(result, 0.0)
                continue
            let val = data[data_offset]
            data_offset = data_offset + 1
            if val >= 128:
                val = val - 256
            if block_idx * Q8_0_BLOCK_SIZE + w < n:
                push(result, val * delta)
    return result

# Dequantize F16 (float16) data to float array.
# data: byte array, n: number of float16 values
# Returns: flat array of float values
proc dequantize_f16(data, n):
    let result = []
    let pos = 0
    for i in range(n):
        let val = read_float16_value(data, pos)
        push(result, val)
        pos = pos + 2
    return result

# Read F32 data directly as float array.
# data: byte array, n: number of float32 values
# Returns: flat array of float values
proc read_f32_data(data, n):
    let result = []
    let pos = 0
    for i in range(n):
        let r = read_float32(data, pos)
        push(result, r["value"])
        pos = pos + 4
    return result

# ============================================================================
# Weight loading
# ============================================================================

# Calculate the byte size of tensor data for a given GGML type and element count.
proc tensor_data_size(ggml_type, n_elements):
    if ggml_type == GGML_TYPE_F32:
        return n_elements * 4
    if ggml_type == GGML_TYPE_F16:
        return n_elements * 2
    if ggml_type == GGML_TYPE_Q4_0:
        let n_blocks = (n_elements / Q4_0_BLOCK_SIZE) | 0
        if n_blocks * Q4_0_BLOCK_SIZE < n_elements:
            n_blocks = n_blocks + 1
        return n_blocks * Q4_0_BYTES_PER_BLOCK
    if ggml_type == GGML_TYPE_Q8_0:
        let n_blocks = (n_elements / Q8_0_BLOCK_SIZE) | 0
        if n_blocks * Q8_0_BLOCK_SIZE < n_elements:
            n_blocks = n_blocks + 1
        return n_blocks * Q8_0_BYTES_PER_BLOCK
    # Fallback: estimate using ggml_type_size
    return (n_elements * ggml_type_size(ggml_type) + 0.5) | 0

# Dequantize a tensor given its raw byte data, type, and element count.
# Returns a flat float array.
proc dequantize_tensor(data, ggml_type, n_elements):
    if ggml_type == GGML_TYPE_F32:
        return read_f32_data(data, n_elements)
    if ggml_type == GGML_TYPE_F16:
        return dequantize_f16(data, n_elements)
    if ggml_type == GGML_TYPE_Q4_0:
        return dequantize_q4_0(data, n_elements)
    if ggml_type == GGML_TYPE_Q8_0:
        return dequantize_q8_0(data, n_elements)
    print("WARNING: dequantize_tensor: unsupported type " + ggml_type_name(ggml_type) + ", returning zeros")
    let result = []
    for i in range(n_elements):
        push(result, 0.0)
    return result

# Load and dequantize all weight tensors from the GGUF file.
#
# bytes: full file byte array
# tensor_infos: list of tensor info dicts from read_tensor_info()
# tensor_data_start: byte offset where tensor data begins in the file
#
# Returns a dict mapping tensor name -> {"data": float_array, "dims": dims, "type": original_type}
proc load_weights(bytes, tensor_infos, tensor_data_start):
    let weights = {}
    for i in range(len(tensor_infos)):
        let info = tensor_infos[i]
        let name = info["name"]
        let n_elements = info["n_elements"]
        let ggml_type = info["type"]
        let data_offset = tensor_data_start + info["data_offset"]
        # Calculate how many bytes to read
        let data_size = tensor_data_size(ggml_type, n_elements)
        # Bounds check
        if data_offset + data_size > len(bytes):
            print("WARNING: load_weights: tensor " + name + " data extends beyond file (offset=" + str(data_offset) + ", size=" + str(data_size) + ", file=" + str(len(bytes)) + ")")
            let w = {}
            w["data"] = []
            w["dims"] = info["dims"]
            w["type"] = ggml_type
            weights[name] = w
            continue
        # Extract raw bytes for this tensor
        let raw = []
        for j in range(data_size):
            push(raw, bytes[data_offset + j])
        # Dequantize
        let float_data = dequantize_tensor(raw, ggml_type, n_elements)
        let w = {}
        w["data"] = float_data
        w["dims"] = info["dims"]
        w["type"] = ggml_type
        weights[name] = w
    return weights

# ============================================================================
# Config extraction from metadata
# ============================================================================

# Map GGUF metadata keys to a SageGPT-compatible config dict.
# Handles multiple architectures by detecting the "general.architecture" key
# and then reading architecture-prefixed keys.
#
# Standard GGUF metadata key patterns:
#   general.architecture -> "llama", "gpt2", "mistral", "phi", "gemma", "qwen2"
#   general.name -> model name string
#   {arch}.context_length -> max sequence length
#   {arch}.embedding_length -> hidden dimension (d_model)
#   {arch}.block_count -> number of transformer blocks (layers)
#   {arch}.feed_forward_length -> FFN intermediate size (d_ff)
#   {arch}.attention.head_count -> number of attention heads
#   {arch}.attention.head_count_kv -> number of KV heads (for GQA; equals head_count if MHA)
#   {arch}.attention.layer_norm_rms_epsilon -> RMSNorm epsilon
#   {arch}.rope.freq_base -> RoPE frequency base (theta)
#   {arch}.vocab_size -> vocabulary size (some models store this, others infer from token_embd)
#
# Architecture-specific notes:
#   llama/mistral/qwen2: SwiGLU FFN, RMSNorm, RoPE
#   gpt2: GELU FFN, LayerNorm, learned position embedding
#   phi: partial RoPE, GELU or SiLU depending on version
#   gemma: similar to llama, large vocab (256k), different tensor names
proc extract_config(metadata):
    let config = {}
    # Detect architecture
    let arch = "llama"
    if dict_has(metadata, "general.architecture"):
        arch = metadata["general.architecture"]
    config["architecture"] = arch
    # Model name
    config["name"] = "unknown"
    if dict_has(metadata, "general.name"):
        config["name"] = metadata["general.name"]
    # Context length
    let ctx_key = arch + ".context_length"
    config["context_length"] = 2048
    if dict_has(metadata, ctx_key):
        config["context_length"] = metadata[ctx_key]
    # Embedding length (d_model)
    let emb_key = arch + ".embedding_length"
    config["d_model"] = 4096
    if dict_has(metadata, emb_key):
        config["d_model"] = metadata[emb_key]
    # Block count (n_layers)
    let blk_key = arch + ".block_count"
    config["n_layers"] = 32
    if dict_has(metadata, blk_key):
        config["n_layers"] = metadata[blk_key]
    # Feed forward length (d_ff)
    let ff_key = arch + ".feed_forward_length"
    config["d_ff"] = config["d_model"] * 4
    if dict_has(metadata, ff_key):
        config["d_ff"] = metadata[ff_key]
    # Attention head count
    let head_key = arch + ".attention.head_count"
    config["n_heads"] = 32
    if dict_has(metadata, head_key):
        config["n_heads"] = metadata[head_key]
    # KV head count (for GQA)
    let kv_key = arch + ".attention.head_count_kv"
    config["n_heads_kv"] = config["n_heads"]
    if dict_has(metadata, kv_key):
        config["n_heads_kv"] = metadata[kv_key]
    # Vocab size
    let vocab_key = arch + ".vocab_size"
    config["vocab_size"] = 32000
    if dict_has(metadata, vocab_key):
        config["vocab_size"] = metadata[vocab_key]
    # RMSNorm epsilon
    let eps_key = arch + ".attention.layer_norm_rms_epsilon"
    config["layer_norm_eps"] = 0.00001
    if dict_has(metadata, eps_key):
        config["layer_norm_eps"] = metadata[eps_key]
    # RoPE frequency base
    let rope_key = arch + ".rope.freq_base"
    config["rope_theta"] = 10000
    if dict_has(metadata, rope_key):
        config["rope_theta"] = metadata[rope_key]
    # Head dimension
    config["d_head"] = (config["d_model"] / config["n_heads"]) | 0
    # Infer additional properties based on architecture
    config["rope"] = true
    config["bias"] = false
    config["activation"] = "silu"
    config["norm_type"] = "rms_norm"
    config["tie_weights"] = false
    config["dropout"] = 0.0
    # GPT-2 uses different defaults
    if arch == "gpt2":
        config["rope"] = false
        config["bias"] = true
        config["activation"] = "gelu"
        config["norm_type"] = "layer_norm"
        config["tie_weights"] = true
    # Phi uses different defaults
    if arch == "phi":
        config["activation"] = "gelu"
    # Sliding window (mistral)
    config["sliding_window"] = 0
    let sw_key = arch + ".attention.sliding_window"
    if dict_has(metadata, sw_key):
        config["sliding_window"] = metadata[sw_key]
    # File type / quantization info
    config["file_type"] = 0
    if dict_has(metadata, "general.file_type"):
        config["file_type"] = metadata["general.file_type"]
    return config

# ============================================================================
# Supported architectures
# ============================================================================

# Returns a list of architecture strings supported by this importer.
# These correspond to values in the "general.architecture" metadata key.
proc supported_architectures():
    let archs = []
    push(archs, "llama")
    push(archs, "gpt2")
    push(archs, "gemma")
    push(archs, "phi")
    push(archs, "qwen2")
    push(archs, "mistral")
    return archs

# Check if an architecture string is supported
proc is_supported_architecture(arch):
    let supported = supported_architectures()
    for i in range(len(supported)):
        if supported[i] == arch:
            return true
    return false

# ============================================================================
# GGUF tensor name mapping to SageGPT layer structure
# ============================================================================

# Map GGUF tensor names to SageGPT model weight keys.
# GGUF tensor names follow the pattern:
#   token_embd.weight             -> embedding table
#   blk.{i}.attn_norm.weight      -> layer i attention RMSNorm
#   blk.{i}.attn_q.weight         -> layer i query projection
#   blk.{i}.attn_k.weight         -> layer i key projection
#   blk.{i}.attn_v.weight         -> layer i value projection
#   blk.{i}.attn_output.weight    -> layer i output projection
#   blk.{i}.ffn_norm.weight       -> layer i FFN RMSNorm
#   blk.{i}.ffn_gate.weight       -> layer i SwiGLU gate projection
#   blk.{i}.ffn_up.weight         -> layer i SwiGLU up projection
#   blk.{i}.ffn_down.weight       -> layer i SwiGLU down projection
#   output_norm.weight            -> final RMSNorm
#   output.weight                 -> output projection (lm_head)
#
# SageGPT model structure (from models/sagegpt/model.sage):
#   model["embed"]                -> flat array [vocab_size * d_model]
#   model["layers"][i]["norm1"]   -> attention norm [d_model]
#   model["layers"][i]["norm2"]   -> FFN norm [d_model]
#   model["layers"][i]["q_proj"]  -> query projection [d_model * d_model]
#   model["layers"][i]["k_proj"]  -> key projection [d_model * d_model]
#   model["layers"][i]["v_proj"]  -> value projection [d_model * d_model]
#   model["layers"][i]["o_proj"]  -> output projection [d_model * d_model]
#   model["layers"][i]["gate_proj"] -> SwiGLU gate [d_model * d_ff]
#   model["layers"][i]["up_proj"]   -> SwiGLU up [d_model * d_ff]
#   model["layers"][i]["down_proj"] -> SwiGLU down [d_ff * d_model]
#   model["final_norm"]           -> final RMSNorm [d_model]
#   model["lm_head"]              -> output projection [d_model * vocab_size]

# Parse a block layer index from a GGUF tensor name like "blk.5.attn_q.weight"
# Returns the layer index or -1 if not a block tensor.
proc parse_block_index(name):
    # Check if name starts with "blk."
    if len(name) < 5:
        return -1
    if name[0] != "b":
        return -1
    if name[1] != "l":
        return -1
    if name[2] != "k":
        return -1
    if name[3] != ".":
        return -1
    # Extract the number after "blk."
    let num_str = ""
    let pos = 4
    for _ in range(len(name) - 4):
        if pos >= len(name):
            return -1
        if name[pos] == ".":
            return -1
        let c = name[pos]
        if c == ".":
            # found end of number
            if len(num_str) == 0:
                return -1
            return str_to_num(num_str)
        num_str = num_str + c
        pos = pos + 1
    return -1

# Helper to convert a numeric string to a number
proc str_to_num(s):
    let result = 0
    for i in range(len(s)):
        let c = ord(s[i])
        if c < 48:
            return result
        if c > 57:
            return result
        result = result * 10 + (c - 48)
    return result

# Get the suffix of a block tensor name (the part after "blk.N.")
proc get_block_suffix(name):
    # Skip "blk."
    let pos = 4
    # Skip number
    for _ in range(len(name) - 4):
        if pos >= len(name):
            return ""
        if name[pos] == ".":
            return ""
        let c = name[pos]
        if c == ".":
            # Return everything after this dot
            let result = ""
            for j in range(len(name) - pos - 1):
                result = result + name[pos + 1 + j]
            return result
        pos = pos + 1
    return ""

# Improved block suffix extraction - finds the second dot and returns rest
proc block_suffix(name):
    let dot_count = 0
    let start = 0
    for i in range(len(name)):
        if name[i] == ".":
            dot_count = dot_count + 1
            if dot_count == 2:
                start = i + 1
                let result = ""
                for j in range(len(name) - start):
                    result = result + name[start + j]
                return result
    return ""

# ============================================================================
# Convert GGUF data to SageGPT model format
# ============================================================================

# Convert loaded GGUF data into a SageGPT model dict compatible with
# models/sagegpt/model.sage create_model() output.
#
# gguf_data: dict with "config", "weights", "metadata" from import_gguf()
# Returns: dict matching SageGPT model structure
proc convert_to_sagegpt(gguf_data):
    let config = gguf_data["config"]
    let weights = gguf_data["weights"]
    let model = {}
    model["config"] = config
    model["tokenizer"] = nil
    let n_layers = config["n_layers"]
    let d = config["d_model"]
    # Token embedding
    if dict_has(weights, "token_embd.weight"):
        model["embed"] = weights["token_embd.weight"]["data"]
    else:
        print("WARNING: convert_to_sagegpt: missing token_embd.weight, using zeros")
        let embed = []
        let embed_size = config["vocab_size"] * d
        for i in range(embed_size):
            push(embed, 0.0)
        model["embed"] = embed
    # Per-layer weights
    let layers = []
    for layer_idx in range(n_layers):
        let l = {}
        let prefix = "blk." + str(layer_idx) + "."
        # Attention norm
        let norm1_key = prefix + "attn_norm.weight"
        if dict_has(weights, norm1_key):
            l["norm1"] = weights[norm1_key]["data"]
        else:
            let norm = []
            for i in range(d):
                push(norm, 1.0)
            l["norm1"] = norm
        # FFN norm
        let norm2_key = prefix + "ffn_norm.weight"
        if dict_has(weights, norm2_key):
            l["norm2"] = weights[norm2_key]["data"]
        else:
            let norm = []
            for i in range(d):
                push(norm, 1.0)
            l["norm2"] = norm
        # Q, K, V, O projections
        let q_key = prefix + "attn_q.weight"
        if dict_has(weights, q_key):
            l["q_proj"] = weights[q_key]["data"]
        else:
            l["q_proj"] = []
        let k_key = prefix + "attn_k.weight"
        if dict_has(weights, k_key):
            l["k_proj"] = weights[k_key]["data"]
        else:
            l["k_proj"] = []
        let v_key = prefix + "attn_v.weight"
        if dict_has(weights, v_key):
            l["v_proj"] = weights[v_key]["data"]
        else:
            l["v_proj"] = []
        let o_key = prefix + "attn_output.weight"
        if dict_has(weights, o_key):
            l["o_proj"] = weights[o_key]["data"]
        else:
            l["o_proj"] = []
        # FFN projections (SwiGLU: gate, up, down)
        let gate_key = prefix + "ffn_gate.weight"
        if dict_has(weights, gate_key):
            l["gate_proj"] = weights[gate_key]["data"]
        else:
            l["gate_proj"] = []
        let up_key = prefix + "ffn_up.weight"
        if dict_has(weights, up_key):
            l["up_proj"] = weights[up_key]["data"]
        else:
            l["up_proj"] = []
        let down_key = prefix + "ffn_down.weight"
        if dict_has(weights, down_key):
            l["down_proj"] = weights[down_key]["data"]
        else:
            l["down_proj"] = []
        push(layers, l)
    model["layers"] = layers
    # Final norm
    if dict_has(weights, "output_norm.weight"):
        model["final_norm"] = weights["output_norm.weight"]["data"]
    else:
        let norm = []
        for i in range(d):
            push(norm, 1.0)
        model["final_norm"] = norm
    # Output projection (lm_head)
    if dict_has(weights, "output.weight"):
        model["lm_head"] = weights["output.weight"]["data"]
    else:
        # Some models tie embedding and output weights
        if dict_has(weights, "token_embd.weight"):
            model["lm_head"] = weights["token_embd.weight"]["data"]
        else:
            model["lm_head"] = []
    # Rope frequencies would need to be recomputed from config
    model["rope_freqs"] = nil
    return model

# ============================================================================
# Main import function
# ============================================================================

# Import a GGUF model file.
# Reads the file, parses the header, metadata, tensor info, and weight data.
#
# filepath: path to the .gguf file
# Returns: {"config": config_dict, "weights": weights_dict, "metadata": raw_metadata_dict,
#           "tensor_infos": list_of_tensor_info, "header": header_dict}
# or nil on error.
proc import_gguf(filepath):
    print("Loading GGUF file: " + filepath)
    # Read raw file contents
    let raw = io.readfile(filepath)
    if raw == nil:
        print("ERROR: import_gguf: could not read file: " + filepath)
        return nil
    if raw == "":
        print("ERROR: import_gguf: file is empty: " + filepath)
        return nil
    # Convert string to byte array
    print("Converting to byte array (" + str(len(raw)) + " characters)...")
    let bytes = []
    for i in range(len(raw)):
        push(bytes, ord(raw[i]))
    print("File size: " + str(len(bytes)) + " bytes")
    # Parse header
    let header = parse_header(bytes)
    if header == nil:
        print("ERROR: import_gguf: failed to parse header")
        return nil
    print("GGUF v" + str(header["version"]) + ": " + str(header["tensor_count"]) + " tensors, " + str(header["metadata_count"]) + " metadata entries")
    # Read metadata
    let meta_result = read_metadata(bytes, header["offset"], header["metadata_count"])
    let metadata = meta_result["metadata"]
    let offset_after_meta = meta_result["offset"]
    # Check architecture support
    if dict_has(metadata, "general.architecture"):
        let arch = metadata["general.architecture"]
        if not is_supported_architecture(arch):
            print("WARNING: import_gguf: architecture " + chr(34) + arch + chr(34) + " may not be fully supported")
    # Extract config from metadata
    let config = extract_config(metadata)
    print("Architecture: " + config["architecture"])
    print("Model: " + config["name"])
    print("Layers: " + str(config["n_layers"]) + ", d_model: " + str(config["d_model"]) + ", heads: " + str(config["n_heads"]))
    # Read tensor info
    let tensor_result = read_tensor_info(bytes, offset_after_meta, header["tensor_count"])
    let tensor_infos = tensor_result["tensors"]
    let offset_after_tensors = tensor_result["offset"]
    print("Read " + str(len(tensor_infos)) + " tensor descriptors")
    # Calculate tensor data start (aligned to ALIGNMENT boundary)
    let alignment = GGUF_DEFAULT_ALIGNMENT
    if dict_has(metadata, "general.alignment"):
        alignment = metadata["general.alignment"]
    let tensor_data_start = offset_after_tensors
    let remainder = tensor_data_start - ((tensor_data_start / alignment) | 0) * alignment
    if remainder != 0:
        tensor_data_start = tensor_data_start + (alignment - remainder)
    print("Tensor data starts at offset " + str(tensor_data_start))
    # Load weights
    print("Loading and dequantizing weights...")
    let weights = load_weights(bytes, tensor_infos, tensor_data_start)
    print("Loaded " + str(len(dict_keys(weights))) + " tensors")
    # Try to detect vocab_size from token_embd if not in metadata
    if dict_has(weights, "token_embd.weight"):
        let embd = weights["token_embd.weight"]
        if len(embd["dims"]) >= 2:
            let detected_vocab = embd["dims"][0]
            if config["vocab_size"] == 32000:
                config["vocab_size"] = detected_vocab
    # Build result
    let result = {}
    result["config"] = config
    result["weights"] = weights
    result["metadata"] = metadata
    result["tensor_infos"] = tensor_infos
    result["header"] = header
    print("GGUF import complete.")
    return result

# ============================================================================
# Summary
# ============================================================================

# Return a human-readable summary string for a loaded GGUF model.
proc summary(gguf_data):
    let nl = chr(10)
    let config = gguf_data["config"]
    let metadata = gguf_data["metadata"]
    let header = gguf_data["header"]
    let tensor_infos = gguf_data["tensor_infos"]
    let out = "========================================" + nl
    out = out + "  GGUF Model Summary" + nl
    out = out + "========================================" + nl
    out = out + nl
    # General info
    out = out + "Format:         GGUF v" + str(header["version"]) + nl
    out = out + "Model:          " + config["name"] + nl
    out = out + "Architecture:   " + config["architecture"] + nl
    out = out + nl
    # Architecture details
    out = out + "--- Architecture ---" + nl
    out = out + "Layers:         " + str(config["n_layers"]) + nl
    out = out + "Hidden dim:     " + str(config["d_model"]) + nl
    out = out + "FFN dim:        " + str(config["d_ff"]) + nl
    out = out + "Heads:          " + str(config["n_heads"]) + nl
    out = out + "KV Heads:       " + str(config["n_heads_kv"]) + nl
    out = out + "Head dim:       " + str(config["d_head"]) + nl
    out = out + "Context:        " + str(config["context_length"]) + nl
    out = out + "Vocab size:     " + str(config["vocab_size"]) + nl
    out = out + "Activation:     " + config["activation"] + nl
    out = out + "Norm:           " + config["norm_type"] + nl
    out = out + "RoPE:           " + str(config["rope"]) + nl
    if config["rope"]:
        out = out + "RoPE theta:     " + str(config["rope_theta"]) + nl
    if config["sliding_window"] > 0:
        out = out + "Sliding window: " + str(config["sliding_window"]) + nl
    out = out + nl
    # Tensor summary
    out = out + "--- Tensors ---" + nl
    out = out + "Total tensors:  " + str(len(tensor_infos)) + nl
    # Count by type
    let type_counts = {}
    let total_elements = 0
    let total_bytes_est = 0
    for i in range(len(tensor_infos)):
        let info = tensor_infos[i]
        let tname = ggml_type_name(info["type"])
        if dict_has(type_counts, tname):
            type_counts[tname] = type_counts[tname] + 1
        else:
            type_counts[tname] = 1
        total_elements = total_elements + info["n_elements"]
        total_bytes_est = total_bytes_est + tensor_data_size(info["type"], info["n_elements"])
    let type_keys = dict_keys(type_counts)
    for i in range(len(type_keys)):
        let k = type_keys[i]
        out = out + "  " + k + ": " + str(type_counts[k]) + " tensors" + nl
    out = out + "Total elements: " + str(total_elements) + nl
    # Format file size
    if total_bytes_est >= 1073741824:
        out = out + "Est. data size: " + str((total_bytes_est / 1073741824 * 10 + 0.5) | 0) + " GB" + nl
    else:
        if total_bytes_est >= 1048576:
            out = out + "Est. data size: " + str((total_bytes_est / 1048576 + 0.5) | 0) + " MB" + nl
        else:
            out = out + "Est. data size: " + str((total_bytes_est / 1024 + 0.5) | 0) + " KB" + nl
    # Parameter count estimate
    let params = total_elements
    if params >= 1000000000:
        out = out + "Parameters:     ~" + str((params / 100000000 + 0.5) | 0) + "B" + nl
    else:
        if params >= 1000000:
            out = out + "Parameters:     ~" + str((params / 1000000 + 0.5) | 0) + "M" + nl
        else:
            out = out + "Parameters:     ~" + str((params / 1000 + 0.5) | 0) + "K" + nl
    out = out + nl
    # Selected metadata
    out = out + "--- Metadata ---" + nl
    let meta_keys = dict_keys(metadata)
    let shown = 0
    for i in range(len(meta_keys)):
        let k = meta_keys[i]
        let v = metadata[k]
        # Skip large arrays (tokenizer tokens, scores, etc.)
        if type(v) == "array":
            if len(v) > 10:
                out = out + "  " + k + ": [array, " + str(len(v)) + " elements]" + nl
                shown = shown + 1
                continue
        out = out + "  " + k + ": " + str(v) + nl
        shown = shown + 1
        # Cap at 50 entries to keep summary readable
        if shown >= 50:
            out = out + "  ... (" + str(len(meta_keys) - shown) + " more entries)" + nl
            return out + "========================================" + nl
    out = out + "========================================" + nl
    return out

# ============================================================================
# Utility functions
# ============================================================================

# List all tensor names in the loaded GGUF data
proc list_tensors(gguf_data):
    let tensor_infos = gguf_data["tensor_infos"]
    let names = []
    for i in range(len(tensor_infos)):
        push(names, tensor_infos[i]["name"])
    return names

# Get info about a specific tensor by name
proc get_tensor_info(gguf_data, name):
    let tensor_infos = gguf_data["tensor_infos"]
    for i in range(len(tensor_infos)):
        if tensor_infos[i]["name"] == name:
            return tensor_infos[i]
    return nil

# Check if the loaded GGUF data is compatible with SageGPT conversion
proc is_compatible(gguf_data):
    let config = gguf_data["config"]
    let arch = config["architecture"]
    if not is_supported_architecture(arch):
        return false
    # Check for essential tensors
    let weights = gguf_data["weights"]
    if not dict_has(weights, "token_embd.weight"):
        return false
    # Check for at least one block
    if not dict_has(weights, "blk.0.attn_q.weight"):
        return false
    return true

# Estimate memory required to hold the dequantized model in float32
proc estimate_memory(gguf_data):
    let tensor_infos = gguf_data["tensor_infos"]
    let total = 0
    for i in range(len(tensor_infos)):
        total = total + tensor_infos[i]["n_elements"] * 4
    return total

# Format a byte count as a human-readable string
proc format_bytes(n):
    if n >= 1073741824:
        return str((n / 1073741824 * 10 + 0.5) | 0) + " GB"
    if n >= 1048576:
        return str((n / 1048576 + 0.5) | 0) + " MB"
    if n >= 1024:
        return str((n / 1024 + 0.5) | 0) + " KB"
    return str(n) + " B"
