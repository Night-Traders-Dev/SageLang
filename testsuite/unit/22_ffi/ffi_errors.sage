# EXPECT: true
# EXPECT: false
# EXPECT: false

let math = ffi_open("libm.so.6")
print ffi_sym(math, "sin")
print ffi_sym(math, "invalid_symbol_foo")
print ffi_sym(math, "invalid_symbol_bar")
ffi_close(math)
