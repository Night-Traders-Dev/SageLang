# Test FFI with libm math functions
# EXPECT: 4
# EXPECT: 1024
# EXPECT: 5
# EXPECT: 4

let math = ffi_open("libm.so.6")
print ffi_call(math, "sqrt", "double", [16.0])
print ffi_call(math, "pow", "double", [2.0, 10.0])
print ffi_call(math, "ceil", "double", [4.3])
print ffi_call(math, "floor", "double", [4.7])
ffi_close(math)
