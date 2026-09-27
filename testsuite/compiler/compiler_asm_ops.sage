# Exercises every rv64 instruction the AOT emitter can actually reach.
#
# `not` is deliberately absent: core/src/c/parser.c builds `not x` as a binary
# expression with a NULL right operand, which instruction selection cannot
# handle, so VINST_NOT is unreachable from source for every native target.
# Unary minus desugars to `0 - x`, so it appears here as SUB rather than NEG.
# Function calls are absent because validate_native_program rejects VINST_CALL
# and VINST_CALL_BUILTIN as unsafe to call natively.
let a = 7
let b = 3

print a + b
print a - b
print a * b
print a / b
print a % b
print -b

print a > b
print a < b
print a >= b
print a <= b
print a == b
print a != b

let greeting = "hello"
print greeting

let flag = true
print flag

print (a > 1) and (b < 5)
print (a > 10) or (b < 5)

# re-read the globals, to prove STORE_GLOBAL then LOAD_GLOBAL agree
print a
print b
print greeting
