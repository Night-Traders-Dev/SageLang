# RUN: bytecode-run
# EXPECT: 10
# EXPECT: 11
# EXPECT: 7
# EXPECT: 2
# EXPECT: 8
# EXPECT: bytecode

let total = 0
let i = 0

while i < 5:
    total = total + i
    i = i + 1

print total

let bits = (0b1010 & 0b1110) | 0b0001
print bits

let arr = [3, 4]
print arr[0] + arr[1]

let stats = {"hp": 2}
print stats["hp"]

print (8 >> 1) + (1 << 2)
print "byte" + "code"
