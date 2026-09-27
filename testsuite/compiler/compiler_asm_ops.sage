# Exercises every rv64 instruction the AOT emitter can actually reach.
#
# `not` was listed as broken here until instruction selection learned to lower
# it; core/src/c/parser.c builds `not x` as a binary node with a NULL right
# operand, which only the C and LLVM backends had handled. It is now VINST_NOT
# on the native path too, so it is covered below.
#
# Unary minus desugars to `0 - x` in the parser, so it appears as SUB.
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

print not (a > 1)
print not (a > 100)
print not true
print not false

# re-read the globals, to prove STORE_GLOBAL then LOAD_GLOBAL agree
print a
print b
print greeting
