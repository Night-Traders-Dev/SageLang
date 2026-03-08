# Test ffi_sym for checking symbol existence
# EXPECT: true
# EXPECT: false

let math = ffi_open("libm.so.6")
print ffi_sym(math, "sqrt")
print ffi_sym(math, "nonexistent_function")
ffi_close(math)
