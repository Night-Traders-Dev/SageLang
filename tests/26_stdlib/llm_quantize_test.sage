gc_disable()
# EXPECT: int8
# EXPECT: true
# EXPECT: int4
# EXPECT: true

import llm.quantize

# Int8 quantization
let weights = [0.5, -0.3, 0.8, -0.1, 0.6]
let q8 = quantize.quantize_int8(weights)
print q8["dtype"]
let dq8 = quantize.dequantize_int8(q8)
let err8 = quantize.quantization_error(weights, dq8)
print err8["rmse"] < 0.01

# Int4 quantization
let q4 = quantize.quantize_int4(weights, 4)
print q4["dtype"]
let dq4 = quantize.dequantize_int4(q4)
let err4 = quantize.quantization_error(weights, dq4)
print err4["rmse"] < 0.1
